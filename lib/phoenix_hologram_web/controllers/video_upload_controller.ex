defmodule PhoenixHologramWeb.VideoUploadController do
  @moduledoc """
  Real chunked video upload, backing UploadPage's upload form. Unlike
  `AccountAvatarController` (one plain multipart POST), a video can be
  far bigger than any single request should carry through a reverse
  proxy — Cloudflare caps request bodies at 100MB on its free/pro tiers
  regardless of what this app's own `Plug.Parsers` config allows — so
  UploadPage's browser-side JS slices the file into
  `PhoenixHologram.VideoUpload.chunk_size/0`-sized pieces and POSTs them
  here one at a time (`create_chunk/2`), then calls `finalize/2` once
  they've all landed. Both actions return JSON, not a redirect: they're
  called from `fetch()`, not a native form submission, so the page never
  navigates mid-upload and can show live progress instead.

  Sits on the `:browser_no_csrf` pipeline like `AccountAvatarController`
  and validates the same Hologram-issued CSRF token manually, for the
  same reason: the form driving this was never able to populate
  `Plug.CSRFProtection`'s own session key, since it's rendered by a
  Hologram page rather than this router.
  """

  use PhoenixHologramWeb, :controller

  alias Hologram.Runtime.CSRFProtection
  alias PhoenixHologram.VideoUpload

  def create_chunk(conn, params) do
    with :ok <- verify_csrf_token(conn, params),
         %Plug.Upload{} = upload <- Map.get(params, "chunk", :missing),
         {chunk_index, total_chunks} <- parse_chunk_params(params),
         :ok <- VideoUpload.store_chunk(params["upload_id"], chunk_index, total_chunks, upload) do
      json(conn, %{status: "ok"})
    else
      {:error, message} when is_binary(message) ->
        conn |> put_status(422) |> json(%{status: "error", message: message})

      _missing_or_invalid ->
        conn |> put_status(422) |> json(%{status: "error", message: "Invalid chunk upload."})
    end
  end

  def finalize(conn, params) do
    with :ok <- verify_csrf_token(conn, params),
         {:ok, total_chunks} <- parse_int(params["total_chunks"]),
         {:ok, movie} <-
           VideoUpload.finalize(params["upload_id"], params["filename"] || "", total_chunks) do
      json(conn, %{status: "ok", movie_id: movie.id, title: movie.title})
    else
      {:error, message} when is_binary(message) ->
        conn |> put_status(422) |> json(%{status: "error", message: message})

      _missing_or_invalid ->
        conn
        |> put_status(422)
        |> json(%{
          status: "error",
          message: "Invalid upload — please reload the page and try again."
        })
    end
  end

  defp parse_chunk_params(params) do
    with {:ok, chunk_index} <- parse_int(params["chunk_index"]),
         {:ok, total_chunks} <- parse_int(params["total_chunks"]) do
      {chunk_index, total_chunks}
    end
  end

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _invalid -> :error
    end
  end

  defp parse_int(_other), do: :error

  defp verify_csrf_token(conn, params) do
    client_token = params["_csrf_token"]
    session_token = get_session(conn, CSRFProtection.session_key())

    if client_token && session_token && CSRFProtection.validate_token(session_token, client_token) do
      :ok
    else
      {:error, "Your session expired — please reload the page and try again."}
    end
  end
end
