defmodule ShubhVivahs.Photos.RecognitionRunner do
  @moduledoc """
  Runs an album's face recognition (`ShubhVivahs.Photos.FaceRecognition`)
  in the background when an admin clicks the button on AdminAlbumPage.

  Shares `ShubhVivahs.MovieJobRunner`'s rule: one heavy job at a time
  inside the web server, since that process is also what serves the site.
  A run already going for the album (here or in `mix photos.detect_faces`)
  is refused unless it has stalled.
  """

  require Logger

  alias ShubhVivahs.MovieJobRunner
  alias ShubhVivahs.Photos
  alias ShubhVivahs.Photos.{AlbumJobs, FaceRecognition}

  @spec start(integer) :: :ok | {:error, :not_found | :already_running | :busy}
  def start(album_id) do
    job = AlbumJobs.get(album_id, "recognition")

    cond do
      running?() or MovieJobRunner.running?() ->
        {:error, :busy}

      Photos.get_album(album_id) == nil ->
        {:error, :not_found}

      job && job.status == "running" && not AlbumJobs.stalled?(job) ->
        {:error, :already_running}

      true ->
        # Shows as running straight away, before the task gets going.
        AlbumJobs.start(album_id, "recognition")

        {:ok, _pid} =
          Task.Supervisor.start_child(ShubhVivahs.TaskSupervisor, fn -> run(album_id) end)

        :ok
    end
  end

  @doc "Whether the web server is recognising faces in an album right now."
  def running?, do: Process.whereis(__MODULE__) != nil

  defp run(album_id) do
    Process.register(self(), __MODULE__)

    try do
      with {:error, reason} <- FaceRecognition.run(Photos.get_album(album_id)) do
        Logger.error("Face recognition failed for album #{album_id}: #{inspect(reason)}")
      end
    rescue
      exception ->
        Logger.error(
          "Face recognition crashed for album #{album_id}: #{Exception.message(exception)}"
        )
    end
  end
end
