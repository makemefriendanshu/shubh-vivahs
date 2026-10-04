defmodule ShubhVivahsWeb.Hologram.Pages.PremierePage do
  use Hologram.Page

  alias Hologram.UI.Link
  alias ShubhVivahs.FaceDetection
  alias ShubhVivahsWeb.Hologram.Pages.AdminMoviePage
  alias ShubhVivahsWeb.Hologram.Pages.PlayerPage

  route "/premiere"

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout

  def init(_params, component, server) do
    server = put_subscription(server, :movies_changed)

    component =
      component
      |> put_state(:logged_in?, !!server.user_id)
      |> put_filtered_movies(list_movies(server), :all)

    {component, server}
  end

  # Dispatched via Hologram.Realtime.broadcast_action/2 from this page's own
  # :set_movie_visibility command, or from DashboardPage/UploadPage/
  # AdminMoviesPage's equivalent commands - keeps the Public/Private badge
  # correct here too when toggled from another open tab/page.
  def action(:movies_updated, _params, component) do
    put_command(component, :refresh_movies)
  end

  # Toggling straight from the Public/Private badge - no confirm step,
  # since it is easily reversible (click it again). Matches
  # DashboardPage/UploadPage/AdminMoviesPage's :toggle_movie_visibility
  # action. Only rendered for logged-in users (see template) - anonymous
  # visitors only ever see public movies, so there is nothing to toggle.
  def action(:toggle_movie_visibility, params, component) do
    put_command(component, :set_movie_visibility,
      movie_id: params.movie_id,
      currently_public: params.currently_public
    )
  end

  # All/Public/Private filter above the grid - purely narrows the
  # already-fetched @all_movies list, no server round trip needed. Only
  # rendered for logged-in users (see template) - anonymous visitors only
  # ever have public movies to begin with.
  def action(:set_visibility_filter, params, component) do
    put_filtered_movies(component, component.state.all_movies, params.filter)
  end

  def action(:movies_refreshed, params, component) do
    put_filtered_movies(component, params.movies, component.state.visibility_filter)
  end

  def command(:refresh_movies, _params, server) do
    put_action(server, :movies_refreshed, movies: list_movies(server))
  end

  def command(:set_movie_visibility, params, server) do
    # Defense in depth: the toggle button only renders for logged-in users
    # (see template), but an anonymous session dispatching this action
    # directly must not be able to flip visibility.
    if server.user_id do
      FaceDetection.set_movie_visibility(params.movie_id, !params.currently_public)
      Hologram.Realtime.broadcast_action(:movies_changed, :movies_updated)
    end

    put_action(server, :movies_refreshed, movies: list_movies(server))
  end

  defp put_filtered_movies(component, all_movies, filter) do
    put_state(component,
      all_movies: all_movies,
      visibility_filter: filter,
      movies: filter_movies(all_movies, filter),
      empty_message: empty_message(all_movies, filter)
    )
  end

  defp filter_movies(movies, :public), do: Enum.filter(movies, & &1.public)
  defp filter_movies(movies, :private), do: Enum.filter(movies, &(!&1.public))
  defp filter_movies(movies, :all), do: movies

  defp empty_message([], _filter),
    do: "No films yet. Once a video is ingested it will show up here."

  defp empty_message(_all_movies, :public), do: "No public films."
  defp empty_message(_all_movies, :private), do: "No private films."

  defp empty_message(_all_movies, :all),
    do: "No films yet. Once a video is ingested it will show up here."

  defp list_movies(server) do
    if server.user_id do
      FaceDetection.list_movies_ordered()
    else
      FaceDetection.list_public_movies_ordered()
    end
    |> Enum.map(&build_card/1)
  end

  defp build_card(movie) do
    %{
      id: movie.id,
      title: movie.title || movie.path,
      status: movie.status,
      public: movie.public,
      visibility_label: visibility_label(movie.public),
      visibility_class: visibility_class(movie.public),
      visibility_icon: visibility_icon(movie.public),
      description: movie.description,
      event_line: format_event_line(movie),
      thumbnail_url: "/premiere/videos/#{movie.id}/thumbnail",
      highlight?: highlight_card?(movie)
    }
  end

  defp visibility_label(true), do: "Public"
  defp visibility_label(false), do: "Private"

  defp visibility_class(true), do: "badge badge-success badge-sm gap-1"
  defp visibility_class(false), do: "badge badge-ghost badge-sm gap-1"

  defp visibility_icon(true), do: "hero-eye w-3 h-3"
  defp visibility_icon(false), do: "hero-eye-slash w-3 h-3"

  defp highlight_card?(movie) do
    title = movie.title || ""
    String.contains?(String.downcase(title), "happy birthday")
  end

  defp format_event_line(movie) do
    case [format_event_date(movie.event_date), movie.location] |> Enum.reject(&is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, " | ")
    end
  end

  defp format_event_date(nil), do: nil
  defp format_event_date(date), do: date |> Calendar.strftime("%d %b %Y") |> String.upcase()

  def template do
    ~HOLO"""
    <div class="min-h-screen">
      <div class="p-6">
        <div class="max-w-3xl mx-auto">
          <div class="flex items-center justify-center gap-3 mb-1">
            <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70" fill="none" stroke="currentColor" stroke-width="1.2">
              <path d="M12 2c-6 6-6 20 0 36" />
              <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
            </svg>
            <h2 class="font-display text-xl sm:text-2xl text-center">
              Past Wedding Celebrations &amp; Milestones
            </h2>
            <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
              <path d="M12 2c-6 6-6 20 0 36" />
              <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
            </svg>
          </div>
          <div class="gold-divider w-24 mx-auto mb-6"></div>

          {%if @logged_in?}
            <div class="flex justify-center gap-2 mb-6">
              <button
                type="button"
                $click={:set_visibility_filter, filter: :all}
                class={
                  if @visibility_filter == :all do
                    "btn btn-sm btn-primary"
                  else
                    "btn btn-sm btn-ghost"
                  end
                }
              >
                All
              </button>
              <button
                type="button"
                $click={:set_visibility_filter, filter: :public}
                class={
                  if @visibility_filter == :public do
                    "btn btn-sm btn-primary"
                  else
                    "btn btn-sm btn-ghost"
                  end
                }
              >
                Public
              </button>
              <button
                type="button"
                $click={:set_visibility_filter, filter: :private}
                class={
                  if @visibility_filter == :private do
                    "btn btn-sm btn-primary"
                  else
                    "btn btn-sm btn-ghost"
                  end
                }
              >
                Private
              </button>
            </div>
          {/if}

          {%if @movies == []}
            <div class="card card-stock shadow-xl">
              <div class="card-body">
                <p class="text-base-content/70">{@empty_message}</p>
              </div>
            </div>
          {%else}
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {%for movie <- @movies}
                <div class={
                  if movie.highlight? do
                    "card sm:col-span-2 border-2 border-primary bg-secondary text-secondary-content shadow-xl hover:shadow-2xl transition overflow-hidden"
                  else
                    "card card-stock shadow-xl hover:shadow-2xl transition overflow-hidden"
                  end
                }>
                  <Link to={PlayerPage, id: movie.id}>
                    <figure class="aspect-video bg-base-300">
                      <img src={movie.thumbnail_url} alt={movie.title} class="w-full h-full object-cover" />
                    </figure>
                  </Link>
                  <div class="card-body items-center text-center">
                    <h2 class="card-title font-display">
                      <Link to={PlayerPage, id: movie.id} class="hover:underline">{movie.title}</Link>
                    </h2>
                    {%if movie.description}
                      <p class={
                        if movie.highlight? do
                          "text-sm text-secondary-content/80"
                        else
                          "text-sm text-base-content/70"
                        end
                      }>{movie.description}</p>
                    {/if}
                    {%if movie.event_line}
                      <p class={
                        if movie.highlight? do
                          "text-xs tracking-wide text-secondary-content/70"
                        else
                          "text-xs tracking-wide text-base-content/50"
                        end
                      }>{movie.event_line}</p>
                    {/if}
                    {%if @logged_in?}
                      <button
                        type="button"
                        $click={:toggle_movie_visibility, movie_id: movie.id, currently_public: movie.public}
                        class={movie.visibility_class}
                        title="Click to toggle whether this shows on public pages"
                      >
                        <span class={movie.visibility_icon}></span>
                        {movie.visibility_label}
                      </button>
                    {/if}
                    <div class="flex flex-wrap justify-center gap-2 mt-2">
                      <Link to={PlayerPage, id: movie.id} class="btn btn-sm btn-primary">
                        View Video ▶
                      </Link>
                      <Link to={AdminMoviePage, id: movie.id} class="btn btn-sm btn-secondary">
                        Admin View ⚙
                      </Link>
                    </div>
                  </div>
                </div>
              {/for}
            </div>
          {/if}
        </div>
      </div>
    </div>
    """
  end
end
