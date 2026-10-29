# Digital wellbeing

Screen time and app usage from all your devices on one dashboard.

[ActivityWatch](https://activitywatch.net) records usage on each device but
keeps the data on that device. A small agent next to it forwards everything to
one server, which stores it and shows the dashboard.

```
device: ActivityWatch ──(localhost:5600)── agent ──HTTPS──▶ server ──▶ dashboard
```

| Package   | What it does |
|-----------|--------------|
| `shared/` | The event type sent from agent to server |
| `server/` | Stores events and category rules in SQLite, serves the API and dashboard |
| `agent/`  | Every 5 min: asks the server where it left off, queries ActivityWatch, uploads |

## Server

GitHub Actions builds the server as a Docker image (amd64 and arm64) and
publishes it as `ghcr.io/couchpotato007/digitalwellbeing`: `:latest` from
`main`, `:1.2.3` and `:1.2` from a `v1.2.3` tag. With [`compose.yaml`](compose.yaml):

```sh
printf 'SECRET_BASE_KEY=%s\nADMIN_TOKEN=%s\n' "$(openssl rand -base64 48)" "$(openssl rand -hex 24)" > .env
docker compose up -d
```

The database lives in the `/data` volume. A bind mount works too, the
container makes it owned by UID 1000, which the server runs as. Put
it behind your reverse proxy for HTTPS, because the token goes over the wire.

Without Docker:

```sh
cd server
CONFIG_DIR=./data SECRET_BASE_KEY=$(openssl rand -base64 48) ADMIN_TOKEN=change-me gleam run
```

The schema is in `server/priv/schema.sql`, the queries in
`server/src/sql/*.sql`. [Parrot](https://github.com/daniellionel01/parrot)
generates typed Gleam functions for them in `server/src/server/sql.gleam`.
After changing either, run `sql` in the dev shell (`nix develop`) to
regenerate it, and commit the result.

Open `http://<server>:8080/` and log in with any user name and `ADMIN_TOKEN` as the
password. Days are counted in the server's local time zone, so set `TZ` if the
server runs elsewhere.

The dashboard looks like ActivityWatch's Activity view, but covers all devices.
At the top you pick a device (or all), a day, a week or 30 days, and step back
and forth or jump to a date. It shows:

- total screen time (time on several devices at once counts once), the change
  against the period before, the daily average, the number of sessions
  (screen time without a break of 5 minutes), the longest one, and when you
  were first and last active (or the busiest day)
- screen time per hour, or per day (a click on a day opens it)
- an activity view of when which category was used, one row per device for a
  day, one row per day for a week or month
- for weeks and months: the average day per hour
- top categories, apps, window titles, browser domains and devices (with
  their operating system, which the agent and the app send along)

Time is split exactly at hour and day boundaries, so a stretch from 23:30 to
00:30 counts half on each day. Below that, the dashboard evaluates the data:

- **Against what is usual**: the period against the median of the same
  weekday in the 8 weeks before (for a week: the 8 weeks before, for 30
  days: the 6 periods before), in total and per category, the most unusual
  first. How unusual is a robust z-score (median absolute deviation, at least
  a tenth of the usual and 10 minutes a day), so one holiday doesn't skew
  it; beyond ±2 is marked. Today is compared with earlier days up to the same
  time. A week or month also shows the 7-day average as a line on the chart.
- **Phone habits**: pickups (per hour, the first of the day), notifications
  per app, how many pickups came within a minute after a notification, the
  app opened first after unlocking, how often the screen was on for less than
  a minute, and media playing.
- **Focus**: stretches of 25+ minutes in one category on one device
  (interruptions under a minute don't end them), app switches, the typical
  session, and for all devices how long the phone was used while a computer
  was in use.
- **Usual week**: a heatmap of screen time per weekday and hour over the last
  4 weeks.

Categories are set up under **Categories** on the server, or under
Settings in the app. Most apps and websites get one on their own, in this
order (the first that applies wins):

1. what you **assigned**: a whole app or website, one tap or click, matched
   in any case (so "Firefox" on the phone and "firefox" on the PC are one)
2. **advanced rules**: regexes on the app (or website) and the window title,
   optionally only on some devices, the deepest category wins
3. **known apps**: a built-in list of apps, websites and Android packages
   (`categories.catalog` in `server/src/categories.gleam`)
4. what **Android** says an app is (game, social, video, maps, …), the app
   sends it along

Browser windows are split where the tab changes and each piece goes by its
website first, then by the browser (so unknown sites are "Browsing", listed
by their name to be moved). What still has no category is listed as
**Unsorted** on top. Every category is rated productive, neutral or
distracting; the dashboard shows the time of each, and Focus only counts
productive stretches. A new server starts with built-in categories; rename,
rate or delete them as you like, "Restore built-in" brings deleted ones back.
Changes re-categorize everything already stored.

API (all calls need `Authorization: Bearer <ADMIN_TOKEN>`):

- `GET  /api/stats?date=2026-10-26&days=7&device=laptop` returns everything the
  dashboard shows for the 7 days up to that date, as JSON (see
  `server/src/stats.gleam`). Without `date` it is today, without `device` all
  devices.
- `GET  /api/categories` returns the categories (with their `rating`, time
  in the last 30 days, the `items` in them with their `source` and their
  advanced `rules`), what is `unsorted` and the devices.
  `POST /api/categories/save` takes `{"name", "rating", "old_name"?}` and
  adds a category, rates it or renames `old_name`; `POST
  /api/categories/delete` takes `{"name"}`; `POST /api/categories/assign`
  takes `{"app", "category"}` (an app or website, `""` back to automatic);
  `POST /api/categories/builtins` adds missing built-in ones. `POST
  /api/rules` takes `{"id"?, "category", "patterns": […], "ignore_case",
  "devices": […]}` and adds or changes an advanced rule, `DELETE
  /api/rules/{id}` deletes one, `POST /api/rules/preview` takes the same
  body and returns what it would match. Invalid input gets a 422 with
  `{"error"}`.
- `GET  /api/insights?date=…&days=…&device=…` returns the evaluation for the
  same selection (see `server/src/insights.gleam`).
- `GET  /api/timeline?date=…&days=…&device=…` returns screen time per app over
  time (15 minutes for a day, hours for a week, days for longer) and the
  sessions, see `server/src/timeline.gleam`.
- `GET  /api/block?device=laptop&category=Work&since_ms=…&until_ms=…` returns
  the `apps` and window `titles` of that category in that time, cut to it
  (what a block of the activity view was made of). Without `device` it is all
  devices.
- `GET  /api/devices/{device}/cursor` returns `{"cursor_ms": <end of newest event>}`
- `POST /api/devices/{device}/events` takes `{"from_ms", "os", "events": [{"kind", "start_ms",
  "duration_ms", "app", "title", "tz_offset_min"}], "app_types": [{"app", "type"}]}` and replaces everything the device did
  from `from_ms` on. `os` (like `"NixOS 25.05 (Warbler)"`) is optional and
  shown next to the device name, `tz_offset_min` (the UTC offset then) is
  optional too, like `app_types` (what phones say their apps are). `kind` is `window` (screen time), `web` (a browser tab),
  or from phones `screen` (screen on), `unlock`, `notification` (both without
  duration) and `audio` (media playing), see `shared/src/shared.gleam`.
  Agents resend the last 10 minutes each time, because
  ActivityWatch still corrects them (e.g. AFK detection).

## Devices

Install ActivityWatch, then run the agent next to it. The agent needs Erlang;
build it once with `cd agent && gleam export erlang-shipment` and copy
`build/erlang-shipment/` to the device.

```sh
SERVER_URL=https://wellbeing.example.org TOKEN=change-me DEVICE=laptop \
  ./erlang-shipment/entrypoint.sh run
```

| Variable            | Default                 | |
|---------------------|-------------------------|-|
| `SERVER_URL`        |                         | required |
| `TOKEN`             |                         | the server's `ADMIN_TOKEN` |
| `DEVICE`            |                         | name shown on the dashboard, unique per device |
| `ACTIVITYWATCH_URL` | `http://localhost:5600` | |
| `INTERVAL_SECONDS`  | `300`                   | `0` syncs once and exits (for cron/systemd timers) |

### Nix / Home Manager

The flake provides the agent as `packages.<system>.agent` and a Home Manager
module that runs it as a systemd user service:

```nix
# flake.nix
inputs.digitalwellbeing.url = "github:<you>/digitalwellbeing";

# home-manager configuration
imports = [ inputs.digitalwellbeing.homeManagerModules.default ];

services.activitywatch.enable = true; # with the window/afk watchers you use
services.digitalwellbeing-agent = {
  enable = true;
  serverUrl = "https://wellbeing.example.org";
  device = "laptop";
  tokenFile = "/run/user/1000/agenix/wellbeing-token"; # contains ADMIN_TOKEN, not copied to the store
};
```

Check it with `journalctl --user -u digitalwellbeing-agent -f`. Without Home
Manager: `SERVER_URL=… TOKEN=… DEVICE=… nix run github:<you>/digitalwellbeing`.

### Other systems

- **Linux / Windows / macOS**: The default ActivityWatch install brings the window
  and AFK watchers. Time away from the computer is cut out. On Wayland, the
  window watcher needs a compositor-specific watcher (e.g. `awatcher`).
  On Linux, run the agent as a systemd user service.
- **Android**: Use the app in `android/` instead of ActivityWatch and the agent,
  see below.
- **iOS**: Not supported. iOS Screen Time has no API that lets apps export usage data.

On the first sync the agent uploads the last 30 days.

### Android

`android/` is a small Kotlin app that does the agent's job on a phone. Every 15
minutes, online or not, it reads Android's usage events into its own database:
which app was in the foreground (cut off when the screen turns off), when the
screen was on and when the phone was unlocked. With notification access it also
records when notifications arrive (only the app, not what they say) and when
an app plays media. It keeps all of it for 400 days, Android itself forgets
usage events after about a week.

Uploading is separate: whenever the server can be reached (e.g. only at home
through a VPN), the app uploads everything that changed since the last upload,
however long ago that was. Settings shows what is stored and what isn't
uploaded yet. Home screen apps (any app that can be the launcher) don't count
as app use, only as the screen being on. The app name is
sent as `app` and the package name (e.g. `org.mozilla.firefox`) as `title`, so
category regexes can match either. Browser tabs are not tracked.

Build it with Android Studio, or with JDK 17 and the Android SDK:

```sh
cd android
gradle wrapper   # once, creates ./gradlew
./gradlew assembleRelease   # app/build/outputs/apk/release/app-release.apk
```

In the app, grant usage access (and optionally notification access), then add the server URL, `ADMIN_TOKEN` and a
device name under **Settings**, where **Test connection** checks them before
saving. The app has three tabs:

- **Overview**: the server's dashboard for all your devices, with its evaluation and the same
  device, day and range selection.
- **Timeline**: screen time per app as stacked areas over the day, week or
  month (drag over it to see a moment), and the sessions with their apps.
- **Settings**: the server, syncing, usage access.

Without a server, Overview shows this phone's last 7 days. Android keeps usage
events only for about a week, so the first collect gets less than 30 days.

## Desktop

`desktop/` is a desktop app in [Odin](https://odin-lang.org) with
[kiln](https://github.com/couchpotato007/kiln) (a submodule in
`desktop/external/kiln`, `git submodule update --init` after cloning). It
shows the same overview as the Android app (range, date and device, summary,
time per hour or day, the activity view, categories, apps, window titles,
domains and devices) and has the server settings with **Test connection**.
Click a day bar or a day row to open that day, a block of the activity view
to see its apps and window titles. It reloads every 5 minutes while the
overview is shown.

```sh
desktop          # in the dev shell: builds and runs desktop/build/wellbeing
```

The settings (server URL, token, colors) are saved in
`~/.config/digitalwellbeing/desktop.json`, readable only by you. kiln builds
its fonts into the binary, so it runs from any directory. To check a layout
without a window, render it at phone, tablet and desktop size from a saved
`/api/stats` answer:

```sh
cd desktop
odin run src -collection:lib=external/kiln -define:KILN_SNAPSHOT=true -define:FIXTURE=stats.json
```
