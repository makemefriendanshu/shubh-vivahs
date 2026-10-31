defmodule ShubhVivahs.Repo.Migrations.AddAudioLanguagesToMediaItems do
  use Ecto.Migration

  # Comma-separated ISO 639-2 codes, e.g. "eng,hin": the first is the
  # language of the item's main file, each other one has its own copy next
  # to it (see Library.audio_versions/1). nil for single-language items.
  def change do
    alter table(:media_items) do
      add :audio_languages, :string
    end
  end
end
