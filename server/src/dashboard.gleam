import categories.{type Rule}
import db.{type Usage}
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import gleam/uri
import lustre/attribute.{class, href, style}
import lustre/element.{type Element}
import lustre/element/html.{text}
import rules
import stats.{type Report, type Strip}

// --c0 to --c7 are the category colors, in the order of stats.color_slot
const css =
  "
:root { --bg: #f6f6f4; --card: #fff; --fg: #1d1d1b; --muted: #77756f; --bar: #4f6bed; --line: #e4e2dc;
  --c0: #2a78d6; --c1: #eb6834; --c2: #1baf7a; --c3: #eda100; --c4: #e87ba4; --c5: #008300; --c6: #6250d6; --c7: #e34948;
  --gray: #a9a79f; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #161615; --card: #20201e; --fg: #ecebe6; --muted: #9a988f; --bar: #7d93ff; --line: #33322e;
    --c0: #3987e5; --c1: #d95926; --c2: #199e70; --c3: #c98500; --c4: #d55181; --c5: #008300; --c6: #9085e9; --c7: #e66767;
    --gray: #6b6a64; }
}
* { box-sizing: border-box; }
body { margin: 0; padding: 24px 16px; background: var(--bg); color: var(--fg);
  font: 15px/1.45 system-ui, sans-serif; font-variant-numeric: tabular-nums; }
a { color: inherit; }
main { max-width: 960px; margin: 0 auto; display: grid; gap: 16px; }
header { display: flex; justify-content: space-between; align-items: baseline; flex-wrap: wrap; gap: 8px; }
h1 { font-size: 20px; margin: 0; } h2 { font-size: 14px; margin: 0 0 12px; color: var(--muted); font-weight: 500; }
nav a { color: var(--muted); margin-left: 12px; text-decoration: none; } nav a.on { color: var(--fg); font-weight: 600; }
section { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 16px; min-width: 0; }
.big { font-size: 34px; font-weight: 650; } .muted { color: var(--muted); }
.controls { display: flex; flex-wrap: wrap; gap: 8px 16px; align-items: center; justify-content: space-between; }
.pills { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; }
.pills a, .pills form { margin: 0; }
.pills a { padding: 3px 10px; border: 1px solid var(--line); border-radius: 99px; background: var(--card);
  color: var(--muted); text-decoration: none; }
.pills a.on { color: var(--fg); border-color: var(--fg); font-weight: 600; }
.pills a.off { visibility: hidden; }
.tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: 12px; margin-top: 16px; }
.tile { border-top: 1px solid var(--line); padding-top: 8px; }
.tile small { display: block; color: var(--muted); font-size: 12px; } .tile b { font-size: 18px; font-weight: 600; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 380px), 1fr)); gap: 16px; align-items: start; }
.chart { position: relative; display: flex; align-items: flex-end; gap: 2px; height: 160px; margin-top: 28px;
  border-top: 1px dashed var(--line); }
.chart .max { position: absolute; top: -20px; left: 0; font-size: 11px; color: var(--muted); }
.col { flex: 1; display: flex; flex-direction: column; justify-content: flex-end; height: 100%; min-width: 0;
  text-decoration: none; }
