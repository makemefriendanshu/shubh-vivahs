defmodule ShubhVivahs.Photos.Importer do
  @moduledoc """
  Adds a folder of photos (JPEGs, searched recursively, in path order) to a
  photo album — creating the album on first import, adding new photos to
  it on later runs (photos already imported are skipped).

  Originals are **moved** into `Photos.storage_dir/0` (same disk, so it is
  instant and needs no extra space), then a web-sized copy and a thumbnail
  are made from each — upright, since `Evision.imread/1` applies the
  camera's EXIF rotation.
  """

  require Logger
  import Ecto.Query

  alias ShubhVivahs.FaceDetection
  alias ShubhVivahs.Photos
  alias ShubhVivahs.Photos.{Album, Photo}
  alias ShubhVivahs.Repo

  @extensions ~w(.jpg .jpeg)

  @doc """
  Imports every JPEG under `source` into the album titled `title`. Calls
  `on_progress.(done, total)` as derivatives are made. Returns
  `{:ok, album, %{imported: n, skipped: n, failed: n}}`.
  """
  def import_dir(source, title, on_progress \\ fn _done, _total -> :ok end) do
    files = source |> Path.expand() |> walk() |> Enum.filter(&jpeg?/1) |> Enum.sort()
    album = find_or_create_album(title)
    File.mkdir_p!(Path.join(Photos.album_dir(album), "originals"))
    File.mkdir_p!(Path.join(Photos.album_dir(album), "web"))
    File.mkdir_p!(Path.join(Photos.album_dir(album), "thumbs"))

    already =
      Repo.all(from p in Photo, where: p.source_path in ^files, select: p.source_path)
      |> MapSet.new()

    {new_files, skipped} = Enum.split_with(files, &(not MapSet.member?(already, &1)))

    next_position =
      (Repo.one(from p in Photo, where: p.album_id == ^album.id, select: max(p.position)) || 0) +
        1

    # Moving originals and inserting rows is quick and sequential; making
    # the copies is CPU-bound, so that part runs a few at a time.
    photos =
      new_files
      |> Enum.with_index(next_position)
      |> Enum.map(fn {file, position} -> move_and_insert(album, file, position) end)
      |> Enum.reject(&is_nil/1)

    total = length(photos)

    results =
      photos
      |> Task.async_stream(&make_copies/1, max_concurrency: 3, timeout: :infinity, ordered: false)
      |> Stream.with_index(1)
      |> Enum.map(fn {{:ok, result}, done} ->
        on_progress.(done, total)
        result
      end)

    for {:ok, photo, {w, h}} <- results do
      photo |> Photo.changeset(%{width: w, height: h}) |> Repo.update!()
    end

    album = ensure_cover(album)
    failed = Enum.count(results, &match?({:error, _, _}, &1))

    {:ok, album,
     %{
       imported: total - failed,
       skipped: length(skipped),
       failed: failed + (length(new_files) - total)
     }}
  end

  @doc "(Re)makes a photo's web copy and thumbnail. Returns `{:ok, photo, {width, height}}` or `{:error, photo, reason}`."
  def make_copies(%Photo{} = photo) do
    with %Evision.Mat{} = img <- Evision.imread(Photos.original_path(photo)) do
      {h, w, _} = Evision.Mat.shape(img)
      web = scale_to(img, w, h, Photos.web_max_px())
      {wh, ww, _} = Evision.Mat.shape(web)
      thumb = scale_to(web, ww, wh, Photos.thumb_max_px())
      write_jpeg(Photos.web_path(photo), web, 80)
      write_jpeg(Photos.thumb_path(photo), thumb, 75)
      {:ok, photo, {w, h}}
    else
      other ->
        Logger.error("Could not read #{Photos.original_path(photo)}: #{inspect(other)}")
        {:error, photo, other}
    end
  end

  defp scale_to(img, w, h, max_px) when max(w, h) <= max_px, do: img

  defp scale_to(img, w, h, max_px) do
    scale = max_px / max(w, h)

    Evision.resize(img, {round(w * scale), round(h * scale)},
      interpolation: Evision.Constant.cv_INTER_AREA()
    )
  end

  defp write_jpeg(path, img, quality) do
    true =
      Evision.imwrite(path, img, params: [Evision.Constant.cv_IMWRITE_JPEG_QUALITY(), quality])
  end

  defp move_and_insert(album, file, position) do
    name = Path.basename(file)
    padded = position |> Integer.to_string() |> String.pad_leading(5, "0")
    relative = Path.join(["#{album.id}", "originals", "#{padded}-#{name}"])
    dest = Path.join(Photos.storage_dir(), relative)

    with :ok <- move(file, dest),
         {:ok, photo} <-
           %Photo{}
           |> Photo.changeset(%{
             album_id: album.id,
             original_path: relative,
             original_name: name,
             source_path: file,
             position: position
           })
           |> Repo.insert() do
      photo
    else
      error ->
        Logger.error("Could not import #{file}: #{inspect(error)}")
        # Put the original back if it had already moved.
        if File.regular?(dest) and not File.exists?(file), do: File.rename(dest, file)
        nil
    end
  end

  # Same disk: an instant rename. Across disks: copy, then remove.
  defp move(from, to) do
    case File.rename(from, to) do
      :ok ->
        :ok

      {:error, :exdev} ->
        with :ok <- File.cp(from, to), do: File.rm(from)

      error ->
        error
    end
  end

  defp find_or_create_album(title) do
    Repo.get_by(Album, title: title) ||
      %Album{}
      |> Album.changeset(%{
        title: title,
        slug: Photos.unique_slug(title),
        public: false,
        user_id: owner_user_id()
      })
      |> Repo.insert!()
  end

  defp ensure_cover(%Album{cover_photo_id: nil} = album) do
    case Photos.photo_at(album, 0) do
      nil -> album
      photo -> album |> Album.changeset(%{cover_photo_id: photo.id}) |> Repo.update!()
    end
  end

  defp ensure_cover(album), do: album

  # Copied in directly, not uploaded through the site: credit the site owner.
  defp owner_user_id do
    id = FaceDetection.owner_user_id()
    if Repo.get(ShubhVivahs.Accounts.User, id), do: id
  end

  # "._IMG.JPG" files are macOS metadata left on copied drives, not photos.
  defp jpeg?(path) do
    (path |> Path.extname() |> String.downcase()) in @extensions and
      not String.starts_with?(Path.basename(path), "._")
  end

  defp walk(path) do
    if File.dir?(path),
      do: path |> File.ls!() |> Enum.flat_map(&walk(Path.join(path, &1))),
      else: [path]
  end
end
