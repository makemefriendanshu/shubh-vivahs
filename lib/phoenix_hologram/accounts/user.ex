defmodule PhoenixHologram.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :password, :string, virtual: true
    field :hashed_password, :string
    field :is_superuser, :boolean, default: false

    timestamps()
  end

  @doc "Changeset for self-service registration — never accepts `is_superuser` from user input."
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :password])
    |> validate_required([:name, :email, :password])
    |> validate_length(:name, max: 120)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> validate_length(:password, min: 8, max: 72)
    |> unsafe_validate_unique(:email, PhoenixHologram.Repo)
    |> unique_constraint(:email)
    |> put_hashed_password()
  end

  @doc "Changeset for seeding accounts (e.g. the initial superuser) — accepts `is_superuser` explicitly."
  def seed_changeset(user, attrs) do
    user
    |> registration_changeset(attrs)
    |> cast(attrs, [:is_superuser])
  end

  defp put_hashed_password(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        changeset
        |> put_change(:hashed_password, Pbkdf2.hash_pwd_salt(password))
        |> delete_change(:password)
    end
  end
end
