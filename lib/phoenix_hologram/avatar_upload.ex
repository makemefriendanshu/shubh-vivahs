defmodule PhoenixHologram.AvatarUpload do
  @moduledoc """
  Stores user-uploaded profile photos on disk (a priv dir, not
  priv/static — mirrors `PhoenixHologram.MovieThumbnail`/`FaceThumbnail`'s
  approach) and serves them back through
  `PhoenixHologramWeb.AccountAvatarController` rather than `Plug.Static`,
  so nothing needs touching in `PhoenixHologramWeb.static_paths/0`.
  """

  @allowed_extensions ~w(.jpg .jpeg .png .gif .webp)
  @max_bytes 5_000_000

  @doc "Saves `upload` as the avatar for `user_id`, replacing any previous one. Returns `:ok` or `{:error, message}`."
  @spec store(term, Plug.Upload.t()) :: :ok | {:error, String.t()}
  def store(user_id, %Plug.Upload{path: tmp_path, filename: filename}) do
    ext = filename |> Path.extname() |> String.downcase()

    cond do
      ext not in @allowed_extensions ->
        {:error, "Please upload a JPG, PNG, GIF, or WEBP image."}

      File.stat!(tmp_path).size > @max_bytes ->
        {:error, "Image must be smaller than 5MB."}

      true ->
        File.mkdir_p!(avatars_dir())
        clear_existing!(user_id)
        File.cp!(tmp_path, avatar_path(user_id, ext))
        :ok
    end
  end

  @doc "Path to this user's stored avatar file, or `nil` if none has been uploaded."
  @spec find_path(term) :: String.t() | nil
  def find_path(user_id) do
    @allowed_extensions
    |> Enum.map(&avatar_path(user_id, &1))
    |> Enum.find(&File.regular?/1)
  end

  defp clear_existing!(user_id) do
    case find_path(user_id) do
      nil -> :ok
      path -> File.rm!(path)
    end
  end

  defp avatar_path(user_id, ext), do: Path.join(avatars_dir(), "#{user_id}#{ext}")

  defp avatars_dir, do: Path.join(:code.priv_dir(:phoenix_hologram), "avatars")
end
