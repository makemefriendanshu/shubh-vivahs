defmodule ShubhVivahsWeb.Hologram.Pages.LibraryPlayerPage do
  @moduledoc """
  Plays one media library item (see `ShubhVivahs.Library`): a `<video>`
  with English subtitles when the import found any, or an `<audio>`
  player for songs. Episodes link to the previous/next episode of their
  series. Signed-in users only, same as LibraryPage.
  """

  use Hologram.Page

  alias Hologram.UI.Link
  alias ShubhVivahs.Library
  alias ShubhVivahs.Library.MediaItem
  alias ShubhVivahsWeb.Hologram.Middleware.RequireAuthenticatedUser
  alias ShubhVivahsWeb.Hologram.Pages.LibraryPage

  route "/library/:id"
  param :id, :integer

  middleware RequireAuthenticatedUser

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout

  def init(params, component, server) do
    item =
      case Library.get_item(params.id) do
        %MediaItem{status: "ready"} = item -> build_item(item)
        _missing_or_unfinished -> nil
      end

    {put_state(component, :item, item), server}
  end

  defp build_item(item) do
    {previous, next} = Library.neighbours(item)

    %{
      id: item.id,
      title: item.title,
      heading: heading(item),
      audio?: item.kind == "song",
      media_url: "/library/media/#{item.id}/file",
      subtitles_url: if(item.has_subtitles, do: "/library/media/#{item.id}/subtitles.vtt"),
      poster_url:
        if(File.regular?(Library.thumbnail_path(item)),
          do: "/library/media/#{item.id}/thumbnail.jpg"
        ),
      previous: neighbour(previous),
      next: neighbour(next)
    }
  end

  defp heading(%MediaItem{kind: "series", season: s, episode: e} = item)
       when is_integer(s) and is_integer(e),
       do: "#{item.collection} · Season #{s}, Episode #{e}"

  defp heading(%MediaItem{collection: collection}), do: collection

  defp neighbour(nil), do: nil

  defp neighbour(item),
    do: %{id: item.id, label: "S#{item.season}E#{item.episode} · #{item.title}"}

  # Previous/next use a plain <a>, not <Link>: Hologram 0.10's client-side
  # navigation between two instances of the *same* page module never
  # remounts - the page bundle <script> keeps its src, so the vdom patch
  # doesn't re-run it and `hologram:pageScriptLoaded` never fires. A full
  # page load sidesteps that.
  def template do
    ~HOLO"""
    <div class="min-h-screen p-4 sm:p-6">
      <div class="max-w-5xl mx-auto">
        <Link to={LibraryPage} class="link link-hover text-sm">&larr; Back to Library</Link>

        {%if @item == nil}
          <div class="card card-stock shadow-xl mt-4">
            <div class="card-body">
              <p class="text-base-content/70">This item could not be found.</p>
            </div>
          </div>
        {%else}
          {%if @item.heading}
            <p class="text-xs uppercase tracking-widest text-primary mt-4">{@item.heading}</p>
          {/if}
          <h1 class="font-display text-2xl mt-1 mb-4">{@item.title}</h1>

          {%if @item.audio?}
            <div class="card card-stock shadow-xl">
              <div class="card-body items-center gap-4">
                {%if @item.poster_url}
                  <img src={@item.poster_url} alt="" class="w-48 h-48 rounded-box object-cover shadow-lg" />
                {%else}
                  <div class="w-48 h-48 rounded-box bg-base-300 flex items-center justify-center">
                    <span class="hero-musical-note w-16 h-16 opacity-30"></span>
                  </div>
                {/if}
                <audio id="library-audio" controls preload="metadata" src={@item.media_url} class="w-full max-w-xl"></audio>
              </div>
            </div>
          {%else}
            <video
              id="library-video"
              controls
              preload="metadata"
              playsinline
              poster={@item.poster_url}
              src={@item.media_url}
              class="w-full rounded-box shadow-xl bg-black"
            >
              {%if @item.subtitles_url}
                <track kind="subtitles" src={@item.subtitles_url} srclang="en" label="English" />
              {/if}
            </video>
          {/if}

          {%if @item.previous || @item.next}
            <div id="library-episode-nav" class="flex flex-col sm:flex-row justify-between gap-2 mt-4">
              {%if @item.previous}
                <a href={"/library/#{@item.previous.id}"} id="library-previous" class="btn btn-sm btn-ghost justify-start max-w-full">
                  <span class="hero-chevron-left w-4 h-4 shrink-0"></span>
                  <span class="truncate">{@item.previous.label}</span>
                </a>
              {%else}
                <span></span>
              {/if}
              {%if @item.next}
                <a href={"/library/#{@item.next.id}"} id="library-next" class="btn btn-sm btn-primary justify-end max-w-full">
                  <span class="truncate">Next: {@item.next.label}</span>
                  <span class="hero-chevron-right w-4 h-4 shrink-0"></span>
                </a>
              {/if}
            </div>
          {/if}
        {/if}
      </div>
    </div>
    """
  end
end
