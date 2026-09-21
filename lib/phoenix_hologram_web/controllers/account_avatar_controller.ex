defmodule PhoenixHologramWeb.AccountAvatarController do
  @moduledoc """
  Real profile-photo upload/serving, backing AccountSettingsPage's photo
  field. `create/2` is a plain multipart POST (Hologram's command/action
  protocol can't carry binary file data — see `AccountSettingsPage`'s
  moduledoc), so it sits on its own router pipeline without
  `:protect_from_forgery`: that plug validates against its own session
  key, which the Hologram-rendered form was never able to populate (no
  `protect_from_forgery` runs while rendering a Hologram page). Instead
  this manually validates the token Hologram itself already generates
  and session-stores for every page load
  (`Hologram.Runtime.CSRFProtection`), submitted here as a hidden field.
  A failure is reported back via the `"avatar_error"` session key
  rather than a query param — see AccountSettingsPage's moduledoc for
  why a query param wouldn't be read by the page it redirects to.
  """

  use PhoenixHologramWeb, :controller

  require Logger

  alias PhoenixHologram.Accounts
  alias PhoenixHologram.AvatarUpload
  alias Hologram.Runtime.CSRFProtection

  def show(conn, %{"user_id" => user_id}) do
    case AvatarUpload.find_path(user_id) do
      nil ->
        send_resp(conn, 404, "Not found")

      path ->
        conn
        |> put_resp_content_type(content_type(path))
        |> put_resp_header("cache-control", "private, max-age=60")
        |> send_file(200, path)
    end
  end

  def create(conn, params) do
    user = conn.assigns.current_user

    with :ok <- verify_csrf_token(conn, params),
         %Plug.Upload{} = upload <- Map.get(params, "avatar", :missing),
         :ok <- AvatarUpload.store(user.id, upload),
         {:ok, _updated_user} <- Accounts.update_profile(user, %{avatar_url: avatar_url(user.id)}) do
      redirect(conn, to: "/account-settings")
    else
      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_session("avatar_error", "Photo saved, but couldn't be attached to your profile — please try again.")
        |> redirect(to: "/account-settings")

      {:error, message} when is_binary(message) ->
        conn |> put_session("avatar_error", message) |> redirect(to: "/account-settings")

      _missing_or_invalid ->
        conn
        |> put_session("avatar_error", "Please choose an image file.")
        |> redirect(to: "/account-settings")
    end
  rescue
    error in [File.Error] ->
      Logger.error("Avatar upload failed: #{Exception.message(error)}")

      conn
      |> put_session("avatar_error", "Couldn't save your photo — please try again.")
      |> redirect(to: "/account-settings")
  end

  defp verify_csrf_token(conn, params) do
    client_token = params["_csrf_token"]
    session_token = get_session(conn, CSRFProtection.session_key())

    if client_token && session_token && CSRFProtection.validate_token(session_token, client_token) do
      :ok
    else
      {:error, "Your session expired — please reload the page and try again."}
    end
  end

  defp avatar_url(user_id), do: "/account/avatar/#{user_id}?v=#{System.system_time(:second)}"

  defp content_type(path) do
    case Path.extname(path) do
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _jpg -> "image/jpeg"
    end
  end
end
