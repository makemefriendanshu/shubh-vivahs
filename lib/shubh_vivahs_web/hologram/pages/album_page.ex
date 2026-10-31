defmodule ShubhVivahsWeb.Hologram.Pages.AlbumPage do
  @moduledoc """
  A photo album in the wedding gallery: `/gallery/<uploader>/photos/<slug>`
  (see `ShubhVivahs.Photos`). A thumbnail grid that keeps loading as you
  scroll, and a full-screen viewer (arrow keys, swipe, Esc) with the
  original available to download.

  Only the first batch of photos is rendered from state (`@photos`); the
  rest are fetched by the page script from `/photos/albums/<id>/page.json`
  and added to `#album-grid-more` outside Hologram. Hologram re-walks a
  page's whole state on every action, so a 1,000-photo album in state
  would make every click and arrow key slow. The viewer keeps its own
  48-photo window (`@window`) around the photo on screen.
  """

  use Hologram.Page
  use Hologram.JS

  alias Hologram.UI.Link
  alias ShubhVivahs.Photos
  alias ShubhVivahsWeb.Hologram.Pages.PremierePage

  route "/gallery/:uploader/photos/:album"
  param :uploader, :string
  param :album, :string

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout

  @per_page Photos.per_page()

  def init(params, component, server) do
    album = Photos.get_album_by_slug(params.album)
    album = if Photos.visible?(album, server.user_id), do: album

    component =
      if album do
        person = person_filter(album, server.query)
        person_id = person && person.id
        total = Photos.photo_count(album, person_id)

        component
        |> put_state(:album, %{
          id: album.id,
          title: album.title,
          description: album.description,
          event_line: event_line(album),
          total: total,
          person: person && Map.put(person, :all_path, Photos.album_path(album)),
          admin_path:
            server.user_id &&
              "/admin/#{ShubhVivahs.MovieSlug.uploader_slug_for(album.user_id)}/photos/#{album.slug}"
        })
        |> put_state(:page_count, max(1, div(total + @per_page - 1, @per_page)))
        |> put_state(:more_src, more_src(album, person_id))
        |> put_state(:photos, page_cards(album, 1, person_id))
        |> then(&put_state(&1, :window, &1.state.photos))
        |> put_state(:recognised?, Photos.recognised?(album))
      else
        component
        |> put_state(:album, nil)
        |> put_state(:page_count, 1)
        |> put_state(:more_src, nil)
        |> put_state(:photos, [])
        |> put_state(:window, [])
        |> put_state(:recognised?, false)
      end

    {put_state(component, viewer: nil, focus: nil), server}
  end

  def action(:page_loaded, params, component) do
    component = put_state(component, :window, params.photos)
    viewer = component.state.viewer

    case Map.get(params, :open) do
      nil when viewer != nil ->
        # Opened ahead of its batch (:open_added_photo): fill in the rest.
        case Enum.find(params.photos, &(&1.index == viewer.index)) do
          nil ->
            component

          card ->
            put_state(component, :viewer, %{
              viewer
              | name: card.name,
                neighbour_urls: neighbour_urls(params.photos, viewer.index)
            })
        end

      nil ->
        component

      index ->
        show_photo(component, index)
    end
  end

  # A photo the page script added below the first batch: its id is known,
  # so the viewer opens at once while its batch loads as the new window.
  def action(:open_added_photo, %{index: index, id: id}, component) do
    component
    |> put_focus_command(id)
    |> put_state(:viewer, %{
      id: id,
      index: index,
      name: "",
      web_url: "/photos/#{id}/web.jpg",
      original_url: "/photos/#{id}/original.jpg",
      prev?: index > 0,
      next?: index < component.state.album.total - 1,
      neighbour_urls: []
    })
    |> put_command(:load_page,
      album_id: component.state.album.id,
      person_id: person_id(component),
      page: div(index, @per_page) + 1
    )
  end

  # Photos in the viewer window open straight away (their URLs follow from
  # the id). Anything else (a photo the page script added further down, or
  # stepping past the window edge) loads that batch as the new window
  # first, so the next steps are instant again.
  def action(:open_photo, %{index: index}, component), do: show_photo(component, index)

  def action(:close_viewer, _params, component), do: put_state(component, :viewer, nil)

  def action(:viewer_key, %{key: key}, component) do
    viewer = component.state.viewer

    cond do
      viewer == nil -> component
      key == "Escape" -> put_state(component, :viewer, nil)
      key == "ArrowRight" and viewer.next? -> show_photo(component, viewer.index + 1)
      key == "ArrowLeft" and viewer.prev? -> show_photo(component, viewer.index - 1)
      true -> component
    end
  end

  # "Who's in focus?" for the photo on screen. Replies for a photo the
  # viewer has already stepped past are dropped.
  def action(:focus_loaded, %{photo_id: photo_id, faces: faces}, component) do
    viewer = component.state.viewer

    if viewer && viewer.id == photo_id,
      do: put_state(component, :focus, faces),
      else: component
  end

  # Flips the chip straight away; the server reply then brings everyone
  # else's votes up to date too.
  def action(:vote_focus, %{face_id: face_id}, component) do
    photo_id = component.state.viewer.id

    focus =
      Enum.map(component.state.focus || [], fn face ->
        cond do
          face.face_id != face_id -> face
          face.voted? -> %{face | voted?: false, votes: face.votes - 1}
          true -> %{face | voted?: true, votes: face.votes + 1}
        end
      end)

    component
    |> put_state(:focus, focus)
    |> put_command(:toggle_vote, photo_id: photo_id, face_id: face_id)
  end

  def command(:load_focus, %{photo_id: photo_id}, server) do
    put_action(server, :focus_loaded,
      photo_id: photo_id,
      faces: Photos.focus(photo_id, server.session_id)
    )
  end

  def command(:toggle_vote, %{photo_id: photo_id, face_id: face_id}, server) do
    :ok = Photos.toggle_vote(photo_id, face_id, server.session_id)

    put_action(server, :focus_loaded,
      photo_id: photo_id,
      faces: Photos.focus(photo_id, server.session_id)
    )
  end

  def command(:load_page, params, server) do
    album = Photos.get_album(params.album_id)

    put_action(server, :page_loaded,
      page: params.page,
      photos: page_cards(album, params.page, params.person_id),
      open: Map.get(params, :open)
    )
  end

  defp show_photo(component, index) do
    case Enum.find(component.state.window, &(&1.index == index)) do
      nil ->
        put_command(component, :load_page,
          album_id: component.state.album.id,
          person_id: person_id(component),
          page: div(index, @per_page) + 1,
          open: index
        )

      card ->
        component
        |> put_focus_command(card.id)
        |> put_state(:viewer, %{
          id: card.id,
          index: index,
          name: card.name,
          web_url: "/photos/#{card.id}/web.jpg",
          original_url: "/photos/#{card.id}/original.jpg",
          prev?: index > 0,
          next?: index < component.state.album.total - 1,
          neighbour_urls: neighbour_urls(component.state.window, index)
        })
    end
  end

  defp put_focus_command(component, photo_id) do
    if component.state.recognised?,
      do: component |> put_state(:focus, nil) |> put_command(:load_focus, photo_id: photo_id),
      else: component
  end

  # Web copies of the photos either side, loaded hidden so stepping through
  # the viewer does not wait on the network.
  defp neighbour_urls(photos, index) do
    photos
    |> Enum.filter(&(&1.index == index - 1 or &1.index == index + 1))
    |> Enum.map(&"/photos/#{&1.id}/web.jpg")
  end

  defp person_id(component) do
    case component.state.album.person do
      nil -> nil
      person -> person.id
    end
  end

  # `?person=<slug>` (e.g. `rahul-sharma`, see `Photos.person_slugs/1`)
  # narrows the album to the photos one recognised person is in (linked
  # from the admin page's People list). Older links used the face id.
  defp person_filter(album, query) do
    case query["person"] do
      value when is_binary(value) and value != "" ->
        case Integer.parse(value) do
          {id, ""} -> Photos.album_person(album, id)
          _ -> Photos.album_person_by_slug(album, value)
        end

      _ ->
        nil
    end
  end

  defp more_src(album, nil), do: "/photos/albums/#{album.id}/page.json?page="

  defp more_src(album, person_id),
    do: "/photos/albums/#{album.id}/page.json?person=#{person_id}&page="

  defp page_cards(album, page, person_id) do
    album
    |> Photos.photo_page(page, @per_page, person_id)
    |> Enum.with_index((page - 1) * @per_page)
    |> Enum.map(fn {photo, index} ->
      %{id: photo.id, index: index, name: photo.original_name, thumb_url: Photos.thumb_url(photo)}
    end)
  end

  defp event_line(album) do
    date = album.event_date && Calendar.strftime(album.event_date, "%d %b %Y")

    case Enum.reject([date, album.location], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  # The viewer listens for arrow keys, Esc and horizontal swipes. No quote
  # marks or backslashes in the script comments: Hologram mangles both.
  def template do
    ~HOLO"""
    <div class="min-h-screen p-4 sm:p-6">
      <div class="max-w-6xl mx-auto">
        <Link to={PremierePage} class="link link-hover text-sm">&larr; Back to Gallery</Link>

        {%if @album == nil}
          <div class="card card-stock shadow-xl mt-4">
            <div class="card-body p-4 sm:p-8">
              <p class="text-base-content/70">This album could not be found.</p>
            </div>
          </div>
        {%else}
          <div class="mt-4 mb-4">
            <div class="flex flex-wrap items-center gap-2">
              <h1 class="font-display text-2xl sm:text-3xl min-w-0 break-words">{@album.title}</h1>
              {%if @album.admin_path}
                <a href={@album.admin_path} id="album-manage" class="btn btn-xs btn-ghost ml-auto">Manage &#9881;</a>
              {/if}
            </div>
            {%if @album.person}
              <div id="album-person" class="flex items-center gap-3 mt-3 p-2 pr-3 rounded-box bg-base-200/70 max-w-xl">
                <img src={@album.person.face_url} alt="" class="w-14 h-14 rounded-full object-cover shrink-0 ring-2 ring-primary/40" />
                <div class="min-w-0 flex-1">
                  <p class="text-base font-semibold leading-tight">Photos of {@album.person.label || "this guest"}</p>
                  <p class="text-xs text-base-content/60">
                    {@album.total} photos ·
                    <a href={@album.person.all_path} id="album-person-clear" class="link link-primary">show all</a>
                  </p>
                </div>
              </div>
            {%else}
              <p class="text-sm text-base-content/60 mt-1">
                {@album.total} photos{%if @album.event_line} · {@album.event_line}{/if}
              </p>
            {/if}
            {%if @album.description}
              <p class="text-sm text-base-content/70 mt-2 max-w-3xl">{@album.description}</p>
            {/if}
          </div>

          <div id="album-grid" class="grid grid-cols-2 min-[480px]:grid-cols-3 sm:grid-cols-4 lg:grid-cols-6 gap-1.5 sm:gap-2 scroll-mt-4">
            {%for photo <- @photos}
              <button
                type="button"
                id={"photo-#{photo.id}"}
                $click={:open_photo, index: photo.index}
                class="group relative aspect-square overflow-hidden rounded-box bg-base-300 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              >
                <img src={photo.thumb_url} alt="" loading="lazy" class="w-full h-full object-cover group-hover:scale-105 transition duration-300" />
              </button>
            {/for}
          </div>

          <div
            id="album-grid-more"
            class="grid grid-cols-2 min-[480px]:grid-cols-3 sm:grid-cols-4 lg:grid-cols-6 gap-1.5 sm:gap-2 mt-1.5 sm:mt-2"
          ></div>

          {%if @page_count > 1}
            <div
              id="album-more"
              data-src={@more_src}
              data-pages={@page_count}
              class="flex justify-center py-6"
              aria-live="polite"
            >
              <span class="loading loading-dots loading-md text-primary/60"></span>
            </div>
          {/if}

          {%if @viewer}
            <div id="photo-viewer" class="fixed inset-0 z-50 bg-black flex flex-col" role="dialog" aria-modal="true" aria-label="Photo viewer">
              <div class="flex items-center gap-2 p-2 sm:p-3 text-white/90 text-sm">
                <span class="tabular-nums shrink-0">{@viewer.index + 1} / {@album.total}</span>
                <span class="truncate text-white/50 text-xs flex-1 min-w-0">{@viewer.name}</span>
                <a href={@viewer.original_url} download={@viewer.name} id="photo-download" class="btn btn-xs btn-ghost text-white gap-1">
                  <span class="hero-arrow-down-tray w-4 h-4"></span><span class="hidden sm:inline">Original</span>
                </a>
                <button type="button" id="photo-close" $click="close_viewer" class="btn btn-xs btn-ghost text-white" aria-label="Close">
                  <span class="hero-x-mark w-5 h-5"></span>
                </button>
              </div>
              <div class="relative flex-1 min-h-0 flex items-center justify-center px-2 pb-2">
                <img src={@viewer.web_url} alt={@viewer.name} class="max-h-full max-w-full object-contain select-none" />
                {%if @viewer.prev?}
                  <button type="button" id="photo-prev" $click={:viewer_key, key: "ArrowLeft"} class="absolute left-1 sm:left-3 top-1/2 -translate-y-1/2 btn btn-circle btn-sm sm:btn-md bg-black/50 border-0 text-white hover:bg-black/80" aria-label="Previous photo">
                    <span class="hero-chevron-left w-5 h-5"></span>
                  </button>
                {/if}
                {%if @viewer.next?}
                  <button type="button" id="photo-next" $click={:viewer_key, key: "ArrowRight"} class="absolute right-1 sm:right-3 top-1/2 -translate-y-1/2 btn btn-circle btn-sm sm:btn-md bg-black/50 border-0 text-white hover:bg-black/80" aria-label="Next photo">
                    <span class="hero-chevron-right w-5 h-5"></span>
                  </button>
                {/if}
              </div>
              {%if @recognised?}
                <div id="photo-focus" class="shrink-0 px-2 pb-3 sm:pb-4">
                  <p class="text-center text-white/70 text-xs sm:text-sm mb-2">
                    Who&rsquo;s in focus? <span class="text-white/40">Tap the people this photo is really about.</span>
                  </p>
                  <div class="flex gap-2 sm:gap-3 overflow-x-auto justify-start sm:justify-center pb-1 min-h-14">
                    {%if @focus == nil}
                      <span class="loading loading-dots loading-sm text-white/50 mx-auto"></span>
                    {%else}
                      {%if @focus == []}
                        <span class="text-white/40 text-xs mx-auto self-center">No faces recognised in this photo.</span>
                      {/if}
                      {%for face <- @focus}
                        <button
                          type="button"
                          id={"focus-face-#{face.face_id}"}
                          $click={:vote_focus, face_id: face.face_id}
                          aria-pressed={if(face.voted?, do: "true", else: "false")}
                          class={"shrink-0 flex flex-col items-center gap-1 rounded-box p-1 w-16 sm:w-20 transition hover:bg-white/10 #{if(face.voted?, do: "bg-white/15", else: "")}"}
                        >
                          <span class={"relative block w-11 h-11 sm:w-14 sm:h-14 rounded-full overflow-hidden ring-2 transition #{if(face.voted?, do: "ring-primary scale-105", else: "ring-white/20")}"}>
                            <img src={face.face_url} alt="" class="w-full h-full object-cover" />
                          </span>
                          <span class="text-[0.6rem] sm:text-xs text-white/80 leading-tight truncate max-w-full">{face.label || "Guest"}</span>
                          <span class={"text-[0.6rem] sm:text-xs tabular-nums leading-none #{if(face.voted?, do: "text-primary", else: "text-white/50")}"}>&hearts; {face.votes}</span>
                        </button>
                      {/for}
                    {/if}
                  </div>
                </div>
              {/if}
              {%for url <- @viewer.neighbour_urls}
                <img src={url} alt="" class="hidden" />
              {/for}
            </div>
          {/if}

          <script>
            {%raw}
            // Infinite scroll. When the end of the grid comes within about two
            // screens, fetch the next batch and add it to album-grid-more; a
            // tap on one of those opens the viewer through a Hologram action.
            // The grid-more box remembers which album and filter it holds
            // (data-loaded-src), so moving to another album starts afresh.
            // Checked on scroll and on a slow timer, which also covers pages
            // shorter than the screen. No quote marks or backslashes here.
            (function () {
              if (window.__albumMoreAttached) { return; }
              window.__albumMoreAttached = true;
              var busy = false;
              var CARD = "group relative aspect-square overflow-hidden rounded-box bg-base-300 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary";
              var IMG = "w-full h-full object-cover group-hover:scale-105 transition duration-300";
              function check() {
                var sentinel = document.getElementById("album-more");
                var more = document.getElementById("album-grid-more");
                if (!sentinel || !more || busy) { return; }
                // Hands off until Hologram has mounted the page: it snapshots
                // the DOM when it starts, and nodes added before its first
                // render leave its event handling out of step.
                var holo = window.Hologram;
                if (!holo || !holo.pageScriptLoaded || !holo.mountedPage) { return; }
                var src = sentinel.getAttribute("data-src");
                if (more.getAttribute("data-loaded-src") !== src) {
                  more.innerHTML = "";
                  more.setAttribute("data-loaded-src", src);
                  more.setAttribute("data-next", "2");
                }
                var next = parseInt(more.getAttribute("data-next"), 10) || 2;
                var pages = parseInt(sentinel.getAttribute("data-pages"), 10) || 1;
                if (next > pages) { sentinel.style.display = "none"; return; }
                sentinel.style.display = "";
                if (sentinel.getBoundingClientRect().top > window.innerHeight * 3) { return; }
                busy = true;
                fetch(src + next, { credentials: "same-origin" })
                  .then(function (response) { return response.json(); })
                  .then(function (data) {
                    if (more.getAttribute("data-loaded-src") === src && more.isConnected) {
                      data.photos.forEach(function (photo) {
                        var button = document.createElement("button");
                        button.type = "button";
                        button.id = "photo-" + photo.id;
                        button.className = CARD;
                        button.setAttribute("data-index", photo.index);
                        button.setAttribute("data-id", photo.id);
                        var img = document.createElement("img");
                        img.src = photo.thumb_url;
                        img.alt = "";
                        img.loading = "lazy";
                        img.className = IMG;
                        button.appendChild(img);
                        more.appendChild(button);
                      });
                      more.setAttribute("data-next", String(next + 1));
                    }
                    busy = false;
                    requestAnimationFrame(check);
                  })
                  .catch(function () { busy = false; });
              }
              document.addEventListener("click", function (e) {
                var button = e.target.closest && e.target.closest("#album-grid-more [data-index]");
                if (!button || !window.Hologram) { return; }
                Hologram.dispatchAction("open_added_photo", "page", {
                  index: parseInt(button.getAttribute("data-index"), 10),
                  id: parseInt(button.getAttribute("data-id"), 10)
                });
              });
              window.addEventListener("scroll", function () { requestAnimationFrame(check); }, { passive: true });
              window.addEventListener("resize", check);
              setInterval(check, 1000);
              check();
            })();
            (function () {
              if (window.__photoViewerKeys) { return; }
              window.__photoViewerKeys = true;
              function send(key) {
                if (!document.getElementById("photo-viewer") || !window.Hologram) { return; }
                Hologram.dispatchAction("viewer_key", "page", { key: key });
              }
              document.addEventListener("keydown", function (e) {
                if (!document.getElementById("photo-viewer")) { return; }
                if (e.key === "ArrowLeft" || e.key === "ArrowRight" || e.key === "Escape") {
                  e.preventDefault();
                  send(e.key);
                }
              });
              var startX = null;
              document.addEventListener("touchstart", function (e) {
                if (document.getElementById("photo-viewer") && e.touches.length === 1) { startX = e.touches[0].clientX; }
              }, { passive: true });
              document.addEventListener("touchend", function (e) {
                if (startX === null) { return; }
                var dx = e.changedTouches[0].clientX - startX;
                startX = null;
                if (Math.abs(dx) > 50) { send(dx < 0 ? "ArrowRight" : "ArrowLeft"); }
              });
            })();
            {/raw}
          </script>
        {/if}
      </div>
    </div>
    """
  end
end
