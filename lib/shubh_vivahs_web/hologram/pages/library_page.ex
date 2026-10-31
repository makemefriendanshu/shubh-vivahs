defmodule ShubhVivahsWeb.Hologram.Pages.LibraryPage do
  @moduledoc """
  The general media library — TV series, movies, and songs added with
  `mix library.import` (see `ShubhVivahs.Library`). Signed-in users only:
  unlike the wedding films, nothing here is ever public.
  """

  use Hologram.Page

  alias ShubhVivahs.Library
  alias ShubhVivahsWeb.Hologram.Middleware.RequireAuthenticatedUser

  route "/library"

  middleware RequireAuthenticatedUser

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout

  def init(_params, component, server) do
    episodes = Library.list_ready("series")
    movies = Library.list_ready("movie")
    songs = Library.list_ready("song")

    series = build_series(episodes)

    # Series counts shows (one per series), not episodes.
    tabs = [
      %{key: :series, label: "Series", icon: "hero-tv", count: length(series)},
      %{key: :movies, label: "Movies", icon: "hero-film", count: length(movies)},
      %{key: :songs, label: "Songs", icon: "hero-musical-note", count: length(songs)}
    ]

    initial_tab = Enum.find_value(tabs, :series, &(&1.count > 0 && &1.key))

    component =
      component
      |> put_state(:tab, initial_tab)
      |> put_state(:tabs, tabs)
      |> put_state(:series, series)
      |> put_state(:movie_groups, build_movie_groups(movies))
      |> put_state(:movies_summary, movies_summary(movies))
      |> put_state(:songs, Enum.map(songs, &build_card/1))

    {component, server}
  end

  def action(:set_tab, params, component) do
    put_state(component, :tab, params.tab)
  end

  # Episodes arrive ordered by series, season, episode (see
  # Library.list_ready/1), so consecutive runs are the groups.
  defp build_series(episodes) do
    episodes
    |> Enum.chunk_by(& &1.collection)
    |> Enum.map(fn [first | _] = series_episodes ->
      seasons =
        series_episodes
        |> Enum.chunk_by(& &1.season)
        |> Enum.map(fn [%{season: season} | _] = season_episodes ->
          %{
            label: if(season, do: "Season #{season}", else: "Episodes"),
            count_label: episode_count_label(length(season_episodes)),
            episodes: Enum.map(season_episodes, &build_card/1)
          }
        end)

      %{
        name: first.collection || "Untitled series",
        summary: series_summary(length(seasons), length(series_episodes)),
        seasons: seasons
      }
    end)
  end

  # Movies have no series/season, so the Movies tab groups them by the
  # release year in their title ("Name (2025)", as the importer writes it),
  # newest first; titles without one go in "Other" at the end.
  defp build_movie_groups(movies) do
    movies
    |> Enum.group_by(&movie_year/1)
    |> Enum.sort_by(fn {year, _} -> year || 0 end, :desc)
    |> Enum.map(fn {year, group} ->
      %{
        label: if(year, do: Integer.to_string(year), else: "Other"),
        count_label: if(length(group) == 1, do: "1 movie", else: "#{length(group)} movies"),
        movies: group |> Enum.sort_by(&String.downcase(&1.title)) |> Enum.map(&build_card/1)
      }
    end)
  end

  defp movies_summary([_one]), do: "1 movie"
  defp movies_summary(movies), do: "#{length(movies)} movies"

  defp movie_year(%{title: title}) do
    case Regex.run(~r/\((\d{4})\)\s*$/, title) do
      [_, year] -> String.to_integer(year)
      nil -> nil
    end
  end

  defp episode_count_label(1), do: "1 episode"
  defp episode_count_label(count), do: "#{count} episodes"

  defp series_summary(1, episodes), do: "1 season · #{episodes} episodes"
  defp series_summary(seasons, episodes), do: "#{seasons} seasons · #{episodes} episodes"

  # Videos play in PlayerPage via their backing movie (faces, comments,
  # likes); songs and anything not linked yet use LibraryPlayerPage. Plain
  # <a href> in the template since the target page module varies per card.
  defp player_url(%{movie_id: nil, id: id}), do: "/library/#{id}"

  defp player_url(%{movie_id: movie_id}),
    do:
      ShubhVivahs.MovieSlug.path(ShubhVivahs.Repo.get!(ShubhVivahs.FaceDetection.Movie, movie_id))

  defp build_card(item) do
    %{
      id: item.id,
      url: player_url(item),
      title: item.title,
      code: if(item.episode, do: "E#{String.pad_leading("#{item.episode}", 2, "0")}"),
      subtitle: item.collection,
      has_subtitles: item.has_subtitles,
      thumbnail_url:
        if(File.regular?(Library.thumbnail_path(item)),
          do: "/library/media/#{item.id}/thumbnail.jpg"
        )
    }
  end

  # Series tab is a two-level accordion: series (open by default) > season
  # (collapsed, so a long show's hundreds of thumbnails only load once a
  # season is opened); the Movies tab mirrors it: a "Movies" header (open)
  # over one collapsed group per year.
  # Native <details>/<summary>, so no state is needed. Headers stick to the
  # top while scrolling their contents: the series header is a fixed height
  # (h-[4.25rem] — room for a two-line name on phones — / sm:h-14) so the
  # season header can stick right below it, and the
  # cards drop overflow-hidden, which would otherwise disable sticky.
  def template do
    ~HOLO"""
    <div class="min-h-screen p-4 sm:p-6">
      <div class="max-w-5xl mx-auto">
        <div class="text-center mb-6">
          <h1 class="font-display text-2xl sm:text-3xl">Library</h1>
          <p class="text-sm text-base-content/60 mt-1">Series, movies &amp; songs — visible to signed-in members only</p>
          <div class="gold-divider w-24 mx-auto mt-3"></div>
        </div>

        <div id="library-tabs" class="grid grid-cols-3 gap-1 p-1 mb-6 w-full max-w-md mx-auto rounded-box bg-base-200/80 border border-primary/15" role="tablist">
          {%for tab <- @tabs}
            <button
              type="button"
              role="tab"
              id={"library-tab-#{tab.key}"}
              $click={:set_tab, tab: tab.key}
              class={
                if @tab == tab.key do
                  "flex flex-col sm:flex-row items-center justify-center gap-0 sm:gap-1.5 min-w-0 px-1 sm:px-3 py-1.5 sm:py-2 rounded-field text-xs sm:text-sm font-medium leading-tight bg-primary text-primary-content shadow transition"
                else
                  "flex flex-col sm:flex-row items-center justify-center gap-0 sm:gap-1.5 min-w-0 px-1 sm:px-3 py-1.5 sm:py-2 rounded-field text-xs sm:text-sm font-medium leading-tight text-base-content/70 hover:bg-base-100 hover:text-base-content transition"
                end
              }
            >
              <span class={"#{tab.icon} w-4 h-4 shrink-0 hidden sm:inline-block"}></span>
              <span class="whitespace-nowrap">{tab.label}</span>
              <span class="text-[0.65rem] sm:text-xs opacity-70 tabular-nums">{tab.count}</span>
            </button>
          {/for}
        </div>

        {%if @tab == :series}
          {%if @series == []}
            <div class="card card-stock shadow-xl">
              <div class="card-body text-center text-base-content/70">
                No series yet. Add a season folder with
                <code class="text-xs">mix library.import FOLDER --kind series</code>
              </div>
            </div>
          {%else}
            <div id="library-series" class="space-y-6">
              {%for series <- @series}
                <details open class="group/series card card-stock shadow-xl">
                  <summary class="sticky top-0 z-20 h-[4.25rem] sm:h-14 list-none [&::-webkit-details-marker]:hidden cursor-pointer select-none flex items-center gap-3 px-4 sm:px-6 bg-base-100 hover:bg-base-200 rounded-box group-open/series:rounded-b-none group-open/series:border-b group-open/series:border-primary/20 group-open/series:shadow-sm transition-colors">
                    <span class="hero-chevron-right w-5 h-5 shrink-0 text-primary transition-transform duration-200 group-open/series:rotate-90"></span>
                    <span class="flex-1 min-w-0 flex flex-col sm:flex-row sm:items-baseline sm:justify-between gap-0.5 sm:gap-3">
                      <h2 class="font-display text-base sm:text-xl leading-tight line-clamp-2 sm:line-clamp-1">{series.name}</h2>
                      <span class="text-xs text-base-content/60 whitespace-nowrap sm:shrink-0">{series.summary}</span>
                    </span>
                  </summary>
                  <div class="px-3 pb-4 sm:px-6 sm:pb-6 space-y-2">
                    {%for season <- series.seasons}
                      <details class="group/season rounded-box border border-primary/20 bg-base-100/40">
                        <summary class="sticky top-[4.25rem] sm:top-14 z-10 list-none [&::-webkit-details-marker]:hidden cursor-pointer select-none flex items-center gap-2 px-3 py-2.5 bg-base-100 hover:bg-base-200 rounded-box group-open/season:rounded-b-none group-open/season:shadow-sm transition-colors">
                          <span class="hero-chevron-right w-4 h-4 shrink-0 text-primary transition-transform duration-200 group-open/season:rotate-90"></span>
                          <span class="flex-1 min-w-0 flex flex-col sm:flex-row sm:items-baseline sm:justify-between gap-0.5 sm:gap-3">
                            <h3 class="font-display text-sm uppercase tracking-wide sm:tracking-widest text-primary whitespace-nowrap">{season.label}</h3>
                            <span class="text-xs text-base-content/50 whitespace-nowrap">{season.count_label}</span>
                          </span>
                        </summary>
                        <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3 p-3 pt-1">
                          {%for episode <- season.episodes}
                            <a href={episode.url} class="group block rounded-box overflow-hidden bg-base-200 hover:-translate-y-0.5 hover:shadow-lg transition">
                              <figure class="aspect-video bg-base-300 relative overflow-hidden">
                                {%if episode.thumbnail_url}
                                  <img src={episode.thumbnail_url} alt="" loading="lazy" class="w-full h-full object-cover group-hover:scale-105 transition duration-300" />
                                {%else}
                                  <div class="w-full h-full flex items-center justify-center"><span class="hero-tv w-8 h-8 opacity-30"></span></div>
                                {/if}
                                <span class="absolute top-1.5 left-1.5 badge badge-sm bg-black/70 border-0 text-white">{episode.code}</span>
                                <span class="absolute inset-0 flex items-center justify-center opacity-0 group-hover:opacity-100 transition bg-black/30">
                                  <span class="hero-play-circle w-10 h-10 text-white"></span>
                                </span>
                              </figure>
                              <p class="text-xs sm:text-sm p-2 leading-snug line-clamp-2">{episode.title}</p>
                            </a>
                          {/for}
                        </div>
                      </details>
                    {/for}
                  </div>
                </details>
              {/for}
            </div>
          {/if}
        {/if}

        {%if @tab == :movies}
          {%if @movie_groups == []}
            <div class="card card-stock shadow-xl">
              <div class="card-body text-center text-base-content/70">
                No movies yet. Add some with
                <code class="text-xs">mix library.import PATH --kind movie</code>
              </div>
            </div>
          {%else}
            <div id="library-movies" class="space-y-6">
              <details open class="group/allmovies card card-stock shadow-xl">
                <summary class="sticky top-0 z-20 h-[4.25rem] sm:h-14 gap-3 px-4 sm:px-6 rounded-box group-open/allmovies:rounded-b-none group-open/allmovies:border-b group-open/allmovies:border-primary/20 group-open/allmovies:shadow-sm list-none [&::-webkit-details-marker]:hidden cursor-pointer select-none flex items-center bg-base-100 hover:bg-base-200 transition-colors">
                  <span class="hero-chevron-right w-5 h-5 shrink-0 text-primary transition-transform duration-200 group-open/allmovies:rotate-90"></span>
                  <span class="flex-1 min-w-0 flex flex-col sm:flex-row sm:items-baseline sm:justify-between gap-0.5 sm:gap-3">
                    <h2 class="font-display text-base sm:text-xl leading-tight">Movies</h2>
                    <span class="text-xs text-base-content/60 whitespace-nowrap">{@movies_summary}</span>
                  </span>
                </summary>
                <div class="px-3 pb-4 pt-2 sm:px-6 sm:pb-6 space-y-2">
                  {%for group <- @movie_groups}
                    <details class="group/movies rounded-box border border-primary/20 bg-base-100/40">
                      <summary class="sticky top-[4.25rem] sm:top-14 z-10 gap-2 px-3 py-2.5 rounded-box group-open/movies:rounded-b-none group-open/movies:shadow-sm list-none [&::-webkit-details-marker]:hidden cursor-pointer select-none flex items-center bg-base-100 hover:bg-base-200 transition-colors">
                        <span class="hero-chevron-right w-4 h-4 shrink-0 text-primary transition-transform duration-200 group-open/movies:rotate-90"></span>
                        <span class="flex-1 min-w-0 flex flex-col sm:flex-row sm:items-baseline sm:justify-between gap-0.5 sm:gap-3">
                          <h3 class="font-display text-sm uppercase tracking-wide sm:tracking-widest text-primary whitespace-nowrap">{group.label}</h3>
                          <span class="text-xs text-base-content/50 whitespace-nowrap">{group.count_label}</span>
                        </span>
                      </summary>
                      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 p-3 pt-1">
                        {%for movie <- group.movies}
                          <a href={movie.url} class="group block rounded-box overflow-hidden bg-base-200 hover:shadow-lg hover:-translate-y-0.5 transition">
                            <figure class="aspect-video bg-base-300 relative overflow-hidden flex items-center justify-center">
                              {%if movie.thumbnail_url}
                                <img src={movie.thumbnail_url} alt="" loading="lazy" class="w-full h-full object-cover group-hover:scale-105 transition duration-300" />
                              {%else}
                                <span class="hero-film w-10 h-10 opacity-30"></span>
                              {/if}
                              <span class="absolute inset-0 flex items-center justify-center opacity-0 group-hover:opacity-100 transition bg-black/30">
                                <span class="hero-play-circle w-12 h-12 text-white"></span>
                              </span>
                            </figure>
                            <div class="p-3">
                              <h3 class="font-display text-base leading-snug">{movie.title}</h3>
                              {%if movie.has_subtitles}
                                <span class="badge badge-sm badge-ghost gap-1 mt-1"><span class="hero-language w-3 h-3"></span>Subtitles</span>
                              {/if}
                            </div>
                          </a>
                        {/for}
                      </div>
                    </details>
                  {/for}
                </div>
              </details>
            </div>
          {/if}
        {/if}

        {%if @tab == :songs}
          {%if @songs == []}
            <div class="card card-stock shadow-xl">
              <div class="card-body text-center text-base-content/70">
                No songs yet. Add a folder of music with
                <code class="text-xs">mix library.import FOLDER --kind song</code>
              </div>
            </div>
          {%else}
            <div class="card card-stock shadow-xl">
              <ul class="divide-y divide-base-content/10">
                {%for song <- @songs}
                  <li>
                    <a href={song.url} class="flex items-center gap-3 p-3 hover:bg-base-200 transition">
                      {%if song.thumbnail_url}
                        <img src={song.thumbnail_url} alt="" loading="lazy" class="w-10 h-10 rounded object-cover shrink-0" />
                      {%else}
                        <span class="w-10 h-10 rounded bg-base-300 flex items-center justify-center shrink-0"><span class="hero-musical-note w-5 h-5 opacity-50"></span></span>
                      {/if}
                      <span class="min-w-0 flex-1">
                        <span class="block truncate">{song.title}</span>
                        {%if song.subtitle}<span class="block text-xs text-base-content/60 truncate">{song.subtitle}</span>{/if}
                      </span>
                      <span class="hero-play w-4 h-4 opacity-50"></span>
                    </a>
                  </li>
                {/for}
              </ul>
            </div>
          {/if}
        {/if}
      </div>
    </div>
    """
  end
end
