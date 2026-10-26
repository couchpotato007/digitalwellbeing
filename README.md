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

The dashboard looks like ActivityWatch's Activity view, but covers all devices:
total screen time (time on several devices at once counts once), a per-hour or
per-day timeline, top categories, apps, window titles and browser domains.
Filter by device at the top.

Categories are set up on the server under **Categories**. A category is a
regex matched against the app and window title (for browser tabs: the domain
and tab title), and every event gets the deepest category that matches, so
`Work > Programming` wins over `Work`. A rule can be limited to some devices.
Changing a rule re-categorizes everything already stored. The page also lists
what took the most time without a category, to help write the patterns.
Categories set up in ActivityWatch itself are not used. A new server starts
with default categories for common apps and sites (programming, office, chat,
email, video, music, social media, games, news, shopping). Change or delete
them as you like; "Add missing default categories" brings back deleted ones.

API (all calls need `Authorization: Bearer <ADMIN_TOKEN>`):

- `GET  /api/devices/{device}/cursor` returns `{"cursor_ms": <end of newest event>}`
- `POST /api/devices/{device}/events` takes `{"from_ms", "events": [{"kind", "start_ms",
  "duration_ms", "app", "title"}]}` and replaces everything the device did
  from `from_ms` on. Agents resend the last 10 minutes each time, because
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

`android/` is a small Kotlin app that does the agent's job on a phone. It reads
Android's usage events (which app was in the foreground, cut off when the screen
turns off) and uploads them every 15 minutes with the same API. The app name is
sent as `app` and the package name (e.g. `org.mozilla.firefox`) as `title`, so
category regexes can match either. Browser tabs are not tracked.

Build it with Android Studio, or with JDK 17 and the Android SDK:

```sh
cd android
gradle wrapper   # once, creates ./gradlew
./gradlew assembleRelease   # app/build/outputs/apk/release/app-release.apk
```

In the app, grant usage access, then add the server URL, `ADMIN_TOKEN` and a
device name. Android keeps usage events only for about a week, so the first sync
uploads less than 30 days.
