defmodule ShubhVivahs.Photos do
  @moduledoc """
  Photo albums in the wedding gallery: `/gallery/<uploader>/photos/<slug>`.

  Each photo is stored three ways under `storage_dir/0`, by album id:
  the untouched original (downloadable), a web-sized copy for the viewer
  (`@web_max_px`, upright), and a grid thumbnail (`@thumb_max_px`). Albums
  are added with `mix photos.import` (see `ShubhVivahs.Photos.Importer`)
  and, like uploaded films, start private: signed-out visitors only see
  albums made public.

  `mix photos.detect_faces` (`ShubhVivahs.Photos.FaceRecognition`) finds
  the people in an album, for the viewer's "Who's in focus?" votes.
  """

  import Ecto.Query

  alias ShubhVivahs.MovieSlug
  alias ShubhVivahs.Photos.{Album, Detection, Face, Photo, Vote}
  alias ShubhVivahs.Repo

  @web_max_px 1440
  @thumb_max_px 360

  # Photos per batch on the album page (its first render, then each
  # infinite-scroll fetch). 48 fills whole rows at 2, 3, 4 and 6 columns.
  @per_page 48

  def per_page, do: @per_page
  def web_max_px, do: @web_max_px
  def thumb_max_px, do: @thumb_max_px

  @doc "Folder every album's files live under (one subfolder per album id)."
  # Tests point this at a temp folder (config/test.exs) so they never
  # write into a real album's folder.
  def storage_dir,
    do:
      Application.get_env(:shubh_vivahs, :photos_dir) ||
        Path.join(:code.priv_dir(:shubh_vivahs), "photos")

  def album_dir(%Album{id: id}), do: Path.join(storage_dir(), Integer.to_string(id))

  def original_path(%Photo{original_path: path}), do: Path.join(storage_dir(), path)

  def web_path(%Photo{album_id: album_id, id: id}),
    do: Path.join([storage_dir(), "#{album_id}", "web", "#{id}.jpg"])

  def thumb_path(%Photo{album_id: album_id, id: id}),
    do: Path.join([storage_dir(), "#{album_id}", "thumbs", "#{id}.jpg"])

  def thumb_url(%Photo{id: id}), do: "/photos/#{id}/thumb.jpg"
  def web_url(%Photo{id: id}), do: "/photos/#{id}/web.jpg"
  def original_url(%Photo{id: id}), do: "/photos/#{id}/original.jpg"

  @doc "`/gallery/<uploader>/photos/<slug>`."
  def album_path(%Album{} = album),
    do: "/gallery/#{MovieSlug.uploader_slug_for(album.user_id)}/photos/#{album.slug}"

  @doc "Whether a viewer (signed in or not) may see `album` — public, or signed in."
  def visible?(nil, _user_id), do: false
  def visible?(%Album{public: true}, _user_id), do: true
  def visible?(%Album{}, user_id), do: not is_nil(user_id)

  @doc "Albums a viewer may see, in display order (`:all` for every album)."
  def list_albums(user_id) do
    query = from a in Album, order_by: [asc_nulls_last: a.position, asc: a.id]
    query = if user_id, do: query, else: from(a in query, where: a.public == true)
    Repo.all(query)
  end

  def get_album_by_slug(slug), do: Repo.get_by(Album, slug: slug)
  def get_album(id), do: Repo.get(Album, id)
  def get_photo(id), do: Repo.get(Photo, id)

  @doc """
  How many photos an album has — or, given a person (a recognised face id
  in that album), how many of its photos they are in. The same optional
  `person_id` narrows `photo_page/4` and `photo_at/3`.
  """
  def photo_count(%Album{} = album, person_id \\ nil),
    do: Repo.one(from p in photos_query(album, person_id), select: count())

  @doc "One page of an album's photos (1-based `page`), in album order."
  def photo_page(%Album{} = album, page, per_page, person_id \\ nil) do
    Repo.all(
      from p in photos_query(album, person_id),
        order_by: [asc: p.position, asc: p.id],
        offset: ^((page - 1) * per_page),
        limit: ^per_page
    )
  end

  @doc "The photo at a 0-based index within the album's order, or nil."
  def photo_at(album, index, person_id \\ nil)

  def photo_at(%Album{} = album, index, person_id) when index >= 0 do
    Repo.one(
      from p in photos_query(album, person_id),
        order_by: [asc: p.position, asc: p.id],
        offset: ^index,
        limit: 1
    )
  end

  def photo_at(_album, _index, _person_id), do: nil

  @doc "The album's cover photo: its chosen one, else its first photo."
  def cover_photo(%Album{cover_photo_id: id} = album) when is_integer(id),
    do: Repo.get(Photo, id) || photo_at(album, 0)

  def cover_photo(album), do: photo_at(album, 0)

  defp photos_query(%Album{id: id}, nil), do: from(p in Photo, where: p.album_id == ^id)

  # A person can be in a photo more than once only by mistake (two faces
  # grouped together); `exists` keeps such a photo to one row.
  defp photos_query(%Album{id: id}, person_id) do
    from p in Photo,
      as: :photo,
      where:
        p.album_id == ^id and
          exists(
            from d in Detection,
              where: d.photo_id == parent_as(:photo).id and d.face_id == ^person_id
          )
  end

  @doc "A recognised person in `album` as `%{id:, label:, face_url:}`, or nil."
  def album_person(%Album{id: album_id}, face_id) do
    case Repo.get_by(Face, id: face_id, album_id: album_id) do
      nil -> nil
      face -> %{id: face.id, label: face.label, face_url: face_url(face)}
    end
  end

  @doc "Whether face recognition has found anyone in `album` yet."
  def recognised?(%Album{id: id}), do: Repo.exists?(from f in Face, where: f.album_id == ^id)

  @doc "Where a recognised person's cropped portrait is kept."
  def face_path(%Face{id: id, album_id: album_id}),
    do: Path.join([storage_dir(), Integer.to_string(album_id), "faces", "#{id}.jpg"])

  def face_url(%{id: id}), do: "/photos/faces/#{id}/portrait.jpg"

  def get_face(id), do: Repo.get(Face, id)

  @doc """
  "Who's in focus?" for one photo: the people recognised in it, each as
  `%{face_id:, label:, face_url:, votes:, voted?:}` (`voted?` for
  `session_id`), left to right as they stand in the photo.
  """
  def focus(photo_id, session_id) do
    faces =
      Repo.all(
        from d in Detection,
          join: f in assoc(d, :face),
          where: d.photo_id == ^photo_id,
          order_by: [asc: d.bbox_x],
          select: %{face_id: f.id, label: f.label}
      )
      |> Enum.uniq_by(& &1.face_id)

    votes =
      Repo.all(
        from v in Vote,
          where: v.photo_id == ^photo_id,
          group_by: v.face_id,
          select: {v.face_id, count(v.id)}
      )
      |> Map.new()

    mine =
      Repo.all(
        from v in Vote,
          where: v.photo_id == ^photo_id and v.session_id == ^session_id,
          select: v.face_id
      )
      |> MapSet.new()

    Enum.map(faces, fn face ->
      Map.merge(face, %{
        face_url: face_url(%{id: face.face_id}),
        votes: Map.get(votes, face.face_id, 0),
        voted?: MapSet.member?(mine, face.face_id)
      })
    end)
  end

  @doc "Adds `session_id`'s focus vote for a person in a photo, or takes it back."
  def toggle_vote(photo_id, face_id, session_id) do
    query =
      from v in Vote,
        where: v.photo_id == ^photo_id and v.face_id == ^face_id and v.session_id == ^session_id

    if Repo.exists?(query) do
      Repo.delete_all(query)
    else
      # Only people actually recognised in that photo can be voted for.
      in_photo? =
        Repo.exists?(
          from d in Detection, where: d.photo_id == ^photo_id and d.face_id == ^face_id
        )

      if in_photo? do
        %Vote{}
        |> Vote.changeset(%{photo_id: photo_id, face_id: face_id, session_id: session_id})
        |> Repo.insert(on_conflict: :nothing)
      end
    end

    :ok
  end

  @doc """
  An album's recognised people for the admin page, each
  `%{id:, label:, subtitle:, face_url:, photos:, votes:}` (`photos` = how
  many photos they are in), most photos first.
  """
  def people(%Album{id: album_id}) do
    photo_counts =
      Repo.all(
        from d in Detection,
          join: f in assoc(d, :face),
          where: f.album_id == ^album_id,
          group_by: d.face_id,
          select: {d.face_id, count(d.photo_id, :distinct)}
      )
      |> Map.new()

    vote_counts =
      Repo.all(
        from v in Vote,
          join: f in assoc(v, :face),
          where: f.album_id == ^album_id,
          group_by: v.face_id,
          select: {v.face_id, count(v.id)}
      )
      |> Map.new()

    Repo.all(from f in Face, where: f.album_id == ^album_id, order_by: [asc: f.id])
    |> Enum.map(fn face ->
      %{
        id: face.id,
        label: face.label,
        subtitle: face.subtitle,
        face_url: face_url(face),
        photos: Map.get(photo_counts, face.id, 0),
        votes: Map.get(vote_counts, face.id, 0)
      }
    end)
    |> Enum.sort_by(&{-&1.photos, &1.id})
  end

  @doc """
  Updates an album's details from the admin page. A new title gets a new
  slug (and so a new URL), like a renamed film.
  """
  def update_album(%Album{} = album, attrs) do
    attrs =
      case attrs do
        %{title: title} when is_binary(title) and title != album.title ->
          Map.put(attrs, :slug, unique_slug(title, album.id))

        _ ->
          attrs
      end

    album |> Album.changeset(attrs) |> Repo.update()
  end

  @doc "Names a recognised person (blank clears it)."
  def label_face(face_id, label, subtitle) do
    case get_face(face_id) do
      nil -> {:error, :not_found}
      face -> face |> Face.label_changeset(%{label: label, subtitle: subtitle}) |> Repo.update()
    end
  end

  @doc "A slug for `title`, unique among albums other than `album_id`."
  def unique_slug(title, album_id \\ nil) do
    base = MovieSlug.slugify(title)

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(fn candidate ->
      not Repo.exists?(from a in Album, where: a.slug == ^candidate and a.id != ^(album_id || 0))
    end)
  end
end
