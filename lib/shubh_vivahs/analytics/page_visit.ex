defmodule ShubhVivahs.Analytics.PageVisit do
  use Ecto.Schema
  import Ecto.Changeset

  schema "page_visits" do
    field :path, :string
    field :ip, :string
    field :referrer, :string
    field :method, :string
    field :status, :integer
    field :duration_ms, :integer
    timestamps(updated_at: false)
  end

  def changeset(page_visit, attrs) do
    page_visit
    |> cast(attrs, [:path, :ip, :referrer, :method, :status, :duration_ms])
    |> validate_required([:path, :ip, :method])
  end
end
