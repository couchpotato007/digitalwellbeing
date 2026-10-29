import browsing
import gleam/list
import gleam/option.{None}
import shared.{Event}

fn window(start, length) {
  Event(shared.Window, start, length, "zen", "title", None)
}

fn tab(start, length, site) {
  Event(shared.Web, start, length, site, "tab", None)
}

fn pieces(events) {
  browsing.split(events)
  |> list.filter(fn(e) { { e.0 }.kind == shared.Window })
  |> list.map(fn(e) { #({ e.0 }.start_ms, { e.0 }.duration_ms, e.1) })
}

pub fn split_test() {
  // a window from 0 to 100, tabs from 10 to 40 and 40 to 120
  assert pieces([window(0, 100), tab(10, 30, "a.org"), tab(40, 80, "b.org")])
    == [#(0, 10, ""), #(10, 30, "a.org"), #(40, 60, "b.org")]
  // without tabs it stays
  assert pieces([window(0, 100)]) == [#(0, 100, "")]
  // a gap between tabs, and a second window
  assert pieces([
      window(0, 100),
      window(200, 50),
      tab(20, 10, "a.org"),
      tab(210, 10, "c.org"),
    ])
    == [
      #(0, 20, ""),
      #(20, 10, "a.org"),
      #(30, 70, ""),
      #(200, 10, ""),
      #(210, 10, "c.org"),
      #(220, 30, ""),
    ]
}

pub fn others_stay_test() {
  let events = [window(0, 10), tab(0, 10, "a.org")]
  let assert [_, #(web, "")] = browsing.split(events)
  assert web.kind == shared.Web
}
