defmodule PhoenixHologram.VideoUpload do
  @moduledoc """
  Real video upload, done in chunks so a single HTTP request never has to
  carry more than `chunk_size/0` bytes — Cloudflare (and most reverse
  proxies) cap request bodies well below what a real wedding video weighs
  in at, 100MB on Cloudflare's free/pro tiers, regardless of what
  `Plug.Parsers`' own `:length` option allows. UploadPage's browser-side
  JS slices the file and POSTs each piece to
  `PhoenixHologramWeb.VideoUploadController.create_chunk/2` sequentially,
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
  lifecycle every other listing already displays.
  """

  require Logger

  alias PhoenixHologram.FaceDetection
  alias PhoenixHologram.FaceDetection.Movie
  alias PhoenixHologram.Repo

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
  @spec finalize(String.t(), String.t(), non_neg_integer) ::
          {:ok, Movie.t()} | {:error, String.t()}
  def finalize(upload_id, filename, total_chunks) do
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
        assemble(upload_id, dir, filename, ext, total_chunks)
    end
  end

  defp assemble(upload_id, dir, filename, ext, total_chunks) do
    dest = destination_path(filename, ext)
    File.mkdir_p!(uploads_dir())

    File.open!(dest, [:write, :binary], fn dest_io ->
      for i <- 0..(total_chunks - 1) do
        IO.binwrite(dest_io, File.read!(chunk_path(upload_id, i)))
      end
    end)

    cleanup(dir)

    if File.stat!(dest).size > @max_bytes do
      File.rm(dest)
      {:error, "Video must be smaller than #{div(@max_bytes, 1_000_000)}MB."}
    else
      title = title_from_filename(filename, ext)

      %Movie{}
      |> Movie.changeset(%{path: dest, title: title, status: "pending"})
      |> Repo.insert()
      |> case do
        {:ok, movie} ->
          start_ingestion(dest, title)
          {:ok, movie}

        {:error, _changeset} ->
          File.rm(dest)
          {:error, "Couldn't save this upload — please try again."}
      end
    end
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
    Task.Supervisor.start_child(PhoenixHologram.TaskSupervisor, fn ->
      case FaceDetection.ingest_video(path, title: title) do
        {:ok, _movie} -> :ok
        {:error, reason} -> Logger.error("Video ingest failed for #{path}: #{inspect(reason)}")
      end

      # Runs outside any Hologram command/action (this is a plain Task), so
      # `put_broadcast/4` (which needs a `%Hologram.Server{}`) isn't
      # available here — `Hologram.Realtime.broadcast_action/2` is the
      # public API for exactly this case, matching how
      # `PhoenixHologram.Analytics.record_visit/1` pushes
      # `:page_visits_changed` from outside a handler. DashboardPage and
      # UploadPage both subscribe to `:movies_changed` so their movie
      # lists/status badges update live instead of needing a manual
      # reload once curation finishes (or fails).
      Hologram.Realtime.broadcast_action(:movies_changed, :movie_ingested)
    end)
  end

  defp chunk_dir(upload_id), do: Path.join(chunks_root(), upload_id)

  defp chunk_path(upload_id, chunk_index) do
    Path.join(
      chunk_dir(upload_id),
      "chunk_" <> String.pad_leading(Integer.to_string(chunk_index), 6, "0")
    )
  end

  defp destination_path(filename, ext) do
    safe_name =
      filename
      |> Path.basename(ext)
      |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")

    unique = "#{System.system_time(:second)}-#{System.unique_integer([:positive])}"
    Path.expand(Path.join(uploads_dir(), "#{unique}-#{safe_name}#{ext}"))
  end

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

  defp uploads_dir, do: Path.join(:code.priv_dir(:phoenix_hologram), "face_detection/uploads")
  defp chunks_root, do: Path.join(uploads_dir(), "tmp")
end
