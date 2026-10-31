defmodule ShubhVivahs.Leads do
  @moduledoc """
  Captures "Start your story" signups from the home page.
  """

  alias ShubhVivahs.Leads.Lead
  alias ShubhVivahs.Repo

  def create_lead(attrs) do
    %Lead{}
    |> Lead.changeset(attrs)
    |> Repo.insert()
  end
end
