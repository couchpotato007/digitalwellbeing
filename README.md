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
| `server/` | Stores events in SQLite (one `events` table), serves the API and dashboard |
| `agent/`  | Every 5 min: asks the server where it left off, queries ActivityWatch, uploads |

## Server

```sh
cd server
CONFIG_DIR=./data SECRET_BASE_KEY=$(openssl rand -base64 48) ADMIN_TOKEN=change-me gleam run
```

Open `http://<server>:8080/` and log in with any user name and `ADMIN_TOKEN` as the
password. Days are counted in the server's local time zone, so set `TZ` if the
server runs elsewhere.

The dashboard looks like ActivityWatch's Activity view, but covers all devices:
total screen time (time on several devices at once counts once), a per-hour or
per-day timeline, top categories, apps, window titles and browser domains.
Filter by device at the top. Categories are the ones you set up in
ActivityWatch (Settings → Categorization). Each agent sends them along with
its events.

API (all calls need `Authorization: Bearer <ADMIN_TOKEN>`):

- `GET  /api/devices/{device}/cursor` returns `{"cursor_ms": <end of newest event>}`
- `POST /api/devices/{device}/events` takes `{"from_ms", "events": [{"kind", "start_ms",
  "duration_ms", "app", "title", "category"}]}` and replaces everything the device did
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
- **Android**: Install ActivityWatch from F-Droid or Play and grant it usage
  access. Run the agent in Termux (`pkg install erlang`), and use Termux:Boot to
  start it on boot.
- **iOS**: Not supported. iOS Screen Time has no API that lets apps export usage data.

On the first sync the agent uploads the last 30 days.
