import categories.{type Rule, Rule}
import db.{type Usage}
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import gleam/uri
import lustre/attribute.{class, href, style}
import lustre/element.{type Element}
import lustre/element/html.{text}
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
.rule { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 2fr) auto; gap: 8px;
  align-items: center; padding: 12px 0; border-top: 1px solid var(--line); }
.rule:first-of-type { border-top: 0; }
@media (max-width: 600px) { .rule { grid-template-columns: minmax(0, 1fr); } .strip { grid-template-columns: 64px minmax(0, 1fr); } }
input:not([type=checkbox]), button { font: inherit; color: inherit; border: 1px solid var(--line);
  border-radius: 6px; padding: 5px 8px; min-width: 0; background: var(--bg); }
button { background: var(--card); cursor: pointer; }
.pills input { padding: 2px 8px; border-radius: 99px; background: var(--card); }
.checks { grid-column: 1 / -1; display: flex; flex-wrap: wrap; gap: 4px 14px; font-size: 13px; color: var(--muted); }
.error { color: #d0453a; margin: 0 0 8px; } p { margin: 0 0 8px; }
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
                  segment.category
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

/// The category rules, one form each, and what has no category yet.
pub fn categories_page(
  rules: List(Rule),
  devices: List(String),
  error: String,
  sections: List(#(String, List(Usage))),
) -> String {
  // devices of rules might not have sent anything yet
  let devices =
    list.flat_map(rules, fn(rule) { rule.devices })
    |> list.append(devices)
    |> list.unique
    |> list.sort(string.compare)
  document("Categories", [
    html.header([], [
      html.h1([], [text("Categories")]),
      html.nav([], [html.a([href("/")], [text("Screen time")])]),
    ]),
    html.section([], [
      html.p([class("muted")], [
        text(
          "Every app and window title gets the deepest category whose regex
          matches it (for browser tabs: the domain and tab title). Use > for
          subcategories, like Work > Programming. A rule without devices
          applies to all of them.",
        ),
      ]),
      case error {
        "" -> element.none()
        error -> html.p([class("error")], [text(error)])
      },
      case
        list.any(categories.defaults, fn(default) {
          !list.any(rules, fn(rule) { rule.name == default.name })
        })
      {
        True ->
          html.form(
            [attribute.method("post"), attribute.action("/categories/defaults")],
            [html.button([], [text("Add missing default categories")])],
          )
        False -> element.none()
      },
      ..list.map(rules, fn(rule) { rule_form(Some(rule.id), rule, devices) })
      |> list.append([rule_form(None, Rule(0, "", "", True, []), devices)])
    ]),
    html.div(
      [class("grid")],
      list.map(sections, fn(section) { usage_list(section.0, section.1) }),
    ),
  ])
}

fn rule_form(
  id: Option(Int),
  rule: Rule,
  devices: List(String),
) -> Element(msg) {
  let checkbox = fn(name, value, checked, label) {
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
  html.form(
    [class("rule"), attribute.method("post"), attribute.action("/categories")],
    [
      case id {
        Some(id) ->
          html.input([
            attribute.type_("hidden"),
            attribute.name("id"),
            attribute.value(int.to_string(id)),
          ])
        None -> element.none()
      },
      html.input([
        attribute.name("name"),
        attribute.value(rule.name),
        attribute.placeholder("Work > Programming"),
        attribute.required(True),
      ]),
      html.input([
        attribute.name("regex"),
        attribute.value(rule.regex),
        attribute.placeholder("code|vim|github"),
        attribute.required(True),
      ]),
      html.div([], [
        html.button([], [
          text(case id {
            Some(_) -> "Save"
            None -> "Add"
          }),
        ]),
        case id {
          Some(id) ->
            html.button(
              [
                attribute.formaction(
                  "/categories/" <> int.to_string(id) <> "/delete",
                ),
                style("margin-left", "6px"),
              ],
              [text("Delete")],
            )
          None -> element.none()
        },
      ]),
      html.div([class("checks")], [
        checkbox("ignore_case", "on", rule.ignore_case, "ignore case"),
        ..list.map(devices, fn(device) {
          checkbox(
            "devices",
            device,
            list.contains(rule.devices, device),
            device,
          )
        })
      ]),
    ],
  )
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
