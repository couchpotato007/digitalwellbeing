//// Browser windows are split where the tab changes, so that each piece gets
//// the category of the website it showed. ActivityWatch sends the active
//// tab as `Web` events, only while the browser window is active.

import gleam/int
import gleam/list
import shared.{type Event, Event}

/// Every event with its site: window events that overlap tabs are split at
/// the tabs' edges, a piece showing a tab has its domain as site, the rest
/// "". Other events stay as they are, with "".
pub fn split(events: List(Event)) -> List(#(Event, String)) {
  let #(windows, others) =
    list.partition(events, fn(e) { e.kind == shared.Window })
  let tabs =
    list.filter(others, fn(e) { e.kind == shared.Web })
    |> list.sort(fn(a, b) { int.compare(a.start_ms, b.start_ms) })
  let windows =
    list.sort(windows, fn(a, b) { int.compare(a.start_ms, b.start_ms) })
  list.append(
    split_loop(windows, tabs, []),
    list.map(others, fn(e) { #(e, "") }),
  )
}

fn split_loop(
  windows: List(Event),
  tabs: List(Event),
  acc: List(#(Event, String)),
) -> List(#(Event, String)) {
  case windows {
    [] -> list.reverse(acc)
    [window, ..rest] -> {
      let start = window.start_ms
      let end = start + window.duration_ms
      // tabs that ended before this window can't overlap later ones either
      let tabs =
        list.drop_while(tabs, fn(t) { t.start_ms + t.duration_ms <= start })
      let inside = list.take_while(tabs, fn(t) { t.start_ms < end })
      split_loop(
        rest,
        tabs,
        list.append(list.reverse(pieces(window, inside)), acc),
      )
    }
  }
}

/// The pieces of `window` with the `tabs` overlapping it, in order.
fn pieces(window: Event, tabs: List(Event)) -> List(#(Event, String)) {
  let end = window.start_ms + window.duration_ms
  let piece = fn(from, to, site) {
    #(Event(..window, start_ms: from, duration_ms: to - from), site)
  }
  let #(pieces, cursor) =
    list.fold(tabs, #([], window.start_ms), fn(acc, tab) {
      let #(pieces, cursor) = acc
      let from = int.max(tab.start_ms, cursor)
      let to = int.min(tab.start_ms + tab.duration_ms, end)
      case to > from {
        False -> acc
        True -> {
          let pieces = case from > cursor {
            True -> [piece(cursor, from, ""), ..pieces]
            False -> pieces
          }
          #([piece(from, to, tab.app), ..pieces], to)
        }
      }
    })
  let pieces = case cursor < end {
    True -> [piece(cursor, end, ""), ..pieces]
    False -> pieces
  }
  list.reverse(pieces)
}
