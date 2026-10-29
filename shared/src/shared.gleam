//// The wire format between agent and server.

import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option}

/// Something that happened on a device, see `Kind`. `tz_offset_min` is the
/// device's UTC offset at the start, None from agents that don't send it.
pub type Event {
  Event(
    kind: Kind,
    start_ms: Int,
    duration_ms: Int,
    app: String,
    title: String,
    tz_offset_min: Option(Int),
  )
}

/// `Window` events are the active app and window title, they add up to the
/// screen time. `Web` events are the active browser tab, with the domain as
/// `app`, and overlap the browser's `Window` events.
///
/// Phones send more: `Screen` is the screen being on (also while locked),
/// `Unlock` an unlock and `Notification` a new notification of `app`, both
/// with duration 0, and `Audio` is `app` playing media, which can overlap
/// anything else.
pub type Kind {
  Window
  Web
  Screen
  Unlock
  Notification
  Audio
}

pub const kinds = [Window, Web, Screen, Unlock, Notification, Audio]

pub fn kind_to_string(kind: Kind) -> String {
  case kind {
    Window -> "window"
    Web -> "web"
    Screen -> "screen"
    Unlock -> "unlock"
    Notification -> "notification"
    Audio -> "audio"
  }
}

pub fn kind_from_string(kind: String) -> Result(Kind, Nil) {
  case kind {
    "window" -> Ok(Window)
    "web" -> Ok(Web)
    "screen" -> Ok(Screen)
    "unlock" -> Ok(Unlock)
    "notification" -> Ok(Notification)
    "audio" -> Ok(Audio)
    _ -> Error(Nil)
  }
}

pub fn event_to_json(event: Event) -> json.Json {
  json.object([
    #("kind", json.string(kind_to_string(event.kind))),
    #("start_ms", json.int(event.start_ms)),
    #("duration_ms", json.int(event.duration_ms)),
    #("app", json.string(event.app)),
    #("title", json.string(event.title)),
    #("tz_offset_min", json.nullable(event.tz_offset_min, json.int)),
  ])
}

pub fn event_decoder() -> decode.Decoder(Event) {
  use kind <- decode.field("kind", {
    use kind <- decode.then(decode.string)
    case kind_from_string(kind) {
      Ok(kind) -> decode.success(kind)
      Error(Nil) -> decode.failure(Window, "an event kind")
    }
  })
  use start_ms <- decode.field("start_ms", decode.int)
  use duration_ms <- decode.field("duration_ms", decode.int)
  use app <- decode.field("app", decode.string)
  use title <- decode.field("title", decode.string)
  use tz_offset_min <- decode.optional_field(
    "tz_offset_min",
    option.None,
    decode.optional(decode.int),
  )
  decode.success(Event(
    kind:,
    start_ms:,
    duration_ms:,
    app:,
    title:,
    tz_offset_min:,
  ))
}

/// Replaces all events of a device from `from_ms` on with `events`. `os` is
/// the device's operating system, like "NixOS 25.05" or "Android 15", ""
/// from agents that don't send it. `app_types` is what phones know about
/// their apps: the app (as in events) and its type, like "game", "social"
/// or "maps" (Android's `ApplicationInfo.category`).
pub type Upload {
  Upload(
    from_ms: Int,
    os: String,
    events: List(Event),
    app_types: List(#(String, String)),
  )
}

pub fn upload_to_json(upload: Upload) -> json.Json {
  json.object([
    #("from_ms", json.int(upload.from_ms)),
    #("os", json.string(upload.os)),
    #("events", json.array(upload.events, event_to_json)),
    #(
      "app_types",
      json.array(upload.app_types, fn(entry) {
        json.object([
          #("app", json.string(entry.0)),
          #("type", json.string(entry.1)),
        ])
      }),
    ),
  ])
}

pub fn upload_decoder() -> decode.Decoder(Upload) {
  use from_ms <- decode.field("from_ms", decode.int)
  use os <- decode.optional_field("os", "", decode.string)
  use events <- decode.field("events", decode.list(event_decoder()))
  use app_types <- decode.optional_field(
    "app_types",
    [],
    decode.list({
      use app <- decode.field("app", decode.string)
      use type_ <- decode.field("type", decode.string)
      decode.success(#(app, type_))
    }),
  )
  decode.success(Upload(from_ms:, os:, events:, app_types:))
}
