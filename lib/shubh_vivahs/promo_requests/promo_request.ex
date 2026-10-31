defmodule ShubhVivahs.PromoRequests.PromoRequest do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending approved rejected)

  schema "promo_requests" do
    field :description, :string
    field :amount, :integer
    field :code, :string
    field :status, :string, default: "pending"
    timestamps()
  end

  def changeset(promo_request, attrs) do
    promo_request
    |> cast(attrs, [:description, :amount, :code, :status])
    |> validate_required([:description, :amount, :code])
    |> validate_length(:description, max: 500)
    |> validate_inclusion(:status, @statuses)
  end
end
