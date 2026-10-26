import categories.{type Rule, Rule}
import db.{type Filter, type Usage}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/uri
import lustre/attribute.{class, href, style}
import lustre/element.{type Element}
import lustre/element/html.{text}

const css =
  "
:root { --bg: #f6f6f4; --card: #fff; --fg: #1d1d1b; --muted: #77756f; --bar: #4f6bed; --line: #e4e2dc; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #161615; --card: #20201e; --fg: #ecebe6; --muted: #9a988f; --bar: #7d93ff; --line: #33322e; }
}
* { box-sizing: border-box; }
body { margin: 0; padding: 24px 16px; background: var(--bg); color: var(--fg);
  font: 15px/1.45 system-ui, sans-serif; font-variant-numeric: tabular-nums; }
main { max-width: 860px; margin: 0 auto; display: grid; gap: 16px; }
header { display: flex; justify-content: space-between; align-items: baseline; flex-wrap: wrap; gap: 8px; }
h1 { font-size: 20px; margin: 0; } h2 { font-size: 14px; margin: 0 0 12px; color: var(--muted); font-weight: 500; }
nav a { color: var(--muted); margin-left: 12px; text-decoration: none; } nav a.on { color: var(--fg); font-weight: 600; }
section { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 16px; }
.big { font-size: 34px; font-weight: 650; } .muted { color: var(--muted); }
.devices { display: flex; flex-wrap: wrap; gap: 6px; }
.devices a { margin: 0; padding: 3px 10px; border: 1px solid var(--line); border-radius: 99px; background: var(--card); }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 380px), 1fr)); gap: 16px; align-items: start; }
.chart { display: flex; align-items: flex-end; gap: 3px; height: 140px; margin-top: 16px; }
.col { flex: 1; display: flex; flex-direction: column; justify-content: flex-end; height: 100%; min-width: 0; }
.col div { background: var(--bar); border-radius: 3px 3px 0 0; min-height: 2px; }
.col span { font-size: 11px; color: var(--muted); text-align: center; overflow: hidden; white-space: nowrap; }
.row { display: grid; grid-template-columns: minmax(0, 1fr) 72px; gap: 2px 12px; padding: 6px 0; border-top: 1px solid var(--line); }
.row:first-of-type { border-top: 0; }
.row b { font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.row .t { text-align: right; } .row small { color: var(--muted); grid-column: 1 / -1; }
.meter { grid-column: 1 / -1; height: 4px; background: var(--line); border-radius: 2px; }
.meter div { height: 100%; background: var(--bar); border-radius: 2px; }
.rule { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 2fr) auto; gap: 8px;
  align-items: center; padding: 12px 0; border-top: 1px solid var(--line); }
.rule:first-of-type { border-top: 0; }
@media (max-width: 600px) { .rule { grid-template-columns: minmax(0, 1fr); } }
input:not([type=checkbox]), button { font: inherit; color: inherit; border: 1px solid var(--line);
  border-radius: 6px; padding: 5px 8px; min-width: 0; background: var(--bg); }
button { background: var(--card); cursor: pointer; }
.checks { grid-column: 1 / -1; display: flex; flex-wrap: wrap; gap: 4px 14px; font-size: 13px; color: var(--muted); }
.error { color: #d0453a; margin: 0 0 8px; } p { margin: 0 0 8px; }
"

pub fn page(
  filter: Filter,
  devices: List(Usage),
  timeline: List(Usage),
  sections: List(#(String, List(Usage))),
) -> String {
  let total = list.fold(timeline, 0, fn(sum, bucket) { sum + bucket.ms })
  let link = fn(days, device, label, on) {
    html.a(
      [
        href(
          "/?days="
          <> int.to_string(days)
          <> "&device="
          <> uri.percent_encode(device),
        ),
        class(case on {
          True -> "on"
          False -> ""
        }),
      ],
      [text(label)],
    )
  }
  let device_name = case filter.device {
    "" -> "all devices"
    device -> device
  }
  document("Screen time", [
    html.header([], [
      html.h1([], [text("Screen time")]),
      html.nav(
        [],
        list.map([#(1, "Today"), #(7, "7 days"), #(30, "30 days")], fn(range) {
          link(range.0, filter.device, range.1, range.0 == filter.days)
        })
          |> list.append([html.a([href("/categories")], [text("Categories")])]),
      ),
    ]),
    html.nav([class("devices")], [
      link(filter.days, "", "All devices", filter.device == ""),
      ..list.map(devices, fn(device) {
        link(
          filter.days,
          device.name,
          device.name,
          device.name == filter.device,
        )
      })
    ]),
    html.section([], [
      html.div([class("big")], [text(duration(total))]),
      html.div([class("muted")], [
        text(case filter.days {
          1 -> "today on " <> device_name
          days ->
            "on "
            <> device_name
            <> " · "
            <> duration(total / days)
            <> " per day on average"
        }),
      ]),
      chart(timeline),
    ]),
    html.div(
      [class("grid")],
      list.map(sections, fn(section) { usage_list(section.0, section.1) }),
    ),
  ])
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

fn chart(buckets: List(Usage)) -> Element(msg) {
  let max = list.fold(buckets, 1, fn(max, bucket) { int.max(max, bucket.ms) })
  html.div(
    [class("chart")],
    list.map(buckets, fn(bucket) {
      html.div(
        [
          class("col"),
          attribute.title(bucket.name <> ": " <> duration(bucket.ms)),
        ],
        [
          html.div([style("height", percent(bucket.ms, max))], []),
          // hour "07" or day "2026-10-26" -> "10-26"
          html.span([], [text(string.slice(bucket.name, -5, 5))]),
        ],
      )
    }),
  )
}

fn usage_list(title: String, items: List(Usage)) -> Element(msg) {
  let max = list.fold(items, 1, fn(max, item) { int.max(max, item.ms) })
  html.section([], [
    html.h2([], [text(title)]),
    ..list.map(items, fn(item) {
      html.div([class("row")], [
        html.b([], [text(item.name)]),
        html.span([class("t")], [text(duration(item.ms))]),
        html.small([], [text(item.detail)]),
        html.div([class("meter")], [
          html.div([style("width", percent(item.ms, max))], []),
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
