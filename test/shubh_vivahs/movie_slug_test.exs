defmodule ShubhVivahs.MovieSlugTest do
  use ShubhVivahs.DataCase, async: true

  alias ShubhVivahs.Accounts
  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.MovieSlug
  alias ShubhVivahs.Repo

  test "slugify/1 makes lower-case ASCII words joined by dashes" do
    assert MovieSlug.slugify("Game of Thrones S01E01 · Winter Is Coming") ==
             "game-of-thrones-s01e01-winter-is-coming"

    assert MovieSlug.slugify("Mother's Mercy!") == "mothers-mercy"
    assert MovieSlug.slugify("Café Déjà Vu") == "cafe-deja-vu"
    assert MovieSlug.slugify("···") == "video"
  end

  test "ensure/1 assigns a unique slug once and keeps it" do
    a = Repo.insert!(%Movie{path: "/x/a.mp4", title: "Reception"})
    b = Repo.insert!(%Movie{path: "/x/b.mp4", title: "Reception"})

    assert MovieSlug.ensure(a).slug == "reception"
    assert MovieSlug.ensure(b).slug == "reception-2"
    assert Repo.get!(Movie, a.id).slug == "reception"
    assert MovieSlug.ensure(Repo.get!(Movie, a.id)).slug == "reception"
  end

  test "path/1 uses the uploader's name, or shubhvivahs when there is none" do
    {:ok, user} =
      Accounts.seed_user(%{
        name: "Anshuman Das",
        email: "slug-test@example.com",
        password: "correcthorsebatterystaple"
      })

    mine = Repo.insert!(%Movie{path: "/x/m.mp4", title: "Sangeet Night", user_id: user.id})
    library = Repo.insert!(%Movie{path: "/x/l.mp4", title: "Winter Is Coming"})

    assert MovieSlug.path(mine) == "/gallery/anshuman-das/sangeet-night"
    assert MovieSlug.path(library) == "/gallery/shubhvivahs/winter-is-coming"
  end
end
