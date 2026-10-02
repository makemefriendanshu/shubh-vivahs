defmodule ShubhVivahs.VideoUpload do
  @moduledoc """
  Real video upload, done in chunks so a single HTTP request never has to
  carry more than `chunk_size/0` bytes — Cloudflare (and most reverse
  proxies) cap request bodies well below what a real wedding video weighs
  in at, 100MB on Cloudflare's free/pro tiers, regardless of what
  `Plug.Parsers`' own `:length` option allows. UploadPage's browser-side
  JS slices the file and POSTs each piece to
  `ShubhVivahsWeb.VideoUploadController.create_chunk/2` sequentially,
  then calls `finalize/2` (via `VideoUploadController.finalize/2`) once
  every piece has landed. Chunks live under a temp dir keyed by a
  browser-generated `upload_id` (a v4 UUID, validated with
  `valid_upload_id?/1` before ever touching the filesystem — it becomes
  part of a file path, so it's never trusted as-is) and get concatenated
  back into one file, in order, before a `Movie` row is inserted for it.

  Ingestion (`FaceDetection.ingest_video/2` — frame extraction and face
  detection) runs afterward in a background `Task.Supervisor` child, not
  inline in the finalize request, since it can take a while; the movie
  shows up right away with `status: "pending"` and moves through
  "processing" to "done"/"failed" for real as that finishes, the same
  lifecycle every other listing already displays. It also starts
  `public: false` — hidden from Home/Premiere Hall/the nav dropdown until
  someone flips it public from Dashboard/UploadPage (see
  `FaceDetection.set_movie_visibility/2`) — so a fresh upload doesn't show
  up to anonymous visitors before its owner is ready to show it off.

  If the browser-side JS cancels mid-upload (see UploadPage's "Cancel
  Upload" button), it calls `VideoUploadController.abort/2`, which routes
  here to `abort/1` — otherwise chunks already sent for that `upload_id`
  would sit under the temp dir forever, since `finalize/3` (the only
  other thing that cleans them up) never runs for an upload that was
  never completed.
  """

  require Logger
  import Ecto.Query

  alias ShubhVivahs.Accounts
  alias ShubhVivahs.Accounts.User
  alias ShubhVivahs.FaceDetection
  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.Repo

  @allowed_extensions ~w(.mp4 .mov .webm .mkv .m4v)
  @max_bytes 5_000_000_000
  @chunk_size 40_000_000
  @max_chunks ceil(@max_bytes / @chunk_size) + 1
  @upload_id_pattern ~r/^[a-zA-Z0-9-]{1,64}$/

  @doc "Accepted video file extensions, for display in the upload form's helper text."
  def allowed_extensions, do: @allowed_extensions

  @doc "Max total upload size in bytes, across all chunks combined."
  def max_bytes, do: @max_bytes

  @doc "Max size in bytes the browser-side JS should slice each chunk down to."
  def chunk_size, do: @chunk_size

  @doc """
  Stores one chunk of an in-progress upload. `upload_id` must already be
  a well-formed id (see `valid_upload_id?/1`) — callers are expected to
  reject anything else before this ever runs. Returns `:ok` or
  `{:error, message}`.
  """
  @spec store_chunk(String.t(), non_neg_integer, non_neg_integer, Plug.Upload.t()) ::
          :ok | {:error, String.t()}
  def store_chunk(upload_id, chunk_index, total_chunks, %Plug.Upload{path: tmp_path}) do
    cond do
      not valid_upload_id?(upload_id) ->
        {:error, "Invalid upload session — please reload the page and try again."}

      not (is_integer(chunk_index) and chunk_index >= 0) ->
        {:error, "Invalid chunk."}

      not (is_integer(total_chunks) and total_chunks > 0 and total_chunks <= @max_chunks) ->
        {:error, "Invalid upload — please reload the page and try again."}

      chunk_index >= total_chunks ->
        {:error, "Invalid chunk."}

      true ->
        dir = chunk_dir(upload_id)
        File.mkdir_p!(dir)
        File.cp!(tmp_path, chunk_path(upload_id, chunk_index))
        :ok
    end
  end

  @doc """
  Concatenates every previously stored chunk for `upload_id` (there must
  be exactly `total_chunks` of them, `0`-indexed) back into one file
  under its final name, inserts a `Movie` row for it (`status:
  "pending"`), and kicks off background ingestion. Returns `{:ok,
  movie}` or `{:error, message}`; either way, the chunk temp dir is
  removed.
  """
  @spec finalize(String.t(), String.t(), non_neg_integer, User.t()) ::
          {:ok, Movie.t()} | {:error, String.t()}
  def finalize(upload_id, filename, total_chunks, %User{} = user) do
    ext = filename |> Path.extname() |> String.downcase()
    dir = chunk_dir(upload_id)

    cond do
      not valid_upload_id?(upload_id) ->
        {:error, "Invalid upload session — please reload the page and try again."}

      ext not in @allowed_extensions ->
        cleanup(dir)
        {:error, "Please upload an #{format_extensions()} file."}

      not (is_integer(total_chunks) and total_chunks > 0 and total_chunks <= @max_chunks) ->
        cleanup(dir)
        {:error, "Invalid upload — please reload the page and try again."}

      not all_chunks_present?(upload_id, total_chunks) ->
        cleanup(dir)
        {:error, "Upload is incomplete — please try again."}

      true ->
        assemble(upload_id, dir, filename, ext, total_chunks, user)
    end
  end

  defp assemble(upload_id, dir, filename, ext, total_chunks, user) do
    title = title_from_filename(filename, ext)
    tmp_dest = destination_path(title, ext, user)
    File.mkdir_p!(Path.dirname(tmp_dest))

    File.open!(tmp_dest, [:write, :binary], fn dest_io ->
      for i <- 0..(total_chunks - 1) do
        IO.binwrite(dest_io, File.read!(chunk_path(upload_id, i)))
      end
    end)

    cleanup(dir)

    if File.stat!(tmp_dest).size > @max_bytes do
      File.rm(tmp_dest)
      {:error, "Video must be smaller than #{div(@max_bytes, 1_000_000)}MB."}
    else
      %Movie{}
      |> Movie.changeset(%{
        path: tmp_dest,
        title: title,
        status: "pending",
        public: false,
        user_id: user.id
      })
      |> Repo.insert()
      |> case do
        {:ok, movie} ->
          # The final filename is keyed by `movie.id` (see
          # `id_filename/3`) so it stays sorted by upload order even
          # after an admin rename — but the id doesn't exist until
          # after this insert, so the file gets one more rename right
          # here from its provisional `tmp_dest` name.
          {:ok, movie} = settle_path(movie, tmp_dest, ext)
          start_ingestion(movie.path, title)
          {:ok, movie}

        {:error, _changeset} ->
          File.rm(tmp_dest)
          {:error, "Couldn't save this upload — please try again."}
      end
    end
  end

  defp settle_path(movie, tmp_dest, ext) do
    final_path = Path.join(Path.dirname(tmp_dest), id_filename(movie.id, movie.title, ext))

    if final_path == tmp_dest do
      {:ok, movie}
    else
      File.rename!(tmp_dest, final_path)
      movie |> Movie.changeset(%{path: final_path}) |> Repo.update()
    end
  end

  @doc """
  Renames `movie`'s on-disk file to match `new_title`, keeping it in the
  same per-user directory, so an admin-authored rename
  (`FaceDetection.rename_movie/2`) stays reflected on disk — not just in
  the title shown everywhere. Returns the (possibly unchanged) path to
  store on the movie. A no-op, returning `movie.path` as-is, when
  there's nothing to rename: `path` is `nil`, the file isn't actually
  there, it lives outside `uploads_dir()` entirely (the handful of seed
  movies that predate this feature, see the `movies.user_id` migration),
  or the new name is identical to the old one.
  """
  @spec rename_for_title(Movie.t(), String.t()) :: String.t() | nil
  def rename_for_title(%Movie{id: id, path: path}, new_title) when is_binary(path) do
    if String.starts_with?(path, uploads_dir() <> "/") and File.regular?(path) do
      ext = Path.extname(path)
      dir = Path.dirname(path)
      new_path = Path.join(dir, id_filename(id, new_title, ext))

      if new_path == path do
        path
      else
        File.rename!(path, new_path)
        new_path
      end
    else
      path
    end
  end

  def rename_for_title(%Movie{path: path}, _new_title), do: path

  @doc """
  Moves `movie`'s file into managed storage under `user`'s per-user
  folder, named the same way `rename_for_title/2` would — for movies
  that predate this app's upload feature and still live wherever they
  were originally ingested from (see the `movies.user_id` migration).
  Returns the new path, or `movie.path` unchanged if it's already under
  `uploads_dir()` or the file isn't actually there.
  """
  @spec adopt_into_uploads(Movie.t(), User.t()) :: String.t() | nil
  def adopt_into_uploads(%Movie{id: id, path: path, title: title}, %User{} = user)
      when is_binary(path) do
    if String.starts_with?(path, uploads_dir() <> "/") or not File.regular?(path) do
      path
    else
      dest_dir = Path.join(uploads_dir(), user_dir(user))
      File.mkdir_p!(dest_dir)
      new_path = Path.join(dest_dir, id_filename(id, title, Path.extname(path)))
      File.rename!(path, new_path)
      new_path
    end
  end

  def adopt_into_uploads(%Movie{path: path}, _user), do: path

  @doc """
  Renames `user`'s managed uploads folder (if they have one) to match
  their current `user_dir/1` and updates every one of their movies'
  `path` to match — so a tier/user-type change (`Accounts.set_superuser/2`)
  stays reflected on disk, not just in any freshly-saved file going
  forward. A no-op if the folder already matches or the user has never
  uploaded anything.
  """
  @spec resync_user_dir(User.t()) :: :ok
  def resync_user_dir(%User{id: id} = user) do
    dir = uploads_dir()
    new_dir = Path.join(dir, user_dir(user))

    existing =
      if File.dir?(dir) do
        Enum.find(File.ls!(dir), fn name ->
          String.starts_with?(name, "#{id}-") and Path.join(dir, name) != new_dir
        end)
      end

    if existing do
      old_dir = Path.join(dir, existing)
      File.rename!(old_dir, new_dir)

      Repo.all(
        from m in Movie, where: m.user_id == ^id and like(m.path, ^"#{old_dir}/%")
      )
      |> Enum.each(fn movie ->
        new_path = String.replace_prefix(movie.path, old_dir, new_dir)
        movie |> Movie.changeset(%{path: new_path}) |> Repo.update!()
      end)
    end

    :ok
  end

  # Zero-padded so lexical sort (filesystem listings, `ls`, etc.) matches
  # upload order even once ids cross a digit boundary (9 vs 10) — the id
  # itself never changes across a rename, unlike a timestamp would, so
  # this is what keeps sort order stable through the rename flow above.
  defp id_filename(id, title, ext) do
    padded_id = id |> Integer.to_string() |> String.pad_leading(6, "0")
    safe_title = title |> String.trim() |> filesystem_safe()
    "#{padded_id}-#{safe_title}#{ext}"
  end

  @doc """
  Discards every chunk stored so far for `upload_id` (a user-initiated
  cancel) so an abandoned upload does not sit on disk indefinitely.
  Always returns `:ok`, including for an unrecognized or already-cleaned
  `upload_id` — canceling something that is not there is not an error.
  """
  @spec abort(String.t()) :: :ok
  def abort(upload_id) do
    if valid_upload_id?(upload_id) do
      cleanup(chunk_dir(upload_id))
    end

    :ok
  end

  @doc "True for a browser-generated upload id safe to use in a filesystem path."
  @spec valid_upload_id?(term) :: boolean
  def valid_upload_id?(upload_id) when is_binary(upload_id),
    do: Regex.match?(@upload_id_pattern, upload_id)

  def valid_upload_id?(_other), do: false

  defp all_chunks_present?(upload_id, total_chunks) do
    Enum.all?(0..(total_chunks - 1), fn i ->
      upload_id |> chunk_path(i) |> File.regular?()
    end)
  end

  defp cleanup(dir), do: File.rm_rf(dir)

  defp start_ingestion(path, title) do
    Task.Supervisor.start_child(ShubhVivahs.TaskSupervisor, fn ->
      case FaceDetection.ingest_video(path, title: title) do
        {:ok, _movie} -> :ok
        {:error, reason} -> Logger.error("Video ingest failed for #{path}: #{inspect(reason)}")
      end

      # Runs outside any Hologram command/action (this is a plain Task), so
      # `put_broadcast/4` (which needs a `%Hologram.Server{}`) isn't
      # available here — `Hologram.Realtime.broadcast_action/2` is the
      # public API for exactly this case, matching how
      # `ShubhVivahs.Analytics.record_visit/1` pushes
      # `:page_visits_changed` from outside a handler. DashboardPage and
      # UploadPage both subscribe to `:movies_changed` so their movie
      # lists/status badges update live instead of needing a manual
      # reload once curation finishes (or fails).
      Hologram.Realtime.broadcast_action(:movies_changed, :movies_updated)
    end)
  end

  defp chunk_dir(upload_id), do: Path.join(chunks_root(), upload_id)

  defp chunk_path(upload_id, chunk_index) do
    Path.join(
      chunk_dir(upload_id),
      "chunk_" <> String.pad_leading(Integer.to_string(chunk_index), 6, "0")
    )
  end

  defp destination_path(title, ext, user) do
    safe_title = title |> String.trim() |> filesystem_safe()
    unique = "#{System.system_time(:second)}-#{System.unique_integer([:positive])}"

    Path.expand(
      Path.join([uploads_dir(), user_dir(user), "#{unique}-#{safe_title}#{ext}"])
    )
  end

  # "User type" and "tier" both collapse to the one real distinction this
  # app has — `Accounts.superuser?/1` (see DashboardPage's moduledoc: "no
  # fake paid-tier names exist on the `User` schema") — but are spelled
  # out as separate folder segments since that's how Dashboard already
  # presents them to the account itself (a "Superuser" badge plus a
  # separate "Premium"/"Get Premium" line).
  @doc false
  @spec user_dir(User.t()) :: String.t()
  def user_dir(%User{id: id, name: name} = user) do
    user_type = if Accounts.superuser?(user), do: "Superuser", else: "User"
    tier = if Accounts.premium?(user), do: "Premium", else: "Free"
    "#{id}-#{filesystem_safe(name)}-#{user_type}-#{tier}"
  end

  defp filesystem_safe(string), do: String.replace(string, ~r/[^a-zA-Z0-9_-]+/, "_")

  defp title_from_filename(filename, ext) do
    filename
    |> Path.basename(ext)
    |> String.replace(~r/[_-]+/, " ")
    |> String.trim()
  end

  defp format_extensions do
    [last | rest] =
      @allowed_extensions
      |> Enum.map(&(&1 |> String.trim_leading(".") |> String.upcase()))
      |> Enum.reverse()

    (Enum.reverse(rest) |> Enum.join(", ")) <> ", or " <> last
  end

  defp uploads_dir, do: Path.join(:code.priv_dir(:shubh_vivahs), "face_detection/uploads")
  defp chunks_root, do: Path.join(uploads_dir(), "tmp")
end
