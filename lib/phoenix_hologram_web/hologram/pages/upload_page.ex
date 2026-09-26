defmodule PhoenixHologramWeb.Hologram.Pages.UploadPage do
  @moduledoc """
  Real video upload, gated behind `RequireAuthenticatedUser` like
  DashboardPage. The identity bar and account-tier card show the real
  signed-in user (`Accounts.superuser?/1`, `Accounts.premium?/1`) instead
  of the old sample "Rahul P. & Priya S." data, and the file list below
  the form is the same real shared movie catalog
  (`FaceDetection.list_movies_ordered/0`) DashboardPage's "My Uploaded
  Event Videos" card reads — this app has no per-couple event data
  model, so there's no per-user filter to apply here either (see
  DashboardPage's moduledoc). Like DashboardPage, this list is live: it
  subscribes to `:movies_changed` (`put_subscription/2`) so a status
  badge moves from Pending Review through Processing to Curated/Failed
  on its own as background ingestion progresses, not just at the one
  reload after finalize succeeds.

  The upload itself is chunked, not a single multipart POST, because a
  real wedding video can easily be larger than what a reverse proxy will
  let through in one request (Cloudflare caps request bodies at 100MB on
  its free/pro tiers, independent of anything this app's own
  `Plug.Parsers` config allows). `action(:upload_video_clicked, ...)`
  runs a `JS.exec` script — the whole flow has to be plain browser JS,
  not Hologram commands, since it needs `Blob.slice`/`XMLHttpRequest` and
  has to keep going across many sequential requests — that:

    1. Reads the chosen file from the (plain, non-Hologram) file input.
    2. Slices it into `PhoenixHologram.VideoUpload.chunk_size/0`-sized
       pieces and `POST`s them to `PhoenixHologramWeb.VideoUploadController
       .create_chunk/2` **one at a time, awaiting each response** before
       sending the next — never in parallel. Each chunk is sent via
       `XMLHttpRequest` rather than `fetch` specifically so
       `xhr.upload.onprogress` can drive the `<progress>` bar and status
       line with real byte-level progress as the chunk actually
       transfers — `fetch` has no upload-progress event, so with a
       40MB chunk on a slow connection the bar would otherwise sit
       frozen at the previous chunk's value for the whole transfer
       instead of animating continuously.
    3. Once every chunk has landed, `POST`s to
       `VideoUploadController.finalize/2`, which concatenates them back
       into one file server-side, inserts the `Movie` row, and kicks off
       background ingestion.

  Both endpoints return JSON (these are XHR requests, not a form
  submission), so the page never navigates at all — on success it
  dispatches the same `:movies_poll` action the live-update fallback
  timer uses (see below) to refresh the list immediately, instead of
  waiting on the next poll or on ingestion to finish, then resets the
  file input/progress bar so another file can be picked without a
  reload. All three requests carry the CSRF token Hologram's own runtime
  already set on `window.Hologram.csrfToken` — see
  `VideoUploadController`'s moduledoc for why that's validated manually
  instead of via Phoenix's own `:protect_from_forgery`.
  """

  use Hologram.Page
  use Hologram.JS

  alias Hologram.UI.Link
  alias PhoenixHologram.Accounts
  alias PhoenixHologram.FaceDetection
  alias PhoenixHologram.VideoUpload
  alias PhoenixHologramWeb.Hologram.Middleware.RequireAuthenticatedUser
  alias PhoenixHologramWeb.Hologram.Pages.AdminMoviesPage
  alias PhoenixHologramWeb.Hologram.Pages.DashboardPage
  alias PhoenixHologramWeb.Hologram.Pages.PlayerPage
  alias PhoenixHologramWeb.Hologram.Pages.UpgradePage

  route "/upload"

  middleware RequireAuthenticatedUser

  layout PhoenixHologramWeb.Hologram.Layouts.DefaultLayout

  def init(_params, component, server) do
    user = get_stash(server, :current_user)
    server = put_subscription(server, :movies_changed)

    component =
      component
      |> put_state(:current_user_name, user.name)
      |> put_state(:current_user_email, user.email)
      |> put_state(:superuser?, Accounts.superuser?(user))
      |> put_state(:premium?, Accounts.premium?(user))
      |> put_state(:accepted_formats, accepted_formats_label())
      |> put_state(:max_size_label, human_size_label(VideoUpload.max_bytes()))
      |> put_state(:max_bytes_value, VideoUpload.max_bytes())
      |> put_state(:chunk_size_bytes, VideoUpload.chunk_size())
      |> put_state(:movies, list_movies())

    {component, server}
  end

  # Dispatched via Hologram.Realtime.broadcast_action/2 from
  # PhoenixHologram.VideoUpload once a background ingestion finishes (see
  # its moduledoc) — the list below updates live instead of only ever
  # reflecting whatever it looked like at the last page load.
  def action(:movie_ingested, _params, component) do
    put_command(component, :refresh_movies)
  end

  def action(:movies_refreshed, params, component) do
    put_state(component, :movies, params.movies)
  end

  # Fallback safety net in case the broadcast above is ever missed (e.g.
  # the realtime connection dropped and reconnected in between) - fires
  # every 15s from the polling script near the template's end. Matches
  # AdminAnalyticsPage's :auto_refresh pattern.
  def action(:movies_poll, _params, component) do
    put_command(component, :refresh_movies)
  end

  # The whole upload has to happen in plain browser JS, not Hologram
  # commands: it needs `Blob.slice`/`fetch`, has to keep running across
  # many sequential requests without a server round trip driving each
  # step, and updates the progress bar/status line via direct DOM
  # mutation rather than a state-triggered re-render (a re-render mid-
  # upload would be wasted work and risks clobbering the very node it's
  # updating). See this module's doc for the full chunk → finalize flow.
  def action(:upload_video_clicked, _params, component) do
    max_bytes = component.state.max_bytes_value
    chunk_size = component.state.chunk_size_bytes
    max_size_label = component.state.max_size_label

    JS.exec("""
    (async () => {
      const fileInput = document.getElementById('video-file-input');
      const statusEl = document.getElementById('upload-status');
      const progressEl = document.getElementById('upload-progress-bar');
      const button = document.getElementById('upload-video-button');
      const file = fileInput && fileInput.files[0];

      function setStatus(text, tone) {
        if (!statusEl) { return; }
        statusEl.textContent = text;
        statusEl.className = 'text-xs mt-2 ' + (tone === 'error' ? 'text-error' : tone === 'success' ? 'text-success' : 'text-base-content/60');
      }

      if (!file) {
        setStatus('Please choose a video file.', 'error');
        return;
      }

      const MAX_BYTES = #{max_bytes};
      const CHUNK_SIZE = #{chunk_size};

      if (file.size > MAX_BYTES) {
        setStatus('Video must be smaller than #{max_size_label}.', 'error');
        return;
      }

      if (button) { button.disabled = true; }
      if (progressEl) { progressEl.value = 0; progressEl.max = 100; progressEl.classList.remove('hidden'); }
      setStatus('Uploading…', null);

      const uploadId = (window.crypto && window.crypto.randomUUID)
        ? window.crypto.randomUUID()
        : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
            const r = (Math.random() * 16) | 0;
            const v = c === 'x' ? r : (r & 0x3) | 0x8;
            return v.toString(16);
          });
      const totalChunks = Math.ceil(file.size / CHUNK_SIZE);
      const csrfToken = window.Hologram.csrfToken;

      // fetch() has no upload-progress event, so a single large chunk
      // (up to 40MB, which can take a while on a slow connection) would
      // leave the bar frozen at the previous chunk's value for the whole
      // transfer. XHR's upload.onprogress fires continuously as bytes
      // actually go out, so the bar reflects real progress, not a fake
      // decorative animation.
      function postWithProgress(url, formData, onProgress) {
        return new Promise((resolve, reject) => {
          const xhr = new XMLHttpRequest();
          xhr.open('POST', url);
          xhr.upload.onprogress = function (event) {
            if (event.lengthComputable && onProgress) { onProgress(event.loaded); }
          };
          xhr.onload = function () {
            let data = {};
            try { data = JSON.parse(xhr.responseText || '{}'); } catch (parseError) {}
            resolve({ ok: xhr.status >= 200 && xhr.status < 300, data: data });
          };
          xhr.onerror = function () { reject(new Error('Network error during upload.')); };
          xhr.send(formData);
        });
      }

      try {
        let bytesSentBeforeCurrentChunk = 0;

        for (let i = 0; i < totalChunks; i++) {
          const start = i * CHUNK_SIZE;
          const end = Math.min(start + CHUNK_SIZE, file.size);

          const formData = new FormData();
          formData.append('_csrf_token', csrfToken);
          formData.append('upload_id', uploadId);
          formData.append('chunk_index', String(i));
          formData.append('total_chunks', String(totalChunks));
          formData.append('chunk', file.slice(start, end), 'chunk');

          const chunkStartBytes = bytesSentBeforeCurrentChunk;

          const result = await postWithProgress('/videos/upload/chunk', formData, function (loaded) {
            const pct = Math.min(99, Math.round(((chunkStartBytes + loaded) / file.size) * 100));
            if (progressEl) { progressEl.value = pct; }
            setStatus('Uploading… ' + pct + '% (part ' + (i + 1) + ' of ' + totalChunks + ')', null);
          });

          if (!result.ok || result.data.status !== 'ok') {
            throw new Error((result.data && result.data.message) || 'Upload failed.');
          }

          bytesSentBeforeCurrentChunk += end - start;
        }

        setStatus('Finishing up…', null);

        const finalizeData = new FormData();
        finalizeData.append('_csrf_token', csrfToken);
        finalizeData.append('upload_id', uploadId);
        finalizeData.append('filename', file.name);
        finalizeData.append('total_chunks', String(totalChunks));

        const finalizeResult = await postWithProgress('/videos/upload/finalize', finalizeData, null);

        if (!finalizeResult.ok || finalizeResult.data.status !== 'ok') {
          throw new Error((finalizeResult.data && finalizeResult.data.message) || 'Upload failed.');
        }

        if (progressEl) { progressEl.value = 100; }

        setStatus('"' + finalizeResult.data.title + '" uploaded — curation is running now.', 'success');

        // No page reload: the new "Pending Review" row should show up
        // immediately rather than waiting for the next 15s poll or for
        // ingestion to finish, so force one refresh right now — reusing
        // the same :movies_poll action the fallback timer already uses
        // (see this page's moduledoc).
        Hologram.dispatchAction('movies_poll', 'page', {});

        if (fileInput) { fileInput.value = ''; }
        if (progressEl) { progressEl.value = 0; progressEl.classList.add('hidden'); }
        if (button) { button.disabled = false; }
      } catch (error) {
        setStatus((error && error.message) || 'Upload failed — please try again.', 'error');
        if (button) { button.disabled = false; }
      }
    })();
    """)

    component
  end

  def command(:refresh_movies, _params, server) do
    put_action(server, :movies_refreshed, movies: list_movies())
  end

  defp list_movies, do: FaceDetection.list_movies_ordered() |> Enum.map(&movie_view/1)

  defp movie_view(movie) do
    %{
      id: movie.id,
      title: movie.title || movie.path,
      badge_label: status_label(movie.status),
      badge_class: status_class(movie.status)
    }
  end

  defp status_label("done"), do: "Curated"
  defp status_label("processing"), do: "Processing"
  defp status_label("failed"), do: "Failed"
  defp status_label(_pending), do: "Pending Review"

  defp status_class("done"), do: "badge badge-success badge-sm"
  defp status_class("processing"), do: "badge badge-info badge-sm"
  defp status_class("failed"), do: "badge badge-error badge-sm"
  defp status_class(_pending), do: "badge badge-warning badge-sm"

  defp accepted_formats_label do
    VideoUpload.allowed_extensions()
    |> Enum.map(&(&1 |> String.trim_leading(".") |> String.upcase()))
    |> Enum.join(", ")
  end

  defp human_size_label(bytes) when rem(bytes, 1_000_000_000) == 0,
    do: "#{div(bytes, 1_000_000_000)}GB"

  defp human_size_label(bytes), do: "#{div(bytes, 1_000_000)}MB"

  def template do
    ~HOLO"""
    <div class="min-h-screen p-6">
      <div class="max-w-2xl mx-auto">
        <div class="flex flex-col items-center gap-1 mb-4 sm:flex-row sm:justify-center sm:gap-2">
          <span class="flex items-center gap-2 text-center">
            <span class="hero-user-circle w-4 h-4 text-base-content/50 shrink-0"></span>
            <span class="text-xs text-base-content/60 break-all">Signed in as {@current_user_name} ({@current_user_email})</span>
          </span>
        </div>

        <div class="flex items-center justify-center gap-3 mb-1">
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
          <h1 class="font-display text-xl sm:text-2xl text-center">
            Upload Your Vivah Videos
          </h1>
          <svg viewBox="0 0 24 40" class="w-4 h-8 text-primary/70 -scale-x-100" fill="none" stroke="currentColor" stroke-width="1.2">
            <path d="M12 2c-6 6-6 20 0 36" />
            <circle cx="10" cy="10" r="2.5" fill="currentColor" stroke="none" opacity="0.55" />
          </svg>
        </div>
        <p class="text-center text-sm text-base-content/60 mb-2">
          Add a video to your wedding catalog — curation starts automatically once it's uploaded.
        </p>
        <div class="gold-divider w-24 mx-auto mb-6"></div>

        <div class="card card-stock shadow-xl mb-6">
          <div class="card-body items-center text-center">
            <span class="hero-arrow-up-tray w-8 h-8 text-primary"></span>
            <p class="font-display text-lg">New Upload</p>

            <div class="mt-2 w-full flex flex-col items-center gap-3">
              <input
                type="file"
                id="video-file-input"
                accept="video/mp4,video/quicktime,video/webm,video/x-matroska,video/x-m4v"
                class="file-input file-input-bordered w-full max-w-xs"
              />

              <progress id="upload-progress-bar" class="progress progress-primary w-full max-w-xs hidden" value="0" max="100"></progress>
              <p id="upload-status" class="text-xs mt-2 min-h-4"></p>

              <button type="button" id="upload-video-button" $click="upload_video_clicked" class="btn btn-primary btn-block gap-2">
                <span class="hero-arrow-up-tray w-4 h-4"></span>
                Upload Video
              </button>
            </div>
            <p class="text-xs text-base-content/50 mt-1">
              {@accepted_formats}, up to {@max_size_label} — uploaded in chunks, so there's no single-request size limit.
            </p>
          </div>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-6">
          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <h2 class="font-display text-base uppercase tracking-wide">Uploaded Event Videos</h2>
              <script>
                {%raw}
                (function () {
                  if (window.__uploadMoviesPollAttached) { return; }
                  window.__uploadMoviesPollAttached = true;

                  // The :movie_ingested broadcast (see this page's moduledoc)
                  // updates this list within about a second of ingestion
                  // finishing — this is only a fallback in case one is ever
                  // missed (e.g. the realtime connection dropped and
                  // reconnected in between), so it doesn't need to be
                  // frequent.
                  setInterval(function () {
                    Hologram.dispatchAction('movies_poll', 'page', {});
                  }, 15000);
                })();
                {/raw}
              </script>
              {%if @movies == []}
                <p class="text-sm text-base-content/60 mt-2">No videos uploaded yet.</p>
              {%else}
                <ul class="text-sm text-base-content/70 mt-2 flex flex-col gap-1.5">
                  {%for movie <- @movies}
                    <li class="flex items-center gap-2">
                      <span class={movie.badge_class}>{movie.badge_label}</span>
                      <Link to={PlayerPage, id: movie.id} class="hover:underline">{movie.title}</Link>
                    </li>
                  {/for}
                </ul>
              {/if}
            </div>
          </div>

          <div class="card card-stock shadow-xl">
            <div class="card-body">
              <h2 class="font-display text-base uppercase tracking-wide">Your Account</h2>
              {%if @superuser?}
                <div class="flex items-center gap-2 mt-2">
                  <span class="badge badge-secondary gap-1">
                    <span class="hero-shield-check w-3.5 h-3.5"></span>
                    Superuser
                  </span>
                </div>
                <p class="text-sm text-base-content/70 mt-2">Access Tier: All Features Unlocked (Superuser)</p>
              {%else}
                <div class="flex items-center gap-2 mt-2">
                  {%if @premium?}
                    <span class="badge badge-success gap-1">
                      <span class="hero-check-badge w-3.5 h-3.5"></span>
                      Premium
                    </span>
                  {%else}
                    <span class="badge badge-outline gap-1">Free</span>
                  {/if}
                </div>
                {%if !@premium?}
                  <div class="mt-3">
                    <Link to={UpgradePage} class="btn btn-primary btn-sm gap-2">
                      <span class="hero-lock-open w-4 h-4"></span>
                      Upgrade To Premium
                    </Link>
                  </div>
                {/if}
              {/if}
            </div>
          </div>
        </div>

        <div class="flex flex-col items-center gap-3">
          <Link to={DashboardPage} class="btn btn-primary btn-block gap-2">
            <span class="hero-check-circle w-4 h-4"></span>
            Go To Dashboard
          </Link>
          {%if @superuser?}
            <Link to={AdminMoviesPage} class="btn btn-outline btn-block gap-2">
              <span class="hero-film w-4 h-4"></span>
              View In Admin
            </Link>
          {/if}
        </div>

        <div class="flex flex-wrap items-center justify-center gap-x-6 gap-y-2 mt-8 text-xs text-base-content/60">
          <span class="flex items-center gap-1">
            <span class="hero-shield-check w-4 h-4 text-primary"></span>
            Secure &amp; Private
          </span>
          <span class="flex items-center gap-1">
            <span class="hero-film w-4 h-4 text-primary"></span>
            Professional Curation
          </span>
          <span class="flex items-center gap-1">
            <span class="hero-link w-4 h-4 text-primary"></span>
            Custom Shareable Link
          </span>
        </div>
      </div>
    </div>
    """
  end
end
