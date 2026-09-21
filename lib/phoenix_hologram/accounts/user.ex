defmodule PhoenixHologram.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :password, :string, virtual: true
    field :hashed_password, :string
    field :is_superuser, :boolean, default: false
    # Optional — collected at registration and editable later on
    # AccountSettingsPage, but never required (existing accounts predate
    # these columns, and registration/login must keep working without them).
    field :phone, :string
    field :avatar_url, :string
    field :wedding_date, :date

    timestamps()
  end

  @profile_fields [:phone, :avatar_url, :wedding_date]

  @doc "Changeset for self-service registration — never accepts `is_superuser` from user input."
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :password] ++ @profile_fields)
    |> validate_required([:name, :email, :password])
    |> validate_length(:name, max: 120)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> validate_length(:password, min: 8, max: 72)
    |> validate_length(:phone, max: 30)
    |> validate_length(:avatar_url, max: 2048)
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

  @doc "Changeset for a signed-in user editing their own profile (name/email plus the optional fields above) on AccountSettingsPage."
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email] ++ @profile_fields)
    |> validate_required([:name, :email])
    |> validate_length(:name, max: 120)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> validate_length(:phone, max: 30)
    |> validate_length(:avatar_url, max: 2048)
    |> unsafe_validate_unique(:email, PhoenixHologram.Repo)
    |> unique_constraint(:email)
  end

  @doc "Changeset for a signed-in user changing their own password on AccountSettingsPage — caller is responsible for verifying the current password first (see `Accounts.update_password/3`)."
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    |> put_hashed_password()
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