.col div { background: var(--bar); border-radius: 4px 4px 0 0; min-height: 2px; }
.col:hover div { opacity: .75; }
.col.today div { background: var(--c1); }
.col span { font-size: 11px; color: var(--muted); text-align: center; overflow: hidden; white-space: nowrap; height: 16px; }
.strip { display: grid; grid-template-columns: 84px minmax(0, 1fr); gap: 8px; align-items: center; margin: 4px 0; }
.strip > a, .strip > span { font-size: 13px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.track { position: relative; height: 18px; background: var(--bg); border-radius: 4px; overflow: hidden; }
.track div { position: absolute; top: 0; bottom: 0; min-width: 2px; }
.ticks { display: flex; justify-content: space-between; font-size: 11px; color: var(--muted); }
.legend { display: flex; flex-wrap: wrap; gap: 4px 14px; font-size: 13px; color: var(--muted); margin-bottom: 10px; }
.sw { display: inline-block; width: 10px; height: 10px; border-radius: 3px; margin-right: 6px; vertical-align: baseline; }
.row { display: grid; grid-template-columns: minmax(0, 1fr) 72px; gap: 2px 12px; padding: 6px 0; border-top: 1px solid var(--line); }
.row:first-of-type { border-top: 0; }
.row b { font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.row .t { text-align: right; } .row small { color: var(--muted); grid-column: 1 / -1; }
.meter { grid-column: 1 / -1; height: 4px; background: var(--line); border-radius: 2px; }
.meter div { height: 100%; background: var(--bar); border-radius: 2px; }
.c0 { background: var(--c0) !important; } .c1 { background: var(--c1) !important; } .c2 { background: var(--c2) !important; }
.c3 { background: var(--c3) !important; } .c4 { background: var(--c4) !important; } .c5 { background: var(--c5) !important; }
.c6 { background: var(--c6) !important; } .c7 { background: var(--c7) !important; } .cx { background: var(--gray) !important; }
@media (max-width: 600px) { .strip { grid-template-columns: 64px minmax(0, 1fr); } }
input:not([type=checkbox]), button { font: inherit; color: inherit; border: 1px solid var(--line);
  border-radius: 6px; padding: 5px 8px; min-width: 0; background: var(--bg); }
button { background: var(--card); cursor: pointer; }
.pills input { padding: 2px 8px; border-radius: 99px; background: var(--card); }
.checks { grid-column: 1 / -1; display: flex; flex-wrap: wrap; gap: 4px 14px; font-size: 13px; color: var(--muted); }
.error { color: #d0453a; margin: 0 0 8px; } p { margin: 0 0 8px; }
.toolbar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
.toolbar input[type=search] { flex: 1 1 220px; }
.toolbar form { margin: 0; }
a.button { display: inline-block; text-decoration: none; border: 1px solid var(--line); border-radius: 6px;
  padding: 5px 10px; background: var(--card); }
.primary { background: var(--bar) !important; color: #fff !important; border-color: var(--bar) !important; }
.danger { color: #d0453a; }
.group { padding: 8px 16px; }
.group-head { display: flex; align-items: center; gap: 8px; padding: 8px 0; }
.group-head .muted { margin-left: auto; font-size: 13px; }
.cat { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 4px 12px; padding: 10px 8px;
  border-top: 1px solid var(--line); text-decoration: none; border-radius: 6px; }
.cat:hover { background: var(--bg); }
.cat-name { display: flex; gap: 8px; align-items: baseline; min-width: 0; }
.cat .t { color: var(--muted); }
.chips { grid-column: 1 / -1; display: flex; flex-wrap: wrap; gap: 4px; }
.chip { font: 12px/1.6 ui-monospace, monospace; padding: 0 7px; border-radius: 99px; background: var(--bg);
  border: 1px solid var(--line); color: var(--muted); max-width: 100%; overflow: hidden; text-overflow: ellipsis;
  white-space: nowrap; }
.chip.more { font-family: inherit; }
.badge { font-size: 12px; color: var(--muted); border: 1px solid var(--line); border-radius: 4px; padding: 0 5px; }
.assign { grid-column: 1 / -1; display: flex; gap: 6px; margin: 2px 0 0; }
.assign select { flex: 1; min-width: 0; }
select { font: inherit; color: inherit; border: 1px solid var(--line); border-radius: 6px; padding: 4px 6px;
  background: var(--bg); }
.editor section { display: grid; gap: 6px; }
.editor label { font-size: 13px; font-weight: 600; margin-top: 10px; }
.editor .checks label { font-weight: 400; margin: 0; }
.editor textarea { font: 13px/1.6 ui-monospace, monospace; color: inherit; background: var(--bg);
  border: 1px solid var(--line); border-radius: 6px; padding: 8px; resize: vertical; }
.help { color: var(--muted); font-size: 12px; }
.actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 14px; }
.actions .danger { margin-left: auto; }
[hidden] { display: none !important; }
"

/// Link to the dashboard with another date, number of days or device.
fn url(date: String, days: Int, device: String) -> String {
  "/?date="
  <> date
  <> "&days="
  <> int.to_string(days)
  <> "&device="
  <> uri.percent_encode(device)
}

fn pill(target: String, label: String, on: Bool) -> Element(msg) {
  html.a([href(target), class(on_class(on))], [text(label)])
}

fn on_class(on: Bool) -> String {
  case on {
    True -> "on"
    False -> ""
  }
}

pub fn page(report: Report) -> String {
  let filter = report.filter
  let order = report.category_order
  let device_name = case
    filter.device,
    dict.get(report.device_os, filter.device)
  {
    "", _ -> "all devices"
    device, Ok(os) -> device <> " (" <> os <> ")"
    device, Error(Nil) -> device
  }
  let period = case filter.days, report.days {
    1, [day] -> stats.weekday(day.weekday) <> " " <> filter.date
    _, _ -> filter.first_date <> " – " <> filter.date
  }
  let previous_name = case filter.days {
    1 -> "the day before"
    7 -> "the week before"
    days -> "the " <> int.to_string(days) <> " days before"
  }
  let category_total =
    list.fold(report.categories, 0, fn(sum, item) { sum + item.ms })
  document("Screen time", [
    html.header([], [
      html.h1([], [text("Screen time")]),
      html.nav([], [html.a([href("/categories")], [text("Categories")])]),
    ]),
    html.div([class("controls")], [
      html.nav(
        [class("pills")],
        list.map([#(1, "Day"), #(7, "Week"), #(30, "30 days")], fn(range) {
          pill(
            url(filter.date, range.0, filter.device),
            range.1,
            range.0 == filter.days,
          )
        }),
      ),
      html.nav([class("pills")], [
        pill(url(filter.previous_date, filter.days, filter.device), "‹", False),
        date_picker(report),
        html.a(
          [
            href(url(filter.next_date, filter.days, filter.device)),
            // nothing to see in the future
            class(case string.compare(filter.date, filter.today) != order.Lt {
              True -> "off"
              False -> ""
            }),
          ],
          [text("›")],
        ),
        pill(
          url(filter.today, filter.days, filter.device),
          "Today",
          filter.date == filter.today,
        ),
      ]),
    ]),
    html.nav([class("pills")], [
      pill(
        url(filter.date, filter.days, ""),
        "All devices",
        filter.device == "",
      ),
      ..list.map(report.device_names, fn(device) {
        let label = case dict.get(report.device_os, device) {
          Ok(os) -> device <> " · " <> os_short(os)
          Error(Nil) -> device
        }
        pill(
          url(filter.date, filter.days, device),
          label,
          device == filter.device,
        )
      })
    ]),
    html.section([], [
      html.div([class("big")], [text(duration(report.total_ms))]),
      html.div([class("muted")], [text(period <> " · " <> device_name)]),
      html.div([class("tiles")], {
        let change = case stats.change(report.total_ms, report.previous_ms) {
          Ok(p) if p > 0 -> "↑ " <> int.to_string(p) <> "%"
          Ok(p) if p < 0 -> "↓ " <> int.to_string(-p) <> "%"
          Ok(_) -> "±0%"
          Error(Nil) -> "–"
        }
        let common = [
          tile("vs. " <> previous_name, change, duration(report.previous_ms)),
          tile("Sessions", int.to_string(report.sessions), "breaks of 5+ min"),
          tile("Longest session", duration(report.longest_session_ms), ""),
        ]
        case filter.days {
          1 ->
            list.append(common, [
              tile("First active", or_dash(report.first_active), ""),
              tile("Last active", or_dash(report.last_active), ""),
            ])
          days -> {
            let busiest =
              list.fold(report.timeline, db.Usage("", "", 0), fn(max, day) {
                case day.ms > max.ms {
                  True -> day
                  False -> max
                }
              })
            [
              tile("Daily average", duration(report.total_ms / days), ""),
              ..list.append(common, [
                tile(
                  "Busiest day",
                  case busiest.ms {
                    0 -> "–"
                    _ ->
                      busiest.detail <> " " <> string.slice(busiest.name, 5, 5)
                  },
                  case busiest.ms {
                    0 -> ""
                    ms -> duration(ms)
                  },
                ),
              ])
            ]
          }
        }
      }),
      chart(report, report.timeline, True),
    ]),
    case report.strips {
      [] -> element.none()
      strips -> activity(order, strips, filter.days)
    },
    case filter.days {
      1 -> element.none()
      days ->
        html.section([], [
          html.h2([], [text("By hour of day · average per day")]),
          chart(
            report,
            list.map(report.hours, fn(hour) {
              db.Usage(..hour, ms: hour.ms / days)
            }),
            False,
          ),
        ])
    },
    html.div([class("grid")], [
      usage_list_with(
        "Categories",
        report.categories,
        fn(item) { color_class(order, item.name) },
        fn(item) { percent(item.ms, int.max(category_total, 1)) },
      ),
      usage_list("Apps", report.apps),
      usage_list("Window titles", report.titles),
      usage_list("Browser domains", report.domains),
      case filter.device {
        "" -> usage_list("Devices · last active", report.devices)
        _ -> element.none()
      },
    ]),
    case filter.device {
      "" -> element.none()
      device -> delete_device_form(device)
    },
  ])
}

/// "NixOS 25.05 (Warbler)" -> "NixOS", "Android 15" -> "Android"
fn os_short(os: String) -> String {
  case string.split_once(os, " ") {
    Ok(#(name, _)) -> name
    Error(Nil) -> os
  }
}

fn or_dash(value: String) -> String {
  case value {
    "" -> "–"
    _ -> value
  }
}

fn tile(label: String, value: String, note: String) -> Element(msg) {
  html.div([class("tile")], [
    html.small([], [text(label)]),
    html.b([], [text(value)]),
    case note {
      "" -> element.none()
      _ -> html.small([], [text(note)])
    },
  ])
}

/// Changing the date submits the form, without JavaScript Enter does.
fn date_picker(report: Report) -> Element(msg) {
  let filter = report.filter
  html.form([attribute.method("get"), attribute.action("/")], [
    html.input([
      attribute.type_("hidden"),
      attribute.name("days"),
      attribute.value(int.to_string(filter.days)),
    ]),
    html.input([
      attribute.type_("hidden"),
      attribute.name("device"),
      attribute.value(filter.device),
    ]),
    html.input([
      attribute.type_("date"),
      attribute.name("date"),
      attribute.value(filter.date),
      attribute.max(filter.today),
      attribute.attribute("aria-label", "Last day shown"),
      attribute.attribute("onchange", "this.form.submit()"),
    ]),
  ])
}

fn color_class(order: List(String), category: String) -> String {
  case stats.color_slot(order, category) {
    Ok(slot) -> "c" <> int.to_string(slot)
    Error(Nil) -> "cx"
  }
}

/// When which category was used, one row per device or day.
fn activity(
  order: List(String),
  strips: List(Strip),
  days: Int,
) -> Element(msg) {
  let shown =
    list.flat_map(strips, fn(strip) {
      list.map(strip.segments, fn(segment) { stats.top_level(segment.category) })
    })
    |> list.unique
  // the legend in the colors' order, gray ones last
  let legend =
    list.filter(order, list.contains(shown, _))
    |> list.append(list.filter(shown, fn(name) { !list.contains(order, name) }))
  html.section([], [
    html.h2([], [
      text(case days {
        1 -> "Activity per device"
        _ -> "Activity per day"
      }),
    ]),
    html.div(
      [class("legend")],
      list.map(legend, fn(name) {
        html.span([], [
          html.span([class("sw " <> color_class(order, name))], []),
          text(name),
        ])
      }),
    ),
    ..list.map(strips, fn(strip) {
      let length = int.max(strip.end_ms - strip.start_ms, 1)
      html.div([class("strip")], [
        case strip.date {
          "" -> html.span([attribute.title(strip.label)], [text(strip.label)])
          date ->
            html.a([href(url(date, 1, "")), style("text-decoration", "none")], [
              text(strip.label),
            ])
        },
        html.div(
          [class("track")],
          list.map(strip.segments, fn(segment) {
            let from = segment.start_ms - strip.start_ms
            let to = segment.end_ms - strip.start_ms
            html.div(
              [
                class(color_class(order, segment.category)),
                style("left", percent(from, length)),
                style("width", percent(to - from, length)),
                attribute.title(
                  // rows of a day have all devices
                  case strip.date {
                    "" -> ""
                    _ -> segment.device <> " · "
                  }
                  <> segment.category
                  <> " · "
                  <> clock(from)
                  <> "–"
                  <> clock(to)
                  <> " ("
                  <> duration(to - from)
                  <> ")",
                ),
              ],
              [],
            )
          }),
        ),
      ])
    })
    |> list.append([
      html.div([class("strip")], [
        html.span([], []),
        html.div(
          [class("ticks")],
          list.map(["0", "3", "6", "9", "12", "15", "18", "21", "24"], fn(hour) {
            html.span([], [text(hour)])
          }),
        ),
      ]),
    ])
  ])
}

/// Time of day of `ms` after midnight, "07:05".
fn clock(ms: Int) -> String {
  let minutes = ms / 60_000
  let pad = fn(n) { int.to_string(n) |> string.pad_start(2, "0") }
  pad(minutes / 60) <> ":" <> pad(minutes % 60)
}

/// Deletes all data of `device`, after the browser asks to confirm.
fn delete_device_form(device: String) -> Element(msg) {
  html.form(
    [
      attribute.method("post"),
      attribute.action("/devices/" <> uri.percent_encode(device) <> "/delete"),
      attribute.attribute(
        "onsubmit",
        "return confirm('Delete all data of this device? It cannot be undone.')",
      ),
    ],
    [html.button([], [text("Delete " <> device <> " and its data")])],
  )
}

fn document(title: String, children: List(Element(msg))) -> String {
  html.html([attribute.lang("en")], [
    html.head([], [
      html.meta([attribute.charset("utf-8")]),
      html.meta([
        attribute.name("viewport"),
        attribute.content("width=device-width, initial-scale=1"),
      ]),
      html.title([], title),
      html.style([], css),
    ]),
    html.body([], [html.main([], children)]),
  ])
  |> element.to_document_string
}

/// All categories as a tree, grouped by their top level, each with its
/// patterns and time, and below what has no category yet.
pub fn categories_page(overview: rules.Overview, error: String) -> String {
  let order = overview.category_order
  let groups =
    list.group(overview.rules, fn(entry) { stats.top_level({ entry.0 }.name) })
  // groups in the colors' order, the rest after it by name
  let group_names =
    list.filter(order, dict.has_key(groups, _))
    |> list.append(
      dict.keys(groups)
      |> list.filter(fn(name) { !list.contains(order, name) })
      |> list.sort(string.compare),
    )
  let names =
    list.map(overview.rules, fn(entry) { { entry.0 }.name })
    |> list.unique
    |> list.sort(string.compare)
  let missing_defaults =
    list.any(categories.defaults, fn(default) {
      !list.contains(names, default.name)
    })
  document("Categories", [
    html.header([], [
      html.h1([], [text("Categories")]),
      html.nav([], [html.a([href("/")], [text("Screen time")])]),
    ]),
    html.section([], [
      html.p([class("muted")], [
        text(
          "Every app and window title gets the deepest category with a matching
          pattern (for browser tabs: the domain and tab title). A rule without
          devices applies to all of them.",
        ),
      ]),
      case error {
        "" -> element.none()
        error -> html.p([class("error")], [text(error)])
      },
      html.div([class("toolbar")], [
        html.input([
          attribute.type_("search"),
          attribute.id("q"),
          attribute.placeholder("Search categories and patterns"),
          attribute.attribute("aria-label", "Search"),
        ]),
        html.a([class("button primary"), href("/categories/new")], [
          text("+ New category"),
        ]),
        case missing_defaults {
          True ->
            html.form(
              [
                attribute.method("post"),
                attribute.action("/categories/defaults"),
              ],
              [html.button([], [text("Add missing defaults")])],
            )
          False -> element.none()
        },
      ]),
    ]),
    ..list.map(group_names, fn(group) {
      let entries =
        dict.get(groups, group)
        |> result.unwrap([])
        |> list.sort(fn(a, b) { string.compare({ a.0 }.name, { b.0 }.name) })
      let total = list.fold(entries, 0, fn(sum, entry) { sum + entry.1 })
      html.section([class("group")], [
        html.div([class("group-head")], [
          html.span([class("sw " <> color_class(order, group))], []),
          html.b([], [text(group)]),
          html.span([class("muted")], [
            text(
              duration(total) <> " · " <> int.to_string(rules.days) <> " days",
            ),
          ]),
        ]),
        ..list.map(entries, fn(entry) { category_row(entry.0, entry.1) })
      ])
    })
    |> list.append([
      html.div([class("grid")], [
        uncategorized_list(
          "Without a category · apps and domains",
          overview.uncategorized_apps,
          names,
          overview.rules,
        ),
        uncategorized_list(
          "Without a category · window titles",
          overview.uncategorized_titles,
          names,
          overview.rules,
        ),
      ]),
      html.script(
        [],
        "
const q = document.getElementById('q');
q.addEventListener('input', () => {
  const term = q.value.toLowerCase();
  document.querySelectorAll('[data-q]').forEach(el => el.hidden = term && !el.dataset.q.includes(term));
  document.querySelectorAll('.group').forEach(g => g.hidden = !g.querySelector('[data-q]:not([hidden])'));
});",
      ),
    ])
  ])
}

/// A rule in the list: its name indented by depth, a few patterns, devices.
fn category_row(rule: Rule, ms: Int) -> Element(msg) {
  let parts = string.split(rule.name, " > ")
  let depth = list.length(parts) - 1
  let patterns = categories.split_patterns(rule.regex)
  let shown = list.take(patterns, 6)
  let more = list.length(patterns) - list.length(shown)
  html.a(
    [
      class("cat"),
      href("/categories/" <> int.to_string(rule.id)),
      attribute.data(
        "q",
        string.lowercase(rule.name <> " " <> string.join(patterns, " ")),
      ),
      style("padding-left", int.to_string(depth * 20) <> "px"),
    ],
    [
      html.div([class("cat-name")], [
        html.b([], [text(list.last(parts) |> result.unwrap(rule.name))]),
        case rule.devices {
          [] -> element.none()
          devices ->
            html.span([class("badge")], [
              text("only " <> string.join(devices, ", ")),
            ])
        },
      ]),
      html.span([class("t")], [text(duration(ms))]),
      html.div(
        [class("chips")],
        list.map(shown, fn(pattern) {
          html.span([class("chip"), attribute.title(pattern)], [
            text(case string.length(pattern) > 28 {
              True -> string.slice(pattern, 0, 26) <> "…"
              False -> pattern
            }),
          ])
        })
          |> list.append(case more {
            0 -> []
            n -> [
              html.span([class("chip more")], [text("+" <> int.to_string(n))]),
            ]
          }),
      ),
    ],
  )
}

/// What has no category, each with a form to add it to one as a pattern.
fn uncategorized_list(
  title: String,
  items: List(Usage),
  names: List(String),
  rules: List(#(Rule, Int)),
) -> Element(msg) {
  html.section([], [
    html.h2([], [text(title)]),
    case items {
      [] -> html.p([class("muted")], [text("Everything has a category.")])
      _ -> element.none()
    },
    ..list.map(items, fn(item) {
      html.div([class("row")], [
        html.b([attribute.title(item.name)], [text(item.name)]),
        html.span([class("t")], [text(duration(item.ms))]),
        html.small([], [text(item.detail)]),
        html.form(
          [
            class("assign"),
            attribute.method("post"),
            attribute.action("/categories/assign"),
          ],
          [
            html.input([
              attribute.type_("hidden"),
              attribute.name("text"),
              attribute.value(item.name),
            ]),
            html.select(
              [
                attribute.name("id"),
                attribute.attribute("aria-label", "Category"),
              ],
              list.map(names, fn(name) {
                // the first rule of a name gets the pattern
                let id =
                  list.find(rules, fn(entry) { { entry.0 }.name == name })
                  |> result.map(fn(entry) { { entry.0 }.id })
                  |> result.unwrap(0)
                html.option([attribute.value(int.to_string(id))], name)
              }),
            ),
            html.button([], [text("Add")]),
            html.a(
              [
                class("button"),
                href(
                  "/categories/new?pattern="
                  <> uri.percent_encode(categories.escape(item.name)),
                ),
              ],
              [text("New…")],
            ),
          ],
        ),
      ])
    })
  ])
}

/// One rule to edit, or a new one, with what it matches in the last days.
pub fn category_editor(
  rule: Rule,
  overview: rules.Overview,
  error: String,
  preview: Option(rules.Preview),
) -> String {
  let is_new = rule.id == 0
  let patterns = categories.split_patterns(rule.regex)
  // every existing name, and each as a parent for a new subcategory
  let names =
    list.map(overview.rules, fn(entry) { { entry.0 }.name })
    |> list.unique
    |> list.sort(string.compare)
  document(
    case is_new {
      True -> "New category"
      False -> rule.name
    },
    [
      html.header([], [
        html.h1([], [
          text(case is_new {
            True -> "New category"
            False -> rule.name
          }),
        ]),
        html.nav([], [html.a([href("/categories")], [text("‹ Categories")])]),
      ]),
      html.form(
        [
          class("editor"),
          attribute.method("post"),
          attribute.action("/categories"),
        ],
        [
          html.section([], [
            case is_new {
              True -> element.none()
              False ->
                html.input([
                  attribute.type_("hidden"),
                  attribute.name("id"),
                  attribute.value(int.to_string(rule.id)),
                ])
            },
            case error {
              "" -> element.none()
              error -> html.p([class("error")], [text(error)])
            },
            html.label([attribute.for("name")], [text("Name")]),
            html.input([
              attribute.id("name"),
              attribute.name("name"),
              attribute.value(rule.name),
              attribute.placeholder("Work > Programming"),
              attribute.list("names"),
              attribute.required(True),
            ]),
            html.datalist(
              [attribute.id("names")],
              list.flat_map(names, fn(name) {
                [
                  html.option([attribute.value(name)], ""),
                  html.option([attribute.value(name <> " > ")], ""),
                ]
              }),
            ),
            html.small([class("help")], [
              text(
                "Use > for subcategories. The deepest matching category wins.",
              ),
            ]),
            html.label([attribute.for("patterns")], [text("Patterns")]),
            html.textarea(
              [
                attribute.id("patterns"),
                attribute.name("patterns"),
                attribute.rows(int.clamp(list.length(patterns) + 2, 6, 24)),
                attribute.placeholder("code\nvim\ngithub\\.com"),
                attribute.attribute("spellcheck", "false"),
              ],
              string.join(patterns, "\n"),
            ),
            html.small([class("help")], [
              text(
                "One per line, each matched against the app and the window
                title. Plain words work, they are regular expressions: \\b marks
                a word boundary, ^x\\.com$ only matches exactly x.com.",
              ),
            ]),
            html.div([class("checks")], [
              checkbox("ignore_case", "on", rule.ignore_case, "ignore case"),
            ]),
            html.label([], [text("Only on these devices (none: all)")]),
            html.div(
              [class("checks")],
              list.map(overview.devices, fn(device) {
                checkbox(
                  "devices",
                  device,
                  list.contains(rule.devices, device),
                  device,
                )
              }),
            ),
            html.div([class("actions")], [
              html.button(
                [
                  class("primary"),
                  attribute.name("action"),
                  attribute.value("save"),
                ],
                [text("Save")],
              ),
              html.button(
                [attribute.name("action"), attribute.value("preview")],
                [
                  text("Preview matches"),
                ],
              ),
              case is_new {
                True -> element.none()
                False ->
                  html.button(
                    [
                      class("danger"),
                      attribute.formaction(
                        "/categories/" <> int.to_string(rule.id) <> "/delete",
                      ),
                      attribute.attribute(
                        "onclick",
                        "return confirm('Delete this category?')",
                      ),
                    ],
                    [text("Delete")],
                  )
              },
            ]),
          ]),
        ],
      ),
      case preview {
        None -> element.none()
        Some(preview) ->
          html.div([], [
            html.h2([], [
              text(
                "Matches in the last "
                <> int.to_string(rules.days)
                <> " days · "
                <> duration(preview.screen_ms)
                <> " screen time",
              ),
            ]),
            html.div([class("grid")], [
              usage_list("Apps and domains", preview.apps),
              usage_list("Window titles", preview.titles),
            ]),
          ])
      },
    ],
  )
}

fn checkbox(
  name: String,
  value: String,
  checked: Bool,
  label: String,
) -> Element(msg) {
  html.label([], [
    html.input([
      attribute.type_("checkbox"),
      attribute.name(name),
      attribute.value(value),
      attribute.checked(checked),
    ]),
    text(" " <> label),
  ])
}

/// Bars per hour or day. Days link to themselves when `links` is set.
fn chart(report: Report, buckets: List(Usage), links: Bool) -> Element(msg) {
  let filter = report.filter
  let max = list.fold(buckets, 1, fn(max, bucket) { int.max(max, bucket.ms) })
  let count = list.length(buckets)
  // at most about 12 labels
  let every = int.max(1, { count + 11 } / 12)
  html.div([class("chart")], [
    html.span([class("max")], [text(duration(max))]),
    ..list.index_map(buckets, fn(bucket, index) {
      // an hour "07" or a day "2026-10-26"
      let is_day = string.length(bucket.name) == 10
      let label = case index % every, is_day {
        0, False -> bucket.name
        0, True if count <= 7 -> bucket.detail
        0, True -> string.slice(bucket.name, 8, 2)
        _, _ -> ""
      }
      let attributes = [
        class(case is_day && bucket.name == filter.today {
          True -> "col today"
          False -> "col"
        }),
        attribute.title(
          case is_day {
            True -> bucket.detail <> " " <> bucket.name
            False -> bucket.name <> ":00"
          }
          <> ": "
          <> duration(bucket.ms),
        ),
      ]
      let children = [
        html.div([style("height", percent(bucket.ms, max))], []),
        html.span([], [text(label)]),
      ]
      case links && is_day {
        True ->
          html.a(
            [href(url(bucket.name, 1, filter.device)), ..attributes],
            children,
          )
        False -> html.div(attributes, children)
      }
    })
  ])
}

fn usage_list(title: String, items: List(Usage)) -> Element(msg) {
  usage_list_with(title, items, fn(_) { "" }, fn(item) { item.detail })
}

/// `color` gives the class of an item's meter, `detail` the line below it.
fn usage_list_with(
  title: String,
  items: List(Usage),
  color: fn(Usage) -> String,
  detail: fn(Usage) -> String,
) -> Element(msg) {
  let max = list.fold(items, 1, fn(max, item) { int.max(max, item.ms) })
  html.section([], [
    html.h2([], [text(title)]),
    ..list.map(items, fn(item) {
      html.div([class("row")], [
        html.b([attribute.title(item.name)], [text(item.name)]),
        html.span([class("t")], [text(duration(item.ms))]),
        html.small([], [text(detail(item))]),
        html.div([class("meter")], [
          html.div(
            [class(color(item)), style("width", percent(item.ms, max))],
            [],
          ),
        ]),
      ])
    })
  ])
}

fn duration(ms: Int) -> String {
  let minutes = ms / 60_000
  case minutes / 60, minutes % 60 {
    0, 0 -> int.to_string(ms / 1000) <> "s"
    0, m -> int.to_string(m) <> "m"
    h, m -> int.to_string(h) <> "h " <> int.to_string(m) <> "m"
  }
}

fn percent(part: Int, whole: Int) -> String {
  float.to_string(int.to_float(part * 1000 / whole) /. 10.0) <> "%"
}
