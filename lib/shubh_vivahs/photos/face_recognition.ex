defmodule ShubhVivahs.Photos.FaceRecognition do
  @moduledoc """
  Finds the people in a photo album: detects faces in every photo's web
  copy (`FaceDetection.ModelServer`, YuNet + SFace), groups them into
  people across the whole album (`FaceDetection.Clustering`), and saves a
  cropped portrait per person for the "Who's in focus?" panel and the
  admin page.

  Re-running replaces the album's people — and with them their focus
  votes — but keeps names: a new person whose face matches a named one
  from the previous run gets that name back.
  """

  require Logger
  import Ecto.Query

  alias ShubhVivahs.FaceDetection.{Clustering, ModelServer}
  alias ShubhVivahs.Photos
  alias ShubhVivahs.Photos.{Album, AlbumJobs, Detection, Face, Photo}
  alias ShubhVivahs.Repo

  # Faces smaller than this (in web-copy pixels, shorter side) are
  # background people: too few pixels for a reliable embedding.
  @min_face_px 32
  # Real faces score 0.85+; below 0.8 it is mostly hands, fabric, prints.
  @min_confidence 0.8
  # Same-person threshold for carrying a name over from a previous run.
  @rename_threshold 0.5
  @portrait_px 200
  @padding_ratio 0.25

  @doc """
  Runs recognition for `album`. Returns `{:ok, %{photos: n, faces: n, people: n}}`
  or `{:error, reason}`. Progress goes to `AlbumJobs` (kind "recognition").
  """
  def run(%Album{} = album) do
    AlbumJobs.start(album.id, "recognition")
    report = AlbumJobs.reporter(album.id, "recognition")
    set_status(album, "processing")

    photos =
      Repo.all(from p in Photo, where: p.album_id == ^album.id, order_by: [asc: p.position])

    with {:ok, detections} <- detect_all(photos, report) do
      report.("Grouping faces", 0.95)
      clusters = Clustering.cluster(detections)
      people = persist(album, clusters)
      report.("Cropping portraits", 0.98)
      File.rm_rf!(Path.join(Photos.album_dir(album), "faces"))
      Enum.each(people, &write_portrait/1)
      set_status(album, "done")
      AlbumJobs.finish(album.id, "recognition")
      {:ok, %{photos: length(photos), faces: length(detections), people: length(people)}}
    else
      {:error, reason} = error ->
        set_status(album, "failed")
        AlbumJobs.fail(album.id, "recognition", reason)
        error
    end
  rescue
    exception ->
      set_status(album, "failed")
      AlbumJobs.fail(album.id, "recognition", Exception.message(exception))
      reraise exception, __STACKTRACE__
  end

  defp detect_all(photos, report) do
    total = max(length(photos), 1)

    photos
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {photo, index}, {:ok, acc} ->
      report.("Detecting faces", 0.95 * index / total)

      case ModelServer.detect_faces(Photos.web_path(photo)) do
        {:ok, faces} ->
          found =
            faces
            |> Enum.filter(fn %{bbox: {_x, _y, w, h}, confidence: c} ->
              min(w, h) >= @min_face_px and c >= @min_confidence
            end)
            |> Enum.map(&Map.put(&1, :photo_id, photo.id))

          {:cont, {:ok, Enum.reverse(found, acc)}}

        {:error, :models_not_found} = error ->
          {:halt, error}

        {:error, reason} ->
          Logger.warning("Face detection failed for photo #{photo.id}: #{inspect(reason)}")
          {:cont, {:ok, acc}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  # Returns each new person as {face, best_detection} for the portrait.
  defp persist(album, clusters) do
    named =
      Repo.all(from f in Face, where: f.album_id == ^album.id and not is_nil(f.label))

    {:ok, people} =
      Repo.transaction(fn ->
        Repo.delete_all(from f in Face, where: f.album_id == ^album.id)

        # Most-seen people first, so ids (and the admin page's default
        # order) follow how often someone appears.
        clusters
        |> Enum.sort_by(&(-length(&1.members)))
        |> Enum.map(fn cluster ->
          name = carried_name(named, cluster.centroid)

          face =
            %Face{}
            |> Face.changeset(%{
              album_id: album.id,
              embedding: cluster.centroid,
              label: name && name.label,
              subtitle: name && name.subtitle
            })
            |> Repo.insert!()

          for d <- cluster.members do
            {x, y, w, h} = d.bbox

            %Detection{}
            |> Detection.changeset(%{
              photo_id: d.photo_id,
              face_id: face.id,
              bbox_x: x,
              bbox_y: y,
              bbox_w: w,
              bbox_h: h,
              confidence: d.confidence,
              embedding: d.embedding
            })
            |> Repo.insert!()
          end

          {face, Enum.max_by(cluster.members, &portrait_score/1)}
        end)
      end)

    people
  end

  defp carried_name([], _centroid), do: nil

  defp carried_name(named, centroid) do
    {face, similarity} =
      named
      |> Enum.map(&{&1, cosine(&1.embedding, centroid)})
      |> Enum.max_by(&elem(&1, 1))

    if similarity >= @rename_threshold, do: face
  end

  # Prefer big, confident, front-on faces for the portrait.
  defp portrait_score(%{bbox: {_x, _y, w, h}, confidence: c}), do: c * w * h

  defp write_portrait({face, detection}) do
    photo = Repo.get!(Photo, detection.photo_id)

    with %Evision.Mat{} = img <- Evision.imread(Photos.web_path(photo)) do
      path = Photos.face_path(face)
      File.mkdir_p!(Path.dirname(path))
      crop = crop_with_padding(img, detection.bbox)
      Evision.imwrite(path, Evision.resize(crop, {@portrait_px, @portrait_px}))
    end
  end

  defp crop_with_padding(img, {x, y, w, h}) do
    {img_h, img_w, _} = Evision.Mat.shape(img)
    side = max(w, h) * (1 + 2 * @padding_ratio)
    cx = x + w / 2
    cy = y + h / 2
    left = (cx - side / 2) |> max(0) |> round()
    top = (cy - side / 2) |> max(0) |> round()
    right = (cx + side / 2) |> min(img_w) |> round()
    bottom = (cy + side / 2) |> min(img_h) |> round()
    Evision.Mat.roi(img, {left, top, max(right - left, 1), max(bottom - top, 1)})
  end

  defp cosine(a, b) do
    dot = a |> Enum.zip(b) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end)
    dot / (norm(a) * norm(b))
  end

  defp norm(v), do: :math.sqrt(Enum.reduce(v, 0.0, &(&1 * &1 + &2)))

  defp set_status(album, status) do
    Repo.update_all(from(a in Album, where: a.id == ^album.id), set: [status: status])
  end
end
