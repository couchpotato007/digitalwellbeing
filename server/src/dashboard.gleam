import categories.{type Rule}
import db.{type Usage}
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import gleam/uri
import insights.{type Count, type Insights}
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
.col { position: relative; }
.col i { position: absolute; left: 8%; right: 8%; height: 2px; background: var(--fg); opacity: .55; border-radius: 1px; }
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
.up { color: #d0453a; } .down { color: #1b9a6a; }
.cat-box { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 0 16px; }
.cat-box[open] { padding-bottom: 12px; }
.cat-box summary { display: flex; gap: 8px; align-items: center; padding: 12px 0; cursor: pointer; list-style: none; }
.cat-box summary::-webkit-details-marker { display: none; }
.cat-box .grow { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 13px; }
.cat-box > form.toolbar { margin: 4px 0 8px; }
.item { display: grid; grid-template-columns: minmax(0, 1fr) 64px minmax(0, 170px) auto; gap: 6px 10px;
  align-items: center; padding: 6px 0; border-top: 1px solid var(--line); margin: 0; }
.item-name { min-width: 0; } .item-name b { display: block; font-weight: 500; overflow: hidden;
  text-overflow: ellipsis; white-space: nowrap; } .item-name small { color: var(--muted); font-size: 12px; }
.item .t { text-align: right; }
@media (max-width: 600px) { .item { grid-template-columns: minmax(0, 1fr) 56px; } .item select { grid-column: 1 / -1; } }
.rules { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; margin-top: 10px; }
.ratings { margin-top: 16px; }
.rating-bar { display: flex; height: 10px; border-radius: 5px; overflow: hidden; background: var(--line);
  margin-bottom: 6px; }
.productive { background: #1baf7a; } .neutral { background: var(--gray); } .distracting { background: #e34948; }
.badge.productive { color: #1b9a6a; border-color: currentColor; background: none; }
.badge.neutral { background: none; }
.badge.distracting { color: #d0453a; border-color: currentColor; background: none; }
.cmp { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 2px 12px; padding: 6px 0;
  border-top: 1px solid var(--line); }
.cmp:first-of-type { border-top: 0; }
.cmp small { grid-column: 1 / -1; color: var(--muted); }
.vs { grid-column: 1 / -1; position: relative; height: 6px; background: var(--line); border-radius: 3px; }
.vs div { height: 100%; border-radius: 3px; }
.vs i { position: absolute; top: -3px; bottom: -3px; width: 2px; background: var(--fg); }
.heat { display: grid; grid-template-columns: 34px repeat(24, minmax(0, 1fr)); gap: 2px; font-size: 11px;
  color: var(--muted); }
.heat div { aspect-ratio: 1; border-radius: 2px; background: var(--bg); }
.note { font-size: 13px; color: var(--muted); margin-top: 10px; }
section section { border: 0; padding: 0; background: none; }
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

pub fn page(report: Report, insights: Insights) -> String {
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
      rating_bar(insights),
      trend_chart(report, insights.trend),
      usual_note(insights, report.filter.days),
    ]),
    comparisons(report, insights),
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
    phone(report, insights),
    focus(report, insights),
    usual_week(insights.week_hours),
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

/// The categories with their rating and what is in them, and above them
/// what has no category yet, to sort with a click. `open` is the category
/// shown open.
pub fn categories_page(
  overview: rules.Overview,
  open: String,
  error: String,
) -> String {
  let order = overview.category_order
  let names = list.map(overview.categories, fn(entry) { entry.category.name })
  document("Categories", [
    html.header([], [
      html.h1([], [text("Categories")]),
      html.nav([], [html.a([href("/")], [text("‹ Screen time")])]),
    ]),
    case error {
      "" -> element.none()
      error -> html.p([class("error")], [text(error)])
    },
    html.p([class("muted")], [
      text("Most apps and websites get a category on their own: known ones, what
        Android says an app is, and browser windows by the website shown. Move
        anything to another category to change it, times are of the last " <> int.to_string(
        rules.days,
      ) <> " days."),
    ]),
    case overview.unsorted {
      [] -> element.none()
      items ->
        html.section([], [
          html.h2([], [
            text("Unsorted · " <> duration(overview.unsorted_ms)),
          ]),
          ..list.map(items, fn(item) { item_row(item, names, "", []) })
        ])
    },
    ..list.append(
      list.map(overview.categories, fn(entry) {
        category_section(entry, order, names, entry.category.name == open)
      }),
      [
        html.section([], [
          html.h2([], [text("New category")]),
          html.form(
            [
              class("toolbar"),
              attribute.method("post"),
              attribute.action("/categories/save"),
            ],
            [
              html.input([
                attribute.name("name"),
                attribute.placeholder("Work > Studying"),
                attribute.required(True),
              ]),
              rating_select(categories.Neutral),
              html.button([class("primary")], [text("Add")]),
            ],
          ),
          html.small([class("help")], [
            text(
              "Use > for subcategories, they share the color of their group.",
            ),
          ]),
        ]),
        html.form(
          [attribute.method("post"), attribute.action("/categories/builtins")],
          [
            html.button([], [text("Add missing built-in categories")]),
          ],
        ),
      ],
    )
  ])
}

fn rating_select(rating: categories.Rating) -> Element(msg) {
  html.select(
    [attribute.name("rating")],
    list.map(
      [categories.Productive, categories.Neutral, categories.Distracting],
      fn(option) {
        let value = categories.rating_to_string(option)
        html.option(
          [attribute.value(value), attribute.selected(option == rating)],
          value,
        )
      },
    ),
  )
}

fn rating_badge(rating: categories.Rating) -> Element(msg) {
  let value = categories.rating_to_string(rating)
  html.span([class("badge " <> value)], [text(value)])
}

fn source_name(source: categories.Source) -> String {
  case source {
    categories.Assigned -> "assigned"
    categories.ByRule -> "rule"
    categories.Known -> "known app"
    categories.AndroidType -> "app type"
    categories.InBrowser -> "in a browser"
    categories.NoSource -> ""
  }
}

/// A category, open to change its name and rating, move what is in it, and
/// its advanced rules.
fn category_section(
  entry: rules.Entry,
  order: List(String),
  names: List(String),
  open: Bool,
) -> Element(msg) {
  let name = entry.category.name
  html.details([class("cat-box"), attribute.open(open)], [
    html.summary([], [
      html.span([class("sw " <> color_class(order, name))], []),
      html.b([], [text(name)]),
      rating_badge(entry.category.rating),
      html.span([class("muted grow")], [
        text(
          list.take(entry.items, 3)
          |> list.map(fn(item) { item.name })
          |> string.join(", "),
        ),
      ]),
      html.span([class("t")], [text(duration(entry.ms))]),
    ]),
    html.form(
      [
        class("toolbar"),
        attribute.method("post"),
        attribute.action("/categories/save"),
      ],
      [
        hidden("old_name", name),
        hidden("open", name),
        html.input([attribute.name("name"), attribute.value(name)]),
        rating_select(entry.category.rating),
        html.button([], [text("Save")]),
        html.button(
          [
            class("danger"),
            attribute.formaction("/categories/delete"),
            attribute.attribute(
              "onclick",
              "return confirm('Delete this category? Its apps go back to automatic.')",
            ),
          ],
          [text("Delete")],
        ),
      ],
    ),
    case entry.items {
      [] -> html.p([class("muted")], [text("Nothing in the last 30 days.")])
      items ->
        html.div(
          [],
          list.map(list.take(items, 30), fn(item) {
            item_row(item, names, name, case item.source {
              categories.Assigned -> [
                html.button(
                  [
                    attribute.name("category"),
                    attribute.value(""),
                    attribute.title("Let it get its category on its own again"),
                  ],
                  [text("Automatic")],
                ),
              ]
              _ -> []
            })
          }),
        )
    },
    html.div([class("rules")], [
      html.small([class("help")], [text("Advanced rules")]),
      ..list.append(
        list.map(entry.rules, fn(rule) {
          html.a([class("chip"), href("/rules/" <> int.to_string(rule.id))], [
            text(categories.split_patterns(rule.regex) |> string.join(" | ")),
          ])
        }),
        [
          html.a(
            [
              class("chip more"),
              href("/rules/new?category=" <> uri.percent_encode(name)),
            ],
            [text("+ rule")],
          ),
        ],
      )
    ]),
  ])
}

/// An app or website with its time, why it is where it is, and a form to
/// move it to another category. `current` is its category, "" for none.
fn item_row(
  item: rules.Item,
  names: List(String),
  current: String,
  extra: List(Element(msg)),
) -> Element(msg) {
  html.form(
    [
      class("item"),
      attribute.method("post"),
      attribute.action("/categories/assign"),
    ],
    [
      hidden("app", item.name),
      hidden("open", current),
      html.div([class("item-name")], [
        html.b([attribute.title(item.name)], [text(item.name)]),
        html.small([], [
          text(
            [source_name(item.source), string.join(item.devices, ", ")]
            |> list.filter(fn(part) { part != "" })
            |> string.join(" · "),
          ),
        ]),
      ]),
      html.span([class("t")], [text(duration(item.ms))]),
      html.select(
        [
          attribute.name("category"),
          attribute.attribute("onchange", "this.form.submit()"),
        ],
        [
          html.option(
            [attribute.value(current), attribute.selected(True)],
            case current {
              "" -> "Move to…"
              name -> name
            },
          ),
          ..list.filter(names, fn(name) { name != current })
          |> list.map(fn(name) { html.option([attribute.value(name)], name) })
        ],
      ),
      ..extra
    ],
  )
}

fn hidden(name: String, value: String) -> Element(msg) {
  html.input([
    attribute.type_("hidden"),
    attribute.name(name),
    attribute.value(value),
  ])
}

pub fn rule_editor(
  rule: Rule,
  overview: rules.Overview,
  error: String,
  preview: Option(rules.Preview),
) -> String {
  let is_new = rule.id == 0
  let patterns = categories.split_patterns(rule.regex)
  let names = list.map(overview.categories, fn(entry) { entry.category.name })
  let title = case is_new {
    True -> "New rule"
    False -> "Rule"
  }
  document(title, [
    html.header([], [
      html.h1([], [text(title)]),
      html.nav([], [
        html.a([href("/categories?open=" <> uri.percent_encode(rule.name))], [
          text("‹ Categories"),
        ]),
      ]),
    ]),
    html.form(
      [class("editor"), attribute.method("post"), attribute.action("/rules")],
      [
        html.section([], [
          case is_new {
            True -> element.none()
            False -> hidden("id", int.to_string(rule.id))
          },
          case error {
            "" -> element.none()
            error -> html.p([class("error")], [text(error)])
          },
          html.p([class("help")], [
            text(
              "Rules are for what a whole app or website can't say, like window
              titles. They win over known apps, but not over what you assigned.",
            ),
          ]),
          html.label([attribute.for("category")], [text("Category")]),
          html.input([
            attribute.id("category"),
            attribute.name("category"),
            attribute.value(rule.name),
            attribute.list("names"),
            attribute.required(True),
          ]),
          html.datalist(
            [attribute.id("names")],
            list.map(names, fn(name) {
              html.option([attribute.value(name)], "")
            }),
          ),
          html.label([attribute.for("patterns")], [text("Patterns")]),
          html.textarea(
            [
              attribute.id("patterns"),
              attribute.name("patterns"),
              attribute.rows(int.clamp(list.length(patterns) + 2, 6, 24)),
              attribute.placeholder("inkpad\nlecture notes"),
              attribute.attribute("spellcheck", "false"),
            ],
            string.join(patterns, "\n"),
          ),
          html.small([class("help")], [
            text(
              "One per line, each matched against the app (or website) and the
              window title. Plain words work, they are regular expressions: \\b
              marks a word boundary, ^x\\.com$ only matches exactly x.com.",
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
            html.button([attribute.name("action"), attribute.value("preview")], [
              text("Preview matches"),
            ]),
            case is_new {
              True -> element.none()
              False ->
                html.button(
                  [
                    class("danger"),
                    attribute.formaction(
                      "/rules/" <> int.to_string(rule.id) <> "/delete",
                    ),
                    attribute.attribute(
                      "onclick",
                      "return confirm('Delete this rule?')",
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
            usage_list("Apps and websites", preview.apps),
            usage_list("Window titles", preview.titles),
          ]),
        ])
    },
  ])
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
  chart_with(report, buckets, [], links)
}

/// The chart of the period, with each day's 7-day average as a line.
fn trend_chart(report: Report, trend: List(Usage)) -> Element(msg) {
  chart_with(report, report.timeline, list.map(trend, fn(day) { day.ms }), True)
}

/// `marks` are drawn as lines over the bars, one per bucket, if given.
fn chart_with(
  report: Report,
  buckets: List(Usage),
  marks: List(Int),
  links: Bool,
) -> Element(msg) {
  let filter = report.filter
  let max = list.fold(buckets, 1, fn(max, bucket) { int.max(max, bucket.ms) })
  let max = list.fold(marks, max, int.max)
  let marks = case marks {
    [] -> list.map(buckets, fn(_) { -1 })
    _ -> marks
  }
  let count = list.length(buckets)
  // at most about 12 labels
  let every = int.max(1, { count + 11 } / 12)
  html.div([class("chart")], [
    html.span([class("max")], [text(duration(max))]),
    ..list.index_map(list.zip(buckets, marks), fn(entry, index) {
      let #(bucket, mark) = entry
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
          <> duration(bucket.ms)
          <> case mark {
            -1 -> ""
            ms -> ", 7-day average " <> duration(ms)
          },
        ),
      ]
      let children = [
        html.div([style("height", percent(bucket.ms, max))], []),
        html.span([], [text(label)]),
        case mark {
          -1 -> element.none()
          ms ->
            html.i(
              [
                style(
                  "bottom",
                  "calc(16px + (100% - 16px) * " <> ratio(ms, max) <> ")",
                ),
              ],
              [],
            )
        },
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

/// Productive, neutral and distracting time as one bar, by the ratings of
/// their categories.
fn rating_bar(insights: Insights) -> Element(msg) {
  let total =
    insights.productive_ms + insights.neutral_ms + insights.distracting_ms
  case total {
    0 -> element.none()
    _ -> {
      let parts = [
        #("productive", insights.productive_ms),
        #("neutral", insights.neutral_ms),
        #("distracting", insights.distracting_ms),
      ]
      html.div([class("ratings")], [
        html.div(
          [class("rating-bar")],
          list.map(parts, fn(part) {
            html.div(
              [
                class(part.0),
                style("width", percent(part.1, total)),
                attribute.title(part.0 <> ": " <> duration(part.1)),
              ],
              [],
            )
          }),
        ),
        html.div(
          [class("legend")],
          list.map(parts, fn(part) {
            html.span([], [
              html.span([class("sw " <> part.0)], []),
              text(part.0 <> " " <> duration(part.1)),
            ])
          }),
        ),
      ])
    }
  }
}

fn ratio(part: Int, whole: Int) -> String {
  float.to_string(int.to_float(part * 1000 / int.max(whole, 1)) /. 1000.0)
}

/// How the period compares with the same one in earlier weeks, under the
/// total.
fn usual_note(insights: Insights, days: Int) -> Element(msg) {
  let total = insights.total
  case total.periods >= 3 {
    False -> element.none()
    True ->
      html.p([class("note")], [
        text(
          "Usually "
          <> duration(total.usual_ms)
          <> case insights.until_now {
            True -> " by this time"
            False -> ""
          }
          <> " ("
          <> period_name(days, total.periods)
          <> "). ",
        ),
        verdict(total.score),
      ])
  }
}

fn period_name(days: Int, periods: Int) -> String {
  let n = int.to_string(periods)
  case days {
    1 -> "median of the same weekday in the " <> n <> " weeks before"
    7 -> "median of the " <> n <> " weeks before"
    _ ->
      "median of the "
      <> n
      <> " periods of "
      <> int.to_string(days)
      <> " days before"
  }
}

/// A robust z-score in words.
fn verdict(score: Float) -> Element(msg) {
  case score {
    s if s >=. 3.0 -> html.b([class("up")], [text("Far more than usual.")])
    s if s >=. 2.0 -> html.b([class("up")], [text("More than usual.")])
    s if s <=. -3.0 -> html.b([class("down")], [text("Far less than usual.")])
    s if s <=. -2.0 -> html.b([class("down")], [text("Less than usual.")])
    _ -> text("Within the usual range.")
  }
}

/// Categories against what is usual for them, the most unusual first.
fn comparisons(report: Report, insights: Insights) -> Element(msg) {
  case insights.total.periods >= 3, insights.categories {
    False, _ | _, [] -> element.none()
    True, items -> {
      let max =
        list.fold(items, 1, fn(max, c) {
          int.max(max, int.max(c.ms, c.usual_ms))
        })
      html.section([], [
        html.h2([], [
          text(case insights.until_now {
            True -> "Categories against what is usual by this time"
            False -> "Categories against what is usual"
          }),
        ]),
        ..list.map(items, fn(c) {
          let change = case stats.change(c.ms, c.usual_ms) {
            Ok(p) if p > 0 -> "+" <> int.to_string(p) <> "%"
            Ok(p) -> int.to_string(p) <> "%"
            Error(Nil) -> "new"
          }
          html.div([class("cmp")], [
            html.b([], [text(c.name)]),
            html.span([], [text(duration(c.ms))]),
            html.div([class("vs")], [
              html.div(
                [
                  class(color_class(report.category_order, c.name)),
                  style("width", percent(c.ms, max)),
                ],
                [],
              ),
              html.i(
                [
                  style("left", percent(c.usual_ms, max)),
                  attribute.title("usually " <> duration(c.usual_ms)),
                ],
                [],
              ),
            ]),
            html.small([], [
              text(
                "usually " <> duration(c.usual_ms) <> " · " <> change <> " · ",
              ),
              verdict(c.score),
            ]),
          ])
        })
      ])
    }
  }
}

/// Pickups, notifications and media, from phones.
fn phone(report: Report, insights: Insights) -> Element(msg) {
  let days = report.filter.days
  let per_day = fn(n) {
    case days {
      1 -> int.to_string(n)
      _ -> float.to_string(int.to_float(n * 10 / days) /. 10.0) <> " a day"
    }
  }
  case insights.pickups + insights.notifications + insights.screen_ons {
    0 -> element.none()
    _ ->
      html.section([], [
        html.h2([], [text("Phone habits")]),
        html.div([class("tiles")], [
          tile("Pickups", per_day(insights.pickups), case days {
            1 -> ""
            _ -> int.to_string(insights.pickups) <> " in total"
          }),
          tile(
            case days {
              1 -> "First pickup"
              _ -> "First pickup, median"
            },
            or_dash(insights.first_pickup),
            "",
          ),
          tile("Notifications", per_day(insights.notifications), ""),
          tile(
            "Pickups after a notification",
            percent(insights.notification_pickups, int.max(insights.pickups, 1)),
            "within a minute",
          ),
          tile(
            "Screen on under a minute",
            percent(insights.short_screen_ons, int.max(insights.screen_ons, 1)),
            "median " <> duration(insights.median_screen_on_ms),
          ),
          tile(
            "Media playing",
            case insights.audio_ms {
              0 -> "–"
              ms -> duration(ms)
            },
            "",
          ),
        ]),
        html.h2([style("margin-top", "20px")], [
          text(case days {
            1 -> "Pickups by hour"
            _ -> "Pickups by hour · all days"
          }),
        ]),
        count_chart(insights.pickup_hours),
        html.div([class("grid"), style("margin-top", "16px")], [
          count_list("Opened first after unlocking", insights.pickup_apps),
          count_list("Notifications", insights.notification_apps),
          case insights.audio_apps {
            [] -> element.none()
            apps -> usage_list("Media", apps)
          },
        ]),
      ])
  }
}

/// Long stretches in one category, switching and use of several devices.
fn focus(report: Report, insights: Insights) -> Element(msg) {
  case report.total_ms {
    0 -> element.none()
    total -> {
      let hours = int.max(total / 3_600_000, 1)
      html.section([], [
        html.h2([], [text("Focus")]),
        html.div([class("tiles")], [
          tile(
            "Productive stretches 25+ min",
            int.to_string(insights.long_stretches),
            duration(insights.long_stretch_ms)
              <> " · "
              <> percent(insights.long_stretch_ms, total),
          ),
          tile(
            "Longest stretch",
            case insights.longest_stretch.ms {
              0 -> "–"
              ms -> duration(ms)
            },
            insights.longest_stretch.name
              <> " "
              <> insights.longest_stretch.detail,
          ),
          tile(
            "App switches",
            int.to_string(insights.app_switches / hours) <> " an hour",
            int.to_string(insights.app_switches) <> " in total",
          ),
          tile(
            "Typical session",
            duration(insights.median_session_ms),
            "median",
          ),
          ..case report.filter.device, insights.phone_during_computer_ms {
            "", ms if ms > 0 -> [
              tile("Phone while at a computer", duration(ms), ""),
              tile(
                "Pickups at a computer",
                int.to_string(insights.pickups_during_computer),
                "",
              ),
            ]
            _, _ -> []
          }
        ]),
        case insights.long_stretch_categories {
          [] -> element.none()
          items ->
            html.div([style("margin-top", "16px")], [
              usage_list_with(
                "Productive stretches by category",
                items,
                fn(item) { color_class(report.category_order, item.name) },
                fn(_) { "" },
              ),
            ])
        },
      ])
    }
  }
}

/// When screen time usually happens, per weekday and hour.
fn usual_week(week: List(List(Int))) -> Element(msg) {
  let max = list.flatten(week) |> list.fold(1, int.max)
  case max {
    1 -> element.none()
    _ -> {
      // Monday first
      let rows = case week {
        [sunday, ..rest] ->
          list.zip(list.append(rest, [sunday]), [
            "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun",
          ])
        [] -> []
      }
      html.section([], [
        html.h2([], [text("Usual week · average of the last 4 weeks")]),
        html.div([class("heat")], [
          html.span([], []),
          ..list.append(
            list.map(hour_numbers(), fn(hour) {
              html.span([], [
                text(case hour % 6 {
                  0 -> int.to_string(hour)
                  _ -> ""
                }),
              ])
            }),
            list.flat_map(rows, fn(row) {
              let #(hours, day) = row
              [
                html.span([], [text(day)]),
                ..list.index_map(hours, fn(ms, hour) {
                  html.div(
                    [
                      style(
                        "background",
                        "color-mix(in srgb, var(--bar) "
                          <> int.to_string(ms * 100 / max)
                          <> "%, var(--bg))",
                      ),
                      attribute.title(
                        day
                        <> " "
                        <> int.to_string(hour)
                        <> ":00: "
                        <> duration(ms),
                      ),
                    ],
                    [],
                  )
                })
              ]
            }),
          )
        ]),
      ])
    }
  }
}

fn hour_numbers() -> List(Int) {
  int.range(from: 0, to: 24, with: [], run: list.prepend) |> list.reverse
}

/// Bars of counts per hour.
fn count_chart(values: List(Int)) -> Element(msg) {
  let max = list.fold(values, 1, int.max)
  html.div([class("chart")], [
    html.span([class("max")], [text(int.to_string(max))]),
    ..list.index_map(values, fn(n, hour) {
      html.div(
        [
          class("col"),
          attribute.title(int.to_string(hour) <> ":00: " <> int.to_string(n)),
        ],
        [
          html.div([style("height", percent(n, max))], []),
          html.span([], [
            text(case hour % 2 {
              0 -> int.to_string(hour) |> string.pad_start(2, "0")
              _ -> ""
            }),
          ]),
        ],
      )
    })
  ])
}

fn count_list(title: String, items: List(Count)) -> Element(msg) {
  case items {
    [] -> element.none()
    _ -> {
      let max = list.fold(items, 1, fn(max, item) { int.max(max, item.count) })
      html.section([], [
        html.h2([], [text(title)]),
        ..list.map(items, fn(item) {
          html.div([class("row")], [
            html.b([attribute.title(item.name)], [text(item.name)]),
            html.span([class("t")], [text(int.to_string(item.count) <> "×")]),
            html.div([class("meter")], [
              html.div([style("width", percent(item.count, max))], []),
            ]),
          ])
        })
      ])
    }
  }
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
