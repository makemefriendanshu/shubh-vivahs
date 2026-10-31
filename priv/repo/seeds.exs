# Populates the `movies` table from local video folders, for exercising
# /premiere before the real ingestion pipeline (README roadmap item 4) lands.
#
#     mix run priv/repo/seeds.exs

alias ShubhVivahs.FaceDetection.Movie
alias ShubhVivahs.Repo

seed_dirs = [
  Path.expand("../../Anshuman  &  Mausam  Wedding", __DIR__),
  Path.expand("../../Birthday", __DIR__)
]

video_extensions = ~w(.mp4 .mov .webm .mkv .m4v)

seed_dirs
|> Enum.flat_map(fn dir ->
  case File.ls(dir) do
    {:ok, filenames} -> Enum.map(filenames, &Path.join(dir, &1))
    {:error, _reason} -> []
  end
end)
|> Enum.filter(fn path -> String.downcase(Path.extname(path)) in video_extensions end)
|> Enum.each(fn path ->
  title = path |> Path.basename() |> Path.rootname()

  unless Repo.get_by(Movie, path: path) do
    %Movie{}
    |> Movie.changeset(%{path: path, title: title})
    |> Repo.insert!()
  end
end)
