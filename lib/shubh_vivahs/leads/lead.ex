defmodule ShubhVivahs.Leads.Lead do
  use Ecto.Schema
  import Ecto.Changeset

  schema "leads" do
    field :name, :string
    field :wedding_date, :date
    field :email, :string
    timestamps(updated_at: false)
  end

  def changeset(lead, attrs) do
    lead
    |> cast(attrs, [:name, :wedding_date, :email])
    |> validate_required([:name, :email])
    |> validate_length(:name, max: 120)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
  end
end
