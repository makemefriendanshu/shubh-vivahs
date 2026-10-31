defmodule ShubhVivahs.PhotosTest do
  use ShubhVivahs.DataCase

  alias ShubhVivahs.Photos
  alias ShubhVivahs.Photos.{Album, Detection, Face, Importer, Photo, Vote}

  setup do
    File.rm_rf!(Photos.storage_dir())

    source =
      Path.join(
        System.tmp_dir!(),
        "shubh_vivahs_photo_source_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(source, "sub"))
    on_exit(fn -> File.rm_rf!(source) end)
    %{source: source}
  end

  # A plain landscape JPEG, w x h.
  defp jpeg!(path, w, h) do
    img = Evision.Mat.full({h, w, 3}, 128, :u8) |> Evision.Mat.last_dim_as_channel()
    true = Evision.imwrite(path, img)
    path
  end

  test "import_dir/2 moves originals in, makes web copies and thumbnails, and skips repeats",
       %{source: source} do
    jpeg!(Path.join(source, "b.jpg"), 2000, 1000)
    jpeg!(Path.join(source, "sub/a.JPG"), 300, 200)
    File.write!(Path.join(source, "notes.txt"), "not a photo")

    assert {:ok, %Album{} = album, %{imported: 2, skipped: 0, failed: 0}} =
             Importer.import_dir(source, "Patna Reception")

    assert album.slug == "patna-reception"
    refute album.public
    assert Photos.photo_count(album) == 2

    [first, second] = Photos.photo_page(album, 1, 48)
    assert first.original_name == "b.jpg"
    assert second.original_name == "a.JPG"
    assert album.cover_photo_id == first.id
    assert {first.width, first.height} == {2000, 1000}

    refute File.exists?(Path.join(source, "b.jpg"))
    assert File.regular?(Photos.original_path(first))

    {web_h, web_w, _} = Photos.web_path(first) |> Evision.imread() |> Evision.Mat.shape()
    assert max(web_w, web_h) == Photos.web_max_px()
    {th_h, th_w, _} = Photos.thumb_path(first) |> Evision.imread() |> Evision.Mat.shape()
    assert max(th_w, th_h) == Photos.thumb_max_px()

    # Small photos are not scaled up.
    {h, w, _} = Photos.web_path(second) |> Evision.imread() |> Evision.Mat.shape()
    assert {w, h} == {300, 200}

    # Re-running adds new files to the same album, after the existing ones.
    jpeg!(Path.join(source, "c.jpg"), 100, 100)
    assert {:ok, again, %{imported: 1}} = Importer.import_dir(source, "Patna Reception")
    assert again.id == album.id
    assert Photos.photo_at(album, 2).original_name == "c.jpg"
  end

  test "visible?/2 and list_albums/1 hide private albums from signed-out visitors" do
    private = Repo.insert!(%Album{title: "Private", slug: "private", public: false})
    public = Repo.insert!(%Album{title: "Public", slug: "public", public: true})

    refute Photos.visible?(private, nil)
    assert Photos.visible?(private, 1)
    assert Photos.visible?(public, nil)
    refute Photos.visible?(nil, 1)

    assert Enum.map(Photos.list_albums(nil), & &1.id) == [public.id]

    assert Enum.map(Photos.list_albums(1), & &1.id) |> Enum.sort() ==
             Enum.sort([private.id, public.id])
  end

  test "unique_slug/2 avoids other albums' slugs" do
    album = Repo.insert!(%Album{title: "Birthday", slug: "birthday"})
    assert Photos.unique_slug("Birthday") == "birthday-2"
    assert Photos.unique_slug("Birthday", album.id) == "birthday"
  end

  test "update_album/2 gives a renamed album a new slug and keeps it otherwise" do
    album = Repo.insert!(%Album{title: "Birthday", slug: "birthday"})
    _other = Repo.insert!(%Album{title: "Mehendi", slug: "mehendi"})

    assert {:ok, same} = Photos.update_album(album, %{title: "Birthday", location: "Patna"})
    assert {same.slug, same.location} == {"birthday", "Patna"}

    assert {:ok, renamed} = Photos.update_album(same, %{title: "Mehendi"})
    assert renamed.slug == "mehendi-2"

    assert {:ok, %{public: true}} = Photos.update_album(renamed, %{public: true})
  end

  test "label_face/3 names and un-names a person" do
    album = Repo.insert!(%Album{title: "L", slug: "l"})
    face = Repo.insert!(%Face{album_id: album.id, embedding: [0.1]})

    assert {:ok, %{label: "Asha", subtitle: "Bride"}} =
             Photos.label_face(face.id, "Asha", "Bride")

    assert {:ok, %{label: nil}} = Photos.label_face(face.id, nil, nil)
    assert {:error, :not_found} = Photos.label_face(-1, "x", nil)
  end

  test "photo_page/3 and photo_at/2 follow position order" do
    album = Repo.insert!(%Album{title: "A", slug: "a"})

    for {name, pos} <- [{"x", 3}, {"y", 1}, {"z", 2}] do
      Repo.insert!(%Photo{
        album_id: album.id,
        original_name: name,
        original_path: name,
        source_path: "/s/#{name}",
        position: pos
      })
    end

    assert Enum.map(Photos.photo_page(album, 1, 2), & &1.original_name) == ["y", "z"]
    assert Enum.map(Photos.photo_page(album, 2, 2), & &1.original_name) == ["x"]
    assert Photos.photo_at(album, 2).original_name == "x"
    assert Photos.photo_at(album, 3) == nil
  end

  describe "focus votes" do
    setup do
      album = Repo.insert!(%Album{title: "F", slug: "f"})

      [p1, p2] =
        for n <- [1, 2] do
          Repo.insert!(%Photo{
            album_id: album.id,
            original_name: "#{n}.jpg",
            original_path: "#{n}.jpg",
            source_path: "/s/f/#{n}",
            position: n
          })
        end

      emb = List.duplicate(0.1, 4)
      bride = Repo.insert!(%Face{album_id: album.id, label: "Bride", embedding: emb})
      guest = Repo.insert!(%Face{album_id: album.id, embedding: emb})

      for {photo, face, x} <- [{p1, guest, 10.0}, {p1, bride, 500.0}, {p2, bride, 50.0}] do
        Repo.insert!(%Detection{photo_id: photo.id, face_id: face.id, bbox_x: x, confidence: 0.9})
      end

      %{album: album, p1: p1, p2: p2, bride: bride, guest: guest}
    end

    test "focus/2 lists the people in a photo left to right with votes", c do
      assert Photos.recognised?(c.album)

      assert [%{face_id: g, label: nil, votes: 0}, %{face_id: b, label: "Bride"}] =
               Photos.focus(c.p1.id, "s1")

      assert {g, b} == {c.guest.id, c.bride.id}
    end

    test "toggle_vote/3 adds and takes back a session's vote", c do
      :ok = Photos.toggle_vote(c.p1.id, c.bride.id, "s1")
      :ok = Photos.toggle_vote(c.p1.id, c.bride.id, "s2")
      bride = Enum.find(Photos.focus(c.p1.id, "s1"), &(&1.face_id == c.bride.id))
      assert %{votes: 2, voted?: true} = bride

      :ok = Photos.toggle_vote(c.p1.id, c.bride.id, "s1")
      bride = Enum.find(Photos.focus(c.p1.id, "s1"), &(&1.face_id == c.bride.id))
      assert %{votes: 1, voted?: false} = bride
    end

    test "toggle_vote/3 ignores people not in the photo", c do
      :ok = Photos.toggle_vote(c.p2.id, c.guest.id, "s1")
      assert Repo.aggregate(Vote, :count) == 0
    end

    test "photo_count/2, photo_page/4 and photo_at/3 narrow to one person's photos", c do
      assert Photos.photo_count(c.album) == 2
      assert Photos.photo_count(c.album, c.bride.id) == 2
      assert Photos.photo_count(c.album, c.guest.id) == 1
      assert [%{id: p1}] = Photos.photo_page(c.album, 1, 48, c.guest.id)
      assert p1 == c.p1.id
      assert Photos.photo_at(c.album, 1, c.bride.id).id == c.p2.id
      assert Photos.photo_at(c.album, 1, c.guest.id) == nil
    end

    test "album_person/2 only finds people in that album", c do
      assert %{id: id, label: "Bride"} = Photos.album_person(c.album, c.bride.id)
      assert id == c.bride.id
      other = Repo.insert!(%Album{title: "Other", slug: "other"})
      assert Photos.album_person(other, c.bride.id) == nil
    end

    test "person_slugs/1 names people in kebab case, numbering namesakes", c do
      emb = List.duplicate(0.1, 4)
      twin = Repo.insert!(%Face{album_id: c.album.id, label: "  bride ", embedding: emb})
      rahul = Repo.insert!(%Face{album_id: c.album.id, label: "Rahul Sharma", embedding: emb})

      assert Photos.person_slugs(c.album) == %{
               c.bride.id => "bride",
               c.guest.id => "guest-#{c.guest.id}",
               twin.id => "bride-2",
               rahul.id => "rahul-sharma"
             }
    end

    test "album_person_by_slug/2 finds a person by their slug", c do
      assert %{id: id} = Photos.album_person_by_slug(c.album, "bride")
      assert id == c.bride.id
      assert %{id: g} = Photos.album_person_by_slug(c.album, "guest-#{c.guest.id}")
      assert g == c.guest.id
      assert Photos.album_person_by_slug(c.album, "nobody") == nil
    end

    test "people/1 counts photos and votes per person, most photos first", c do
      :ok = Photos.toggle_vote(c.p1.id, c.guest.id, "s1")

      assert [
               %{id: b, slug: "bride", label: "Bride", photos: 2, votes: 0},
               %{id: g, label: nil, photos: 1, votes: 1}
             ] = Photos.people(c.album)

      assert {b, g} == {c.bride.id, c.guest.id}
    end
  end
end
