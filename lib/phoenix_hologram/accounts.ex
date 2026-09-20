defmodule PhoenixHologram.Accounts do
  @moduledoc """
  User registration, authentication, and lookup for the account system
  (login/register/dashboard) and for gating superuser-only demo content
  (the admin movie, analytics, and promo-request pages).
  """

  alias PhoenixHologram.Accounts.User
  alias PhoenixHologram.Repo

  @doc "Registers a new (non-superuser) account from user-submitted attrs."
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Creates or promotes an account with explicit attrs (e.g. `is_superuser: true`) — for seeding only, never exposed to a public form."
  def seed_user(attrs) do
    %User{}
    |> User.seed_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Verifies email/password, returning `{:ok, user}` or `{:error, :invalid_credentials}`. Runs a dummy hash on a missing email to keep timing consistent."
  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)

    cond do
      user && Pbkdf2.verify_pass(password, user.hashed_password) ->
        {:ok, user}

      true ->
        Pbkdf2.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  def get_user_by_email(email), do: Repo.get_by(User, email: email)

  def get_user(id), do: Repo.get(User, id)

  def superuser?(%User{is_superuser: true}), do: true
  def superuser?(_user), do: false
end
