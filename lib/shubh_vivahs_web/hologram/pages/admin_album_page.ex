defmodule ShubhVivahsWeb.Hologram.Pages.AdminAlbumPage do
  @moduledoc """
  Admin page for one photo album, `/admin/<uploader>/photos/<slug>`:
  rename it and edit its details, make it public or private, run face
  recognition (with progress), and name the people it found.

  Form fields are read on submit (`$submit`) rather than tracked per
  keystroke: with a few hundred people in state, every Hologram action
  re-walks all of it.
  """

  use Hologram.Page
  use Hologram.JS

  alias ShubhVivahs.MovieSlug
  alias ShubhVivahs.Photos
  alias ShubhVivahs.Photos.AlbumJobs
  alias ShubhVivahs.Photos.RecognitionRunner
  alias ShubhVivahsWeb.Hologram.Middleware.RequireSuperuser

  route "/admin/:uploader/photos/:album"
  param :uploader, :string
  param :album, :string

  middleware RequireSuperuser

  layout ShubhVivahsWeb.Hologram.Layouts.DefaultLayout

  def init(params, component, server) do
    album = Photos.get_album_by_slug(params.album)

    component =
      if album do
        job = job_view(album)

        component
        |> put_state(:album, album_view(album))
        |> put_state(:job, job)
        |> put_state(:people, Photos.people(album))
        |> put_state(:message, nil)
        |> put_state(:recognition_confirm, false)
        |> put_state(:polling?, job.running?)
        |> then(fn c ->
          if job.running?, do: put_action(c, name: :poll_job, params: %{}, delay: 3000), else: c
        end)
      else
        component
        |> put_state(:album, nil)
        |> put_state(:people, [])
      end

    {component, server}
  end

  def action(:save_details, params, component) do
    form = params.event

    put_command(component, :persist_details,
      album_id: component.state.album.id,
      title: String.trim(Map.get(form, "title", "")),
      description: blank_to_nil(Map.get(form, "description")),
      location: blank_to_nil(Map.get(form, "location")),
      event_date: blank_to_nil(Map.get(form, "event_date"))
    )
  end

  def action(:details_saved, params, component) do
    if params.album.slug != component.state.album.slug do
      # Renamed: the URL changed with the slug.
      JS.exec("window.location.replace(#{inspect(params.album.admin_path)});")
    end

    put_state(component, album: params.album, message: params.message)
  end

  def action(:toggle_public, _params, component) do
    put_command(component, :persist_public,
      album_id: component.state.album.id,
      public: !component.state.album.public
    )
  end

  def action(:recognition_clicked, _params, component) do
    if component.state.people != [],
      do: put_state(component, recognition_confirm: true, message: nil),
      else: start_recognition(component)
  end

  def action(:run_recognition, _params, component), do: start_recognition(component)

  def action(:cancel_recognition, _params, component),
    do: put_state(component, :recognition_confirm, false)

  # Recognition may run in another OS process (`mix photos.detect_faces`)
  # that cannot push to this page, so it polls every 3s while running.
  def action(:poll_job, _params, component) do
    put_command(component, :refresh_job, album_id: component.state.album.id)
  end

  def action(:job_refreshed, params, component) do
    was_running? = component.state.job.running?
    component = put_state(component, job: params.job, recognition_confirm: false)

    cond do
      was_running? and not params.job.running? ->
        # New people: reload rather than rebuild the page state here.
        JS.exec("window.location.reload();")
        component

      params.job.running? ->
        component
        |> put_state(:polling?, true)
        |> put_action(name: :poll_job, params: %{}, delay: 3000)

      true ->
        put_state(component, :polling?, false)
    end
  end

  def action(:job_start_failed, params, component) do
    put_state(component, message: params.message, recognition_confirm: false)
  end

  def action(:save_person, params, component) do
    put_command(component, :persist_person,
      face_id: params.face_id,
      label: blank_to_nil(Map.get(params.event, "label")),
      subtitle: blank_to_nil(Map.get(params.event, "subtitle"))
    )
  end

  def action(:person_saved, params, component) do
    people =
      Enum.map(component.state.people, fn person ->
        person =
          if person.id == params.face_id,
            do: %{person | label: params.label, subtitle: params.subtitle},
            else: person

        # A new name can also renumber a namesake's slug.
        %{person | slug: Map.get(params.slugs, person.id, person.slug)}
      end)

    put_state(component, people: people, message: nil)
  end

  def command(:persist_details, params, server) do
    album = Photos.get_album(params.album_id)

    attrs = %{
      title: params.title,
      description: params.description,
      location: params.location,
      event_date: params.event_date
    }

    case Photos.update_album(album, attrs) do
      {:ok, album} ->
        put_action(server, :details_saved, album: album_view(album), message: "Saved.")

      {:error, changeset} ->
        message =
          changeset.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field} #{msg}" end)
          |> Enum.join(", ")

        put_action(server, :details_saved,
          album: album_view(album),
          message: "Not saved: #{message}"
        )
    end
  end

  def command(:persist_public, %{album_id: album_id, public: public}, server) do
    {:ok, album} = Photos.update_album(Photos.get_album(album_id), %{public: public})
    put_action(server, :details_saved, album: album_view(album), message: nil)
  end

  def command(:start_recognition, %{album_id: album_id}, server) do
    case RecognitionRunner.start(album_id) do
      :ok ->
        put_action(server, :job_refreshed, job: job_view(Photos.get_album(album_id)))

      {:error, reason} ->
        put_action(server, :job_start_failed, message: start_error(reason))
    end
  end

  def command(:refresh_job, %{album_id: album_id}, server) do
    put_action(server, :job_refreshed, job: job_view(Photos.get_album(album_id)))
  end

  def command(:persist_person, params, server) do
    {:ok, face} = Photos.label_face(params.face_id, params.label, params.subtitle)

    put_action(server, :person_saved,
      face_id: params.face_id,
      label: params.label,
      subtitle: params.subtitle,
      slugs: Photos.person_slugs(Photos.get_album(face.album_id))
    )
  end

  defp start_recognition(component) do
    component
    |> put_state(recognition_confirm: false, message: nil)
    |> put_command(:start_recognition, album_id: component.state.album.id)
  end

  defp start_error(:busy),
    do: "The server is already running a heavy job. Try again when it ends."

  defp start_error(:already_running), do: "Recognition is already running for this album."
  defp start_error(:not_found), do: "This album no longer exists."

  defp album_view(album) do
    uploader = MovieSlug.uploader_slug_for(album.user_id)

    %{
      id: album.id,
      title: album.title,
      slug: album.slug,
      public: album.public,
      description: album.description,
      location: album.location,
      event_date: album.event_date && Date.to_iso8601(album.event_date),
      photo_count: Photos.photo_count(album),
      view_path: Photos.album_path(album),
      admin_path: "/admin/#{uploader}/photos/#{album.slug}"
    }
  end

  defp job_view(album) do
    job = AlbumJobs.get(album.id, "recognition")

    state =
      cond do
        job == nil -> :not_run
        AlbumJobs.stalled?(job) -> :stalled
        true -> String.to_existing_atom(job.status)
      end

    %{
      running?: state == :running,
      stalled?: state == :stalled,
      label: job_label(state),
      badge_class: job_badge_class(state),
      stage: job && job.stage,
      percent: state == :running && job.progress && round(job.progress * 100),
      eta: state == :running && format_eta(AlbumJobs.seconds_left(job)),
      error: state == :failed && job.message
    }
  end

  defp job_label(:running), do: "Running"
  defp job_label(:stalled), do: "Stalled"
  defp job_label(:done), do: "Done"
  defp job_label(:failed), do: "Failed"
  defp job_label(:not_run), do: "Not run yet"

  defp job_badge_class(:running), do: "badge badge-sm badge-info"
  defp job_badge_class(:stalled), do: "badge badge-sm badge-warning"
  defp job_badge_class(:done), do: "badge badge-sm badge-success"
  defp job_badge_class(:failed), do: "badge badge-sm badge-error"
  defp job_badge_class(:not_run), do: "badge badge-sm badge-ghost"

  defp format_eta(nil), do: nil
  defp format_eta(seconds) when seconds < 60, do: "under a minute left"
  defp format_eta(seconds), do: "about #{div(seconds, 60) + 1} min left"

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def template do
    ~HOLO"""
    <div class="min-h-screen p-4 sm:p-6">
      <div class="max-w-5xl mx-auto">
        <a href="/admin" class="link link-hover text-sm">&larr; Admin</a>

        {%if @album == nil}
          <div class="card card-stock shadow-xl mt-4">
            <div class="card-body p-4 sm:p-8">
              <p class="text-base-content/70">This album could not be found.</p>
            </div>
          </div>
        {%else}
          <div class="flex flex-wrap items-center gap-2 sm:gap-3 mt-3 mb-4">
            <h1 class="font-display text-2xl sm:text-3xl break-words min-w-0">{@album.title}</h1>
            <button
              type="button"
              id="album-visibility"
              $click="toggle_public"
              class={if(@album.public, do: "badge badge-success gap-1 cursor-pointer", else: "badge badge-ghost gap-1 cursor-pointer")}
              title="Click to toggle whether signed-out visitors can see this album"
            >
              <span class={if(@album.public, do: "hero-eye w-3 h-3", else: "hero-eye-slash w-3 h-3")}></span>
              {if(@album.public, do: "Public", else: "Private")}
            </button>
            <a href={@album.view_path} id="album-view-link" class="btn btn-sm btn-primary ml-auto">View album &rarr;</a>
          </div>
          <p class="text-sm text-base-content/60 -mt-2 mb-4">{@album.photo_count} photos · {@album.view_path}</p>

          {%if @message}
            <div role="status" class="alert alert-info text-sm mb-4 py-2">{@message}</div>
          {/if}

          <div class="grid gap-4 md:grid-cols-2 items-start mb-6">
            <form id="album-details-form" $submit="save_details" class="card card-stock shadow-xl">
              <div class="card-body p-4 sm:p-6 gap-3">
                <h2 class="card-title font-display text-lg">Details</h2>
                <label class="form-control">
                  <span class="label-text text-sm mb-1">Title</span>
                  <input type="text" name="title" value={@album.title} required class="input input-bordered input-sm w-full" />
                </label>
                <label class="form-control">
                  <span class="label-text text-sm mb-1">Description</span>
                  <textarea name="description" rows="2" class="textarea textarea-bordered textarea-sm w-full">{@album.description}</textarea>
                </label>
                <div class="grid grid-cols-1 min-[480px]:grid-cols-2 gap-3">
                  <label class="form-control">
                    <span class="label-text text-sm mb-1">Date</span>
                    <input type="date" name="event_date" value={@album.event_date} class="input input-bordered input-sm w-full" />
                  </label>
                  <label class="form-control">
                    <span class="label-text text-sm mb-1">Location</span>
                    <input type="text" name="location" value={@album.location} class="input input-bordered input-sm w-full" />
                  </label>
                </div>
                <p class="text-xs text-base-content/50">Changing the title changes the album link.</p>
                <div class="card-actions justify-end">
                  <button type="submit" id="album-details-save" class="btn btn-sm btn-primary">Save details</button>
                </div>
              </div>
            </form>

            <div id="album-recognition" class="card card-stock shadow-xl">
              <div class="card-body p-4 sm:p-6 gap-3">
                <div class="flex items-center gap-2">
                  <h2 class="card-title font-display text-lg">Face recognition</h2>
                  <span class={@job.badge_class}>{@job.label}</span>
                </div>
                <p class="text-sm text-base-content/70">
                  Finds the people in every photo, for the viewer&rsquo;s &ldquo;Who&rsquo;s in focus?&rdquo; votes. Takes about 0.4 s per photo.
                </p>
                {%if @job.running?}
                  <div>
                    <div class="flex justify-between text-xs text-base-content/60 mb-1">
                      <span>{@job.stage || "Starting"}</span>
                      <span>{@job.percent}%{%if @job.eta} · {@job.eta}{/if}</span>
                    </div>
                    <progress class="progress progress-primary w-full" value={@job.percent || 0} max="100"></progress>
                  </div>
                {/if}
                {%if @job.error}
                  <p class="text-sm text-error break-words">{@job.error}</p>
                {/if}
                {%if @recognition_confirm}
                  <div class="alert alert-warning text-sm py-2 flex flex-wrap gap-2">
                    <span>Re-running replaces the people found and clears their focus votes. Names are kept.</span>
                    <div class="flex gap-2 ml-auto">
                      <button type="button" id="recognition-cancel" $click="cancel_recognition" class="btn btn-xs btn-ghost">Cancel</button>
                      <button type="button" id="recognition-confirm" $click="run_recognition" class="btn btn-xs btn-warning">Re-run</button>
                    </div>
                  </div>
                {%else}
                  <div class="card-actions justify-end">
                    <button type="button" id="recognition-run" $click="recognition_clicked" disabled={@job.running?} class="btn btn-sm btn-secondary">
                      {if(@people == [], do: "Run face recognition", else: "Re-run face recognition")}
                    </button>
                  </div>
                {/if}
              </div>
            </div>
          </div>

          <div id="album-people">
            <div class="flex flex-wrap items-center gap-2 mb-3">
              <h2 class="font-display text-xl">People <span class="text-base-content/50 text-base">({length(@people)})</span></h2>
              {%if @people != []}
                <div class="flex flex-wrap gap-1 ml-auto" role="group" aria-label="Sort people">
                  <button type="button" data-people-sort="photos" class="btn btn-xs btn-ghost">Most photos</button>
                  <button type="button" data-people-sort="votes" class="btn btn-xs btn-ghost">Most votes</button>
                  <button type="button" data-people-sort="named" class="btn btn-xs btn-ghost">Named first</button>
                  <button type="button" data-people-sort="unnamed" class="btn btn-xs btn-ghost">Unnamed first</button>
                </div>
              {/if}
            </div>
            {%if @people == []}
              <p class="text-sm text-base-content/60">No people yet: run face recognition.</p>
            {/if}
            <div id="people-grid" class="grid grid-cols-1 min-[480px]:grid-cols-2 lg:grid-cols-3 gap-3">
              {%for person <- @people}
                <form
                  id={"person-#{person.id}"}
                  $submit={:save_person, face_id: person.id}
                  data-photos={person.photos}
                  data-votes={person.votes}
                  data-named={if(person.label, do: "1", else: "0")}
                  class="card card-stock shadow p-3 flex flex-row gap-3 items-start"
                >
                  <a href={"#{@album.view_path}?person=#{person.slug}"} class="shrink-0" tabindex="-1" aria-hidden="true">
                    <img src={person.face_url} alt="" loading="lazy" class="w-16 h-16 sm:w-20 sm:h-20 rounded-box object-cover bg-base-300 hover:ring-2 hover:ring-primary transition" />
                  </a>
                  <div class="flex-1 min-w-0 flex flex-col gap-1.5">
                    <p class="text-xs text-base-content/60 tabular-nums">
                      <a href={"#{@album.view_path}?person=#{person.slug}"} id={"person-photos-#{person.id}"} class="link link-primary font-semibold" title="See every photo this person is in">{person.photos} photos &rarr;</a>
                      · &hearts; {person.votes}
                    </p>
                    <input type="text" name="label" value={person.label} placeholder="Name" aria-label="Name" class="input input-bordered input-xs w-full" />
                    <input type="text" name="subtitle" value={person.subtitle} placeholder="e.g. Bride, uncle" aria-label="Who they are" class="input input-bordered input-xs w-full" />
                    <button type="submit" class="btn btn-xs btn-outline self-end">Save</button>
                  </div>
                </form>
              {/for}
            </div>
          </div>

          <script>
            {%raw}
            // Sorts the people cards in the browser (CSS order), so changing
            // the sort costs no Hologram action. The choice is remembered per
            // browser. No quote marks or backslashes in comments here.
            (function () {
              if (window.__peopleSortAttached) { return; }
              window.__peopleSortAttached = true;
              var STORE = "admin-people-sort";
              function saved() {
                try { return localStorage.getItem(STORE) || "photos"; } catch (e) { return "photos"; }
              }
              function num(el, name) { return parseInt(el.getAttribute(name), 10) || 0; }
              var keys = {
                photos: function (c) { return num(c, "data-photos") * 1000000 + num(c, "data-votes"); },
                votes: function (c) { return num(c, "data-votes") * 1000000 + num(c, "data-photos"); },
                named: function (c) { return num(c, "data-named") * 1000000 + num(c, "data-photos"); },
                unnamed: function (c) { return (1 - num(c, "data-named")) * 1000000 + num(c, "data-photos"); }
              };
              function apply(sort) {
                var grid = document.getElementById("people-grid");
                if (!grid) { return; }
                var key = keys[sort] || keys.photos;
                Array.prototype.slice.call(grid.children)
                  .map(function (card, i) { return [key(card), i, card]; })
                  .sort(function (a, b) { return (b[0] - a[0]) || (a[1] - b[1]); })
                  .forEach(function (entry, position) { entry[2].style.order = position; });
                var buttons = document.querySelectorAll("[data-people-sort]");
                for (var i = 0; i < buttons.length; i++) {
                  var on = buttons[i].getAttribute("data-people-sort") === sort;
                  buttons[i].classList.toggle("btn-primary", on);
                  buttons[i].classList.toggle("btn-ghost", !on);
                  buttons[i].setAttribute("aria-pressed", on ? "true" : "false");
                }
              }
              document.addEventListener("click", function (e) {
                var button = e.target.closest && e.target.closest("[data-people-sort]");
                if (!button) { return; }
                var sort = button.getAttribute("data-people-sort");
                try { localStorage.setItem(STORE, sort); } catch (err) {}
                apply(sort);
              });
              var queued = false;
              function schedule() {
                if (queued) { return; }
                queued = true;
                requestAnimationFrame(function () { queued = false; apply(saved()); });
              }
              new MutationObserver(schedule).observe(document.documentElement, {
                subtree: true, childList: true, attributes: true,
                attributeFilter: ["data-votes", "data-named", "data-photos"]
              });
              schedule();
            })();
            {/raw}
          </script>
        {/if}
      </div>
    </div>
    """
  end
end
