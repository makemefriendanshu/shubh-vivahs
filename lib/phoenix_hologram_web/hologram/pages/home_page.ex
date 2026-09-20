defmodule PhoenixHologramWeb.Hologram.Pages.HomePage do
  @moduledoc """
  Public landing page: sells the "turn your wedding videos into a digital
  keepsake" pitch, showcases the real films already in the Premiere Hall as
  a live example, and captures "Start your story" signups (see
  `PhoenixHologram.Leads`).
  """

  use Hologram.Page
  use Hologram.JS

  alias Hologram.UI.Link
  alias PhoenixHologram.FaceDetection
  alias PhoenixHologram.Leads
  alias PhoenixHologramWeb.Hologram.Pages.AdminMoviePage
  alias PhoenixHologramWeb.Hologram.Pages.PlayerPage
  alias PhoenixHologramWeb.Hologram.Pages.PremierePage
  alias PhoenixHologramWeb.Hologram.Pages.ScienceOfFocusPage

  route "/"

  layout PhoenixHologramWeb.Hologram.Layouts.DefaultLayout, banner: :home

  def init(_params, component, _server) do
    movies =
      FaceDetection.list_movies_ordered()
      |> Enum.map(&build_card/1)

    component
    |> put_state(:movies, movies)
    |> put_state(:lead_status, :idle)
    |> put_state(:lead_errors, [])
  end

  defp build_card(movie) do
    %{
      id: movie.id,
      title: movie.title || movie.path,
      status: movie.status,
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

  # Runs client-side, so the actual insert happens in the :persist_lead
  # command below — same client-action/server-command split used
  # throughout the Hologram pages (see AdminMoviePage) since DB access
  # isn't available client-side.
  def action(:submit_lead, params, component) do
    put_command(component, :persist_lead,
      name: blank_to_nil(params.event["name"]),
      wedding_date: blank_to_nil(params.event["wedding_date"]),
      email: blank_to_nil(params.event["email"])
    )
  end

  def action(:lead_saved, _params, component) do
    JS.exec("""
    const form = document.getElementById('lead-form');
    if (form) { form.reset(); }
    """)

    component
    |> put_state(:lead_status, :success)
    |> put_state(:lead_errors, [])
  end

  def action(:lead_rejected, params, component) do
    component
    |> put_state(:lead_status, :error)
    |> put_state(:lead_errors, params.errors)
  end

  def command(:persist_lead, params, server) do
    case Leads.create_lead(%{
           name: params.name,
           wedding_date: params.wedding_date,
           email: params.email
         }) do
      {:ok, _lead} ->
        put_action(server, :lead_saved)

      {:error, changeset} ->
        put_action(server, :lead_rejected, errors: changeset_error_messages(changeset))
    end
  end

  defp changeset_error_messages(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {field, msgs} -> Enum.map(msgs, &"#{field} #{&1}") end)
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  def template do
    ~HOLO"""
    <div class="min-h-screen">
      <div id="celebrations" class="p-6">
        <div class="max-w-3xl mx-auto">
          <div class="flex items-center justify-center gap-3 mb-1">
            <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70" fill="none" stroke="currentColor" stroke-width="1.2">
              <path d="M12 2c-6 6-6 20 0 36" />
              <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
            </svg>
            <h2 class="font-display text-xl sm:text-2xl text-center">
              Analyze Our Core Example
            </h2>
            <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
              <path d="M12 2c-6 6-6 20 0 36" />
              <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
            </svg>
          </div>
          <p class="text-center text-sm text-base-content/60 mb-6">
            Every celebration, organized into its own chapter — just like your site will be.
          </p>

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

            <div class="text-center mt-6">
              <Link to={PremierePage} class="link link-hover text-sm">
                See every celebration in the Premiere Hall &rarr;
              </Link>
            </div>
          {/if}
        </div>
      </div>

      <div id="how-it-works" class="border-y border-primary/30 py-8">
        <div class="max-w-3xl mx-auto px-6 grid grid-cols-1 sm:grid-cols-3 gap-6 text-center">
          <div>
            <div class="text-3xl">🔒</div>
            <p class="font-display text-sm mt-2">Secure &amp; Private</p>
          </div>
          <div>
            <div class="text-3xl">🎞️</div>
            <p class="font-display text-sm mt-2">Professional Curation</p>
          </div>
          <div>
            <div class="text-3xl">🔗</div>
            <p class="font-display text-sm mt-2">Custom Shareable Link</p>
          </div>
        </div>
      </div>

      <div id="scientific-importance" class="py-10 px-6">
        <div class="max-w-3xl mx-auto">
          <div class="flex items-center justify-center gap-3 mb-1">
            <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70" fill="none" stroke="currentColor" stroke-width="1.2">
              <path d="M12 2c-6 6-6 20 0 36" />
              <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
            </svg>
            <h2 class="font-display text-xl sm:text-2xl text-center">
              The Scientific Importance Of Focus
            </h2>
            <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
              <path d="M12 2c-6 6-6 20 0 36" />
              <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
            </svg>
          </div>
          <p class="text-center text-sm text-base-content/60 mb-6">
            Why identifying who matters in every scene makes for a smarter, more resonant film.
          </p>

          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <div class="flex flex-col items-center sm:flex-row sm:items-start gap-4 text-center sm:text-left">
                <div class="w-12 h-12 shrink-0 rounded-box bg-primary/10 border-2 border-primary/40 flex items-center justify-center">
                  <span class="hero-eye w-6 h-6 text-primary"></span>
                </div>
                <div>
                  <p class="text-sm text-base-content/70">
                    Human visual processing is highly selective — we naturally foveate, directing our sharpest attention toward whichever face or gesture is visually salient, emotionally resonant, or narratively important. In a crowded celebration, knowing who commands that visual prominence is what separates a scene that lands from one that blurs together.
                  </p>
                  <p class="text-sm text-base-content/70 mt-3">
                    Studies show that clearly-focused, prominent subjects lead to clearer emotional communication and stronger recall, while blurry or indistinct scenes create cognitive friction and disengagement. Our Focus Engine — pairing AI scene analysis with real community votes — exists to identify that ground-truth focus, scene by scene, for a truly immersive viewing experience.
                  </p>
                </div>
              </div>
              <div class="text-center mt-4">
                <Link to={ScienceOfFocusPage} class="btn btn-primary btn-sm">See The Full Science &rarr;</Link>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div id="start-your-story" class="p-6">
        <div class="max-w-md mx-auto card card-stock shadow-xl">
          <div class="card-body items-center text-center">
            <h2 class="font-display text-xl sm:text-2xl">Start Your Story</h2>
            <p class="text-sm text-base-content/60 -mt-1">Share your videos with us.</p>
            <div class="gold-divider w-16 my-3"></div>

            {%if @lead_status == :success}
              <p class="text-sm text-success">
                Thank you! We've received your details and will be in touch shortly.
              </p>
            {%else}
              {%if @lead_status == :error}
                <div class="text-sm text-error text-left w-full">
                  {%for message <- @lead_errors}
                    <p>{message}</p>
                  {/for}
                </div>
              {/if}
              <form id="lead-form" method="post" $submit="submit_lead" class="flex flex-col gap-3 w-full">
                <input
                  type="text"
                  name="name"
                  placeholder="Name"
                  required
                  class="input input-bordered w-full"
                />
                <input
                  type="date"
                  name="wedding_date"
                  placeholder="Wedding Date"
                  class="input input-bordered w-full"
                />
                <input
                  type="email"
                  name="email"
                  placeholder="Email"
                  required
                  class="input input-bordered w-full"
                />
                <button type="submit" class="btn btn-primary w-full">Get Started</button>
              </form>
            {/if}
          </div>
        </div>
      </div>

      <div class="bg-secondary text-secondary-content py-8 px-6 text-center">
        <p class="font-display text-lg sm:text-xl italic max-w-xl mx-auto text-balance">
          <span class="text-primary not-italic">&ldquo;</span>Our digital memory timeline is a family treasure!<span class="text-primary not-italic">&rdquo;</span>
        </p>
      </div>
    </div>
    """
  end
end
