//// The wire format between agent and server.

import gleam/dynamic/decode
import gleam/json

/// One stretch of time something was in the foreground on a device.
///
/// `Window` events are the active app and window title, they add up to the
/// screen time. `Web` events are the active browser tab, with the domain as
/// `app`, and overlap the browser's `Window` events.
pub type Event {
  Event(
    kind: Kind,
    start_ms: Int,
    duration_ms: Int,
    app: String,
    title: String,
    /// ActivityWatch category path like "Work > Programming"
    category: String,
  )
}

pub type Kind {
  Window
  Web
}

pub fn kind_to_string(kind: Kind) -> String {
  case kind {
    Window -> "window"
    Web -> "web"
  }
}

pub fn event_to_json(event: Event) -> json.Json {
  json.object([
    #("kind", json.string(kind_to_string(event.kind))),
    #("start_ms", json.int(event.start_ms)),
    #("duration_ms", json.int(event.duration_ms)),
    #("app", json.string(event.app)),
    #("title", json.string(event.title)),
    #("category", json.string(event.category)),
  ])
}

pub fn event_decoder() -> decode.Decoder(Event) {
  use kind <- decode.field("kind", {
    use kind <- decode.then(decode.string)
    case kind {
      "window" -> decode.success(Window)
      "web" -> decode.success(Web)
      _ -> decode.failure(Window, "window or web")
    }
  })
  use start_ms <- decode.field("start_ms", decode.int)
  use duration_ms <- decode.field("duration_ms", decode.int)
  use app <- decode.field("app", decode.string)
  use title <- decode.field("title", decode.string)
  use category <- decode.field("category", decode.string)
  decode.success(Event(kind:, start_ms:, duration_ms:, app:, title:, category:))
}

/// Replaces all events of a device from `from_ms` on with `events`.
pub type Upload {
  Upload(from_ms: Int, events: List(Event))
}

pub fn upload_to_json(upload: Upload) -> json.Json {
  json.object([
    #("from_ms", json.int(upload.from_ms)),
    #("events", json.array(upload.events, event_to_json)),
  ])
}

pub fn upload_decoder() -> decode.Decoder(Upload) {
  use from_ms <- decode.field("from_ms", decode.int)
  use events <- decode.field("events", decode.list(event_decoder()))
  decode.success(Upload(from_ms:, events:))
}
