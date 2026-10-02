# Shubh Vivahs

## What we're doing

https://shubhvivahs.com

We're building **Your Digital Wedding Memory Platform**: a couple's wedding film becomes a shared premiere instead of a file on a hard drive. Each film is scanned for faces and every guest is grouped and named. Family and friends watch in the Premiere Hall, vote on who's in focus in each scene, comment, and like. The couple curates it all from their admin view. Each feature is built and fully working before the next one starts, and this README is the single changelog and roadmap.

## Why we're doing it

A wedding film is usually watched once and forgotten. The best moments belong to the guests as much as the couple, but nobody can find one person's scene in a three-hour video. Organising the film around the people in it, and letting them react together, turns it into something families come back to. Keeping this README as the source of truth forces scope discipline: nothing ships without its purpose and status written down.

## How we'll know we're successful

- A guest can open a film, watch, vote, comment, and like, with no account and no help.
- A couple can ingest a film, name the faces, and publish it without touching code.
- Real UPI payments arrive through `/upgrade`, and `/admin/analytics` shows people coming back.
- Every feature ships working end to end; previews are labelled as previews.
- This README always matches what's actually true of the site.

## Status

- ✅ **Guests:** Premiere Hall, live focus voting, comments/replies/likes, view counts, quality picker (original/720p/360p), 35 themes.
- ✅ **Couple:** film library with public/private toggle, scene browser with face naming, free-access request review, live analytics with CSV export.
- ✅ **Marketing:** home, guide pages (How It Works, Premier Experience, Science of Focus), pricing, UPI upgrade.
- 🟡 **Previews only (sample data, no accounts yet):** login, register, dashboard, upload, share, invite team, edit event details.
- 🔲 **Not started:** scheduled synced showtimes, live comments/likes, share counts, ingesting from the admin view.

## Run locally

```bash
sudo apt-get install -y erlang-syntax-tools nodejs npm   # Ubuntu: syntax_tools is a separate package
mix setup                                                # deps + asset build
HOLOGRAM_START=1 mix phx.server                          # localhost:4000 (pages 404 without HOLOGRAM_START)
mix face_detection.setup                                 # one-time: face models + ffmpeg
mix face_detection.ingest PATH --title "Reception"       # add a film
mix precommit                                            # warnings-as-errors, format, test
```

Built with Elixir: Phoenix backend, [Hologram](https://www.hologram.page/) frontend, SQLite. Links: [site](https://shubhvivahs.com) · [Jira](https://home.atlassian.com/o/a7222d2d-be5e-4578-b4c9-32861c2cc4c5/s/711a8a41-4bbd-40db-8c37-f122f871ce2f/project/VSZJZPCZ-1)

**Practice:** new feature → add it to Status → mark ✅ when it ships, in the same commit. Code is truth; if this file drifts, fix the file.
