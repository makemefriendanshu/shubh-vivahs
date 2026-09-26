# shubh-vivahs

Elixir web app: Phoenix backend + [Hologram](https://www.hologram.page/) frontend (compiles Elixir to JS, no separate JS framework). Built additively, one working feature at a time.

## What the site does

ShubhVivahs.com is a digital wedding-memory platform: a couple's wedding video is ingested and run through face-detection/clustering, then guests can browse a Premiere Hall of scenes, vote live on "who's in focus" per scene, comment, like, and watch view counts — all backed by an admin scene browser for naming faces and curating the movie listing. Around that pipeline sits a marketing/pricing site (Admin View bands, a real UPI-payment + admin-reviewed free-access flow) and a set of visual-only account pages (login/register/dashboard/upload/share/invite-team) previewing where accounts and self-serve uploads are headed next.

## Status

🟡 Face-recognition premiere pipeline built end to end: ingest → cluster → admin scene browser → viewer page with live focus-voting, comments, likes, and view counts. Gaps: showtime scheduling and live broadcast of comments/likes (only focus-vote counts are pushed live).

🟡 Marketing/account site layer added around that pipeline: guide pages, a pricing model with a real UPI payment + admin-reviewed free-access workflow, and visual-only login/register/dashboard/upload pages (no auth backend yet — see [Pages](#pages) and [Payments & free-access requests](#payments--free-access-requests)).

## Links

- Site: https://shubhvivahs.com
- [Jira project](https://home.atlassian.com/o/a7222d2d-be5e-4578-b4c9-32861c2cc4c5/s/711a8a41-4bbd-40db-8c37-f122f871ce2f/project/VSZJZPCZ-1)

## Stack

Elixir/Phoenix, Hologram, SQLite via Ecto (Postgres isn't available on every dev machine here).

## Run

```bash
mix setup       # one-time: deps, JS/CSS toolchain, asset build
mix phx.server  # start the app at localhost:4000
```

Face detection needs its own one-time asset download (models + `ffmpeg`) before you can ingest a movie:

```bash
mix face_detection.setup             # downloads YuNet/SFace models and ffmpeg into priv/face_detection/
mix face_detection.ingest PATH       # ingest a movie: detect, cluster, and persist faces
mix face_detection.ingest PATH --title "Reception"
```

Other mix tasks:

```bash
mix test                       # ecto.create + ecto.migrate + test
mix precommit                  # compile --warnings-as-errors, deps.unlock --unused, format, test
mix premiere.generate_previews # (after app.start) cache 720p/2.5Mbps "preview" and 360p/700kbps "minimal" proxies for movies that lack them, for bandwidth-constrained playback
```

### Theme

Every page is a Hologram page sharing one `DefaultLayout` (`lib/phoenix_hologram_web/hologram/layouts/default_layout.ex`) — gold/cream palette, a Cinzel/Cormorant Garamond display face, and a crossfading photo hero built from the ingested movies' thumbnails, rendered above every page's own content so it only has to be maintained in one place. Its identity band + nav render one of two ways depending on the page's `banner` prop: `/` (`banner: :home`, set by `HomePage`) gets a marketing-style header — a `ShubhVivahs.com` wordmark (`priv/static/images/home-logo.png`) flanked on desktop by a pair of hanging brass-lamp images (`priv/static/images/brass-lamp.png`, hidden below the `sm` breakpoint to keep mobile to one row), a "Your Digital Wedding Memory Platform" tagline, and a nav bar linking to in-page sections (How It Works, View Core Example, Create Yours) alongside the Feature Walkthrough/Recognised Faces/Theme dropdowns. Every other page keeps the original floral-heart logo (`priv/static/images/logo.svg`) identity band and Premiere Hall/Recognised Faces/Theme nav. The floral logo doubles as the browser-tab favicon (`priv/static/favicon.svg`, with a rasterized `favicon.ico` fallback for browsers without SVG favicon support) and the browser-tab title, "Shubh Vivaha", on every page regardless of which header is showing.

Every page also has a "Theme" picker (in the nav bar) listing all 35 daisyUI themes plus "System" — `light`/`dark` are the bespoke gold/cream and maroon/gold wedding palettes (`app.css`), the other 33 are daisyUI's stock presets. The full theme name list lives in `PhoenixHologramWeb.DaisyThemes`. The picked theme is stored under the `phx:theme` `localStorage` key, shared by `root.html.heex` and `DefaultLayout`, so it carries over between pages.

### Footer

`DefaultLayout`'s footer (below every page's `<slot />`) carries the same contact/social/CTA block as the marketing mockup: a WhatsApp-linked phone number, Instagram/YouTube/GitHub icons (the GitHub one linking to this repo), a "Register" button that jumps to `/`'s lead-capture form, and a copyright line with a server-computed year (`footer_year` state, set from `Date.utc_today().year`).

### Milestone highlight in movie listings

Any movie whose title contains "happy birthday" (case-insensitive) renders full-width (`sm:col-span-2`) with a gold/maroon card instead of the standard cream `card-stock` card, across all three listing grids (`/`, `/premiere`, `/admin`) — matching the milestone-card treatment in the design mockup, driven by a `highlight_card?/1` check in each page module rather than a hardcoded movie id. Every card's title is also a link into `/premiere/:id`, not just its thumbnail and "View Video" button.

### Loading spinner

Every page (`root.html.heex` and `DefaultLayout`) shows a full-page overlay — the wedding logo above a gold spinner ring — if the initial load is taking a moment, so a slow connection doesn't leave visitors staring at a blank tab. It's built and torn down entirely in an inline `<script>`/`<style>` placed ahead of the `app.css` `<link>` in `<head>` (a stylesheet blocks execution of any synchronous `<script>` after it, so the overlay has to come first to render before app.css itself has necessarily finished loading), revealed only after a short delay so a fast load never flashes it, and hidden once `window.load` fires. On Hologram pages it's appended outside `<body>` rather than declared in the page template, since the Hologram client runtime replaces its whole rendered DOM tree on mount and would otherwise wipe out the overlay's state.

### Mobile layout

`html { font-size: 27px }` (`app.css`) scales every rem-based Tailwind/daisyUI size ~1.7x site-wide, so a plain `w-64` renders at 432px, not the usual 256px — fine on desktop, but a fixed-width dropdown or a few "small" nested margins/gaps can blow past a phone's viewport. The quality-picker dropdown and the comment reply threads on `/premiere/:id` both hit this; fixed with a viewport-relative `max-w-[calc(...)]` cap and `sm:`-only spacing/avatar sizing so mobile gets a tighter layout without touching desktop. The `/` marketing nav hit it too — with 7 links/dropdowns in one `flex flex-wrap` bar, the scaled-up text and `tracking-[0.15em]` letter-spacing left room for only one item per line on phones, reading as a vertical list instead of a nav bar; fixed with `sm:`-only font-size and tracking so mobile packs several items per line without touching desktop. Any new fixed-width or deeply-nested mobile UI should be checked against this scaling before assuming a Tailwind class "looks about right" — rendering it (`/run`) at a mobile viewport is the only way to be sure, since this scaling isn't visible from the class names alone.

### Payments & free-access requests

`/upgrade` carries a real UPI QR (the site owner's actual VPA) and four amount tiers (₹501/1,501/3,501/6,001, matching `/pricing`'s bands). Two independent ways a tier gets marked paid, both converging on `PhoenixHologram.PaymentStore` (an in-memory, amount-keyed, time-windowed GenServer — not per-visitor, since there's no account system):

- **Real UPI payments**: a companion Android app (not part of this repo) reads incoming bank SMS notifications, extracts the amount, and posts it over WebSocket to `PhoenixHologramWeb.PaymentChannel` (mounted via `PaymentSocket` at `/payment_socket`, authenticated by a single shared-secret token — `PAYMENT_SOCKET_TOKEN` env var, fails closed if unset outside `:dev`). The channel records the payment and broadcasts it live (`Hologram.Realtime.broadcast_action/3`) to any open `/upgrade` tab subscribed on that tier.
- **Free-access requests**: "Know the founder personally?" on `/upgrade` lets a visitor describe their relation and submit — this only creates a `"pending"` row in `PhoenixHologram.PromoRequests` and opens a WhatsApp message to the owner; it grants nothing by itself. An admin approves or rejects it from `/admin/promo-requests`'s table (with a "Confirm Payment" and a "check status by code" input on `/upgrade` itself, for a visitor who reloaded and lost their in-memory promo-code state). Approving calls the exact same `PaymentStore.record_payment/1` + broadcast a real payment uses, so an approved request is indistinguishable from a payment to the rest of the page; rejecting a previously-approved request revokes it the same way.

Every piece here is deliberately honest about what's real: "Select Band" and the Login/Register/Dashboard/Upload forms are presentational (no backend), while the UPI QR, the WhatsApp links, and the promo-request review workflow are real and load-bearing.

### Page-visit tracking

`PhoenixHologramWeb.Plugs.PageVisitLogger` (mounted in the endpoint pipeline, ahead of `Hologram.Router`) records every Hologram page view into `page_visits` via `PhoenixHologram.Analytics` — both a fresh browser load and a subsequent client-side `Link` navigation, resolving each one to its friendly route path (e.g. `/premiere/:id` with the real id filled in) rather than Hologram's internal request path. Each row carries path, visitor IP, referrer, HTTP method, status, and response time. The `remote_ip` plug sits ahead of it so the recorded IP reflects the real client behind whatever reverse proxy/tunnel fronts the app, not the proxy's own address. Only visits recorded since this shipped are counted; there's no backfill for earlier traffic. `/admin/analytics` (see [Pages](#pages)) is the only consumer today.

The plug checks `Hologram.enabled?/0` before resolving a page's route, mirroring `Hologram.Router`'s own guard — without it, resolving against `PageModuleResolver`'s persistent term raises whenever Hologram's supervision tree isn't running (e.g. `mix test`, or `:dev` without `HOLOGRAM_START=1`), which would otherwise crash *every* request, not just ones worth tracking.

### Pages

- `/` — landing page, including a "Scientific Importance of Focus" section (foveation, cognitive load, emotional recall) that links through to the full `/science-of-focus` explainer.
- `/hologram` — Hologram demo page.
- `/premiere` — the movie listing grid: title, thumbnail, and, once an admin has filled them in from `/admin/movies/:id`, a blurb plus a "date | location" line — in place of raw file metadata (resolution/size are still shown in the player's quality picker, see below).
- `/admin` — the movie listing grid, and nothing else; `/admin/promo-requests` and `/admin/analytics` are reached from the site-wide nav bar, not linked from here.
- `/admin/promo-requests` — table of free-access requests submitted from `/upgrade` (see [Payments & free-access requests](#payments--free-access-requests)), with Approve/Reject (and "Approve Anyway"/"Revoke" to flip a decision either way) — live-updating across every open tab on new submissions, approvals, and rejections, not just a manual reload. Linked from the site-wide nav bar.
- `/admin/analytics` — real admin analytics dashboard backed by page-visit tracking (see [Page-visit tracking](#page-visit-tracking)): top visited URLs, total page views, a real top-IPs breakdown (donut — there's no geo-IP database, so it's IPs rather than invented regions), other metrics (premium activations, average response time, traffic growth vs. the prior period, comments posted), and a sortable, infinite-scrolling visit-log table (date/time in IST, visitor IP, URL, referrer, method, response time). Filterable by date range, link, visitor IP, HTTP method, referrer, and response-time range (with a hint showing the actual min/max response time seen), each with a visible highlight when active and a one-click "Clear Filters"; the whole filter panel collapses behind a Show/Hide Filters toggle, independent of that highlight/badge/export so they stay reachable either way. A matching CSV export follows the same filters. Live updates push to any open tab within about a second of a new visit anywhere on the site (60s fallback poll), without disrupting an admin who has scrolled past the first page of results. Linked from the site-wide nav bar.
- `/admin/movies/:id` — per-movie scene timeline and recognised faces (nameable, with thumbnails and timestamp ranges badged as playable clips, each carrying a focus-vote count that always matches the scene shown when clicked). The scene-preview modal shows the clip and the "who's in focus" voting panel side by side, with the same hover-to-pause behavior as `/premiere/:id`. Also has an "Edit listing details" panel for that movie's blurb, event date, and location.
- `/premiere/:id` — plays a movie, with:
  - the movie's duration and, if set, its admin-authored blurb, both above the video (the blurb previously wasn't wired up here — it rendered on `/premiere` and `/admin` but got silently shadowed by the duration string on this page)
  - live "who's in focus" voting: multiple named faces per scene, each showing its vote count, a "your vote" indicator, and a "leading" badge on whichever face(s) currently hold the most votes in that scene (ties badge everyone tied for first) — voting identity is scoped to the page load, so refreshing lets you vote again — laid out as the same compact, wrapping card grid as the admin scene-preview panel (and the Science of Focus demo panel — all three share this pattern, duplicated per page rather than shared). Hovering the panel pauses the video and shows a live "Playing"/"Paused" badge; moving off it resumes playback only if it was actually playing when the hover started. A vote's checkmark/count updates optimistically on click, before the server round trip confirming it lands. Stays correct while playing an individual part too: each part file's own clock restarts at 0, so the client adds back that part's probed start offset before matching scenes, rather than the scene lookup silently going stale
  - comments (replies + likes), each poster naming themselves and shown with an avatar of their name's initial
  - a like button — toggles liked/unliked within the current view, but (like focus votes) isn't remembered across reloads: refreshing always resets it to "ready to like", e.g. for a shared/kiosk screen, while the total count persists
  - a view count — recorded once per movie per page load, the first time playback actually starts (pausing/scrubbing/replaying doesn't add more)
  - a themed quality-picker dropdown (original, 720p "preview", or 360p "minimal") for playback and downloads (full movie, or independently-retryable parts via a dropdown) — see [Mobile layout](#mobile-layout) for how it (and the comment threads above) stay on-screen on phones

  Over the ngrok tunnel, large videos are bandwidth-capped (free tier), so playback can stall on multi-GB files — fine on localhost.

- `/how-it-works`, `/premier-experience`, `/science-of-focus` — guide pages explaining the viewer/admin split, the streaming/community layer, and the face-detection-plus-voting pipeline behind "who's leading" each scene, cross-linked to each other and to `/pricing`/`/upgrade`. `/science-of-focus` opens with a "Scientific Importance of Focus" card grounding the whole pipeline in visual-attention research (foveation, cognitive load, emotional recall), and also hosts a live demo — the (movie, scene) pair with the most votes so far, playable and votable right on the page, sharing the focus-vote panel and hover-to-pause pattern above.
- `/pricing` — four Admin View bands (Standard/Silver/Gold/Platinum) by video count, storage, and runtime, plus a "Founder's Circle" free-Band-I offer. No checkout exists, so "Select Band" is presentational; the Founder's Circle CTA opens a real WhatsApp chat.
- `/upgrade` — a second, simpler pricing model (Classic vs. a Premium unlock, reusing How It Works' Admin View copy) aimed at `/dashboard`'s "Get Premium" button, with the real UPI payment flow and free-access request form — see [Payments & free-access requests](#payments--free-access-requests).
- `/login`, `/register`, `/dashboard`, `/upload`, `/share`, `/invite-team`, `/sent-invitations`, `/edit-event-details` — visual-only account pages (no user/auth system exists yet): styled forms that don't authenticate anyone, and dashboard/upload/share/invite-team/sent-invitations/edit-event-details pages shown with fixed sample data rather than a real account's. `/share` (linked from Dashboard's "Generate Shareable Link" quick action) previews password protection, an expiry date/time, guest downloads, and a private message, plus one sample active link. `/invite-team` (linked from Dashboard's "Invite Team" quick action) previews the current team roster and an invite-by-email form with a remaining-invitations meter, and links on to `/sent-invitations`, which previews a pending/accepted/expired invitation list with Resend/Revoke actions. `/edit-event-details` (linked from Dashboard's "Edit Event Details" quick action, which previously pointed at `/admin` by mistake) previews editing the vivah title/date/location/guest count and a private family note, alongside a photo-upload and custom-domain panel. All of it is decorative, since there's no link/share, team/invite, or event-editing system yet — every dashboard sub-page (`/upgrade` included) links back to `/dashboard` so none of them is a dead end. Buttons link to whatever's actually real today (Admin View, Pricing/Upgrade, Dashboard, Invite Team) instead of fake flows, with an honest "coming soon" note where nothing exists yet.

## Feature Log

| # | Feature | Status |
|---|---------|--------|
| 0 | Scaffold Phoenix application (no Ecto) | ✅ Done |
| 1 | Add and configure Hologram, verify with a minimal interactive page | ✅ Done |
| 2 | Style the Hologram page with daisyUI | ✅ Done |
| 3 | Add a Reset button to the Hologram counter | ✅ Done |
| 4 | Face detection: ingest video, cluster unique faces | ✅ Done — YuNet+SFace via Evision, ffmpeg for frame sampling. Clusters by running-centroid cosine similarity, not single-linkage (avoids chaining distinct faces together) |
| 5 | Scene index: map each face to its timestamp ranges | ✅ Done — `FaceDetection.SceneIndex` collapses detections into ranges and derives the movie's scene timeline |
| 6 | Admin page: per-movie scene browser grouped by face | ✅ Done — Scenes and All recognised faces laid out side by side, faces ranked by focus-vote count; admins can also cast focus votes from the scene preview, synced live with `/premiere/:id` over the same PubSub channel. Timestamp badges read as playable clips (play-icon chip) and each one's vote count always matches the scene that opens when clicked, so a face's "N in focus" total is exactly the sum of its badges. A single-instant badge (start == end, most of them, since detections sample at ~1fps) parks the player on that exact frame rather than playing past it. Each badge also carries a "your vote" indicator and every vote's timestamp as a hover tooltip. Casting a vote stays responsive on movies with hundreds of scenes — the client-side update after a vote is O(1) per affected timestamp range and O(1) per scene bucket, not a full rescan (that rescan used to hang or crash the tab on a click). Saving a movie title or a face label auto-collapses its edit panel |
| 7 | Premiere Hall viewer page: scheduled, synced playback | 🟡 No showtime scheduling yet; playback not synced across viewers |
| 8 | Live comments during a showtime | 🟡 Post/reply/like/delete works, each poster names themselves and gets an initial avatar, but isn't broadcast live to co-viewers |
| 9 | Live focus-voting + share-count tracking | 🟡 Focus voting is live (PubSub) and allows multiple faces per scene, with a "leading" badge on the current top vote-getter(s), hover-to-pause/resume over the panel (see below), and an optimistic vote checkmark/count that updates before the server confirms; share-count tracking not implemented |
| 10 | Gold/cream wedding-invitation theme across all pages | ✅ Done — see [Theme](#theme) |
| 11 | Selectable daisyUI theme picker on every page | ✅ Done — see [Theme](#theme) |
| 12 | Movie view count | ✅ Done — recorded once per movie per page load, the first time playback starts |
| 13 | Wedding logo + favicon | ✅ Done — see [Theme](#theme) |
| 14 | Branded full-page loading spinner on slow initial loads | ✅ Done — see [Loading spinner](#loading-spinner) |
| 15 | Admin-authored blurb + date/location on movie cards | ✅ Done — replaces the raw resolution/size line on `/premiere` and `/admin`; edited per movie from `/admin/movies/:id`; also shown above the video on `/premiere/:id` |
| 16 | Marketing-style header + nav on `/`, distinct from the rest of the site | ✅ Done — see [Theme](#theme); mobile nav wrapping fixed, see [Mobile layout](#mobile-layout) |
| 17 | Marketing footer (contact/social/register) + milestone-video highlight in listings | ✅ Done — see [Footer](#footer) and [Milestone highlight in movie listings](#milestone-highlight-in-movie-listings) |
| 18 | Guide pages (How It Works, Premier Experience, Science of Focus) with a live vote demo | ✅ Done — see [Pages](#pages) |
| 19 | Nav dropdowns open on hover, not just click | ✅ Done |
| 20 | Hover-to-pause the video over "who's in focus" on all three focus-vote panels, with a live Playing/Paused badge | ✅ Done — see the `/premiere/:id` entry in [Pages](#pages) |
| 21 | Pricing (`/pricing`) and Premium upgrade (`/upgrade`) pages, with a real UPI payment + admin-reviewed free-access workflow | ✅ Done — see [Payments & free-access requests](#payments--free-access-requests) |
| 22 | Visual-only Login/Register/Dashboard/Upload account pages | ✅ Done — no auth or upload backend exists yet; see [Pages](#pages) |
| 23 | Visual-only Generate Shareable Link page, linked from Dashboard | ✅ Done — no link/share backend exists yet; see [Pages](#pages) |
| 24 | Visual-only Invite Team + Manage Sent Invitations pages, linked from Dashboard | ✅ Done — no team/invite backend exists yet; see [Pages](#pages) |
| 25 | Visual-only Edit Event Details page, linked from Dashboard (fixing a quick action that used to open `/admin` instead); every dashboard sub-page links back to Dashboard | ✅ Done — no event-editing backend exists yet; see [Pages](#pages) |
| 26 | "Scientific Importance of Focus" section on the home page, and a fuller scientific-importance writeup on `/science-of-focus` (foveation, cognitive load, emotional recall) | ✅ Done — see [Pages](#pages) |
| 27 | Visual-only Admin Analytics dashboard (visited URLs, link clicks, unique IPs, visit log), linked from the site nav bar | ✅ Done — superseded by #29; see [Pages](#pages) |
| 28 | Split the Promo Requests table out of `/admin` into its own `/admin/promo-requests` page, linked from the site nav bar | ✅ Done — see [Pages](#pages) |
| 29 | Make Admin Analytics real: page-visit tracking with the real client IP behind the tunnel, working filters (date range/link/IP/method/referrer/response-time range) with a matching CSV export, a sortable + infinite-scrolling visit log, and live updates pushed to every open tab | ✅ Done — see [Page-visit tracking](#page-visit-tracking) and [Pages](#pages) |
| 30 | Collapsible filter panel on Admin Analytics (Show/Hide Filters), plus fixing PageVisitLogger to skip tracking rather than crash whenever Hologram itself isn't running (e.g. under `mix test`, or any boot without `HOLOGRAM_START=1`) | ✅ Done — see [Page-visit tracking](#page-visit-tracking) and [Pages](#pages) |

Legend: 🔲 Not started · 🟡 In progress · ✅ Done

## Practice

New feature → add a `Not started` row above → flip to `In progress` while building → flip to `Done` with a one-line note when it ships. Keep this README in sync with the code — update it in the same commit as the feature it describes. Code is truth; if this file drifts from it, fix the file.
