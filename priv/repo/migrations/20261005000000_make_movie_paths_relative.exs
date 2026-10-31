defmodule ShubhVivahs.Repo.Migrations.MakeMoviePathsRelative do
  use Ecto.Migration

  # Movie.path is now a MoviePath, which stores files under the uploads
  # folder relative to it. Strip whatever absolute prefix existing rows
  # were saved with (including ones from before the project folder was
  # renamed) up to and including "/face_detection/uploads/".
  # Paths outside the uploads folder are left absolute.
  @marker "/face_detection/uploads/"

  def up do
    execute("""
    UPDATE movies
    SET path = substr(path, instr(path, '#{@marker}') + #{String.length(@marker)})
    WHERE instr(path, '#{@marker}') > 0
    """)
  end

  def down do
    prefix =
      (Path.join(:code.priv_dir(:shubh_vivahs), "face_detection/uploads") <> "/")
      |> String.replace("'", "''")

    execute("UPDATE movies SET path = '#{prefix}' || path WHERE path NOT LIKE '/%'")
  end
end
