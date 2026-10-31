defmodule ShubhVivahsWeb.PlayerUrlRedirectTest do
  use ShubhVivahs.DataCase, async: true

  alias ShubhVivahs.FaceDetection.Movie
  alias ShubhVivahs.Repo
  alias ShubhVivahsWeb.Hologram.Middleware.PlayerUrlRedirect

  defp run(path, mode, opts \\ []) do
    server = %Hologram.Server{path: path, user_id: opts[:user_id], raw_query: opts[:query]}
    result = PlayerUrlRedirect.call(server, Keyword.merge([mode: mode], opts[:mw] || []))
    {result.status, result.response_headers["location"]}
  end

  setup do
    public =
      Repo.insert!(%Movie{path: "/x/p.mp4", title: "Reception", slug: "reception", public: true})

    private =
      Repo.insert!(%Movie{path: "/x/q.mp4", title: "Winter Is Coming", slug: "winter-is-coming"})

    %{public: public, private: private}
  end

  @gallery [mw: [section: :gallery]]
  @library [mw: [section: :library]]

  test "old stream and library-file URLs go to the new endpoints, keeping the query" do
    assert run("/premiere/videos/93", :premiere_legacy, query: "quality=source") ==
             {302, "/premiere/videos/93/stream?quality=source"}

    assert run("/library/media/12", :player, @library) == {302, "/library/media/12/file"}
  end

  test "the canonical URL passes through; a wrong uploader or section redirects to it" do
    assert run("/gallery/shubhvivahs/reception", :player, @gallery) == {nil, nil}

    assert run("/gallery/someone/reception", :player, @gallery) ==
             {302, "/gallery/shubhvivahs/reception"}

    assert run("/library/shubhvivahs/reception", :player, @library) ==
             {302, "/gallery/shubhvivahs/reception"}
  end

  test "old /premiere links redirect to the readable URL", %{public: public, private: private} do
    assert run("/premiere/#{public.id}", :legacy) == {302, "/gallery/shubhvivahs/reception"}

    assert run("/premiere/#{private.id}", :legacy, user_id: 1) ==
             {302, "/gallery/shubhvivahs/winter-is-coming"}

    assert run("/premiere/someone/reception", :premiere_legacy) ==
             {302, "/gallery/shubhvivahs/reception"}

    assert run("/premiere", :gallery_index) == {302, "/gallery"}
  end

  test "private movies never reveal their URL to signed-out visitors", %{private: private} do
    assert run("/premiere/#{private.id}", :legacy) == {302, "/gallery"}
    assert run("/premiere/someone/winter-is-coming", :premiere_legacy) == {302, "/gallery"}
    assert run("/gallery/someone/winter-is-coming", :player, @gallery) == {nil, nil}
  end

  test "admin scene browser: canonical passes, old and wrong URLs redirect", %{private: private} do
    assert run("/admin/shubhvivahs/winter-is-coming", :admin) == {nil, nil}

    assert run("/admin/someone/winter-is-coming", :admin) ==
             {302, "/admin/shubhvivahs/winter-is-coming"}

    assert run("/admin/movies/#{private.id}", :admin) ==
             {302, "/admin/shubhvivahs/winter-is-coming"}

    assert run("/admin/movies/999999", :admin) == {302, "/admin"}

    assert run("/admin/movies/shubhvivahs/winter-is-coming", :admin_legacy) ==
             {302, "/admin/shubhvivahs/winter-is-coming"}

    assert run("/admin/analytics/export.csv", :admin, query: "days=7") ==
             {302, "/admin/analytics.csv?days=7"}
  end
end
