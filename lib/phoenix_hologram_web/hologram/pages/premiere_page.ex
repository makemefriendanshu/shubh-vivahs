defmodule PhoenixHologramWeb.Hologram.Pages.PremierePage do
  use Hologram.Page

  alias Hologram.UI.Link
  alias PhoenixHologram.FaceDetection
  alias PhoenixHologramWeb.Hologram.Pages.AdminMoviePage
  alias PhoenixHologramWeb.Hologram.Pages.PlayerPage

  route "/premiere"

  layout PhoenixHologramWeb.Hologram.Layouts.DefaultLayout

  def init(_params, component, server) do
    movies =
      if server.user_id do
        FaceDetection.list_movies_ordered()
      else
        FaceDetection.list_public_movies_ordered()
      end
      |> Enum.map(&build_card/1)

    put_state(component, :movies, movies)
  end

  defp build_card(movie) do
    %{
      id: movie.id,
      title: movie.title || movie.path,
      status: movie.status,
      public: movie.public,
      description: movie.description,
      event_line: format_event_line(movie),
      thumbnail_url: "/premiere/videos/#{movie.id}/thumbnail",
      highlight?: highlight_card?(movie)
    }
  end

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

          {%if @movies == []}
            <div class="card card-stock shadow-xl">
              <div class="card-body">
                <p class="text-base-content/70">
                  No films yet. Once a video is ingested it will show up here.
                </p>
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
                    {%if !movie.public}
                      <span class="badge badge-ghost gap-1">
                        <span class="hero-eye-slash w-3 h-3"></span>
                        Private
                      </span>
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
