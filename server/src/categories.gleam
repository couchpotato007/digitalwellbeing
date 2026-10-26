//// Categories are set up on the server, in the dashboard. Like in
//// ActivityWatch, a category is a regex that is matched against the app and
//// the title of an event (the domain and the tab title for browser tabs).
//// An event gets the deepest category that matches, or "Uncategorized".

import gleam/int
import gleam/list
import gleam/regexp.{type Regexp}
import gleam/result
import gleam/string

pub type Rule {
  Rule(
    id: Int,
    /// A path like "Work > Programming"
    name: String,
    regex: String,
    ignore_case: Bool,
    /// The devices the rule applies to, all devices if empty
    devices: List(String),
  )
}

pub const uncategorized = "Uncategorized"

/// What a new server starts with, based on ActivityWatch's defaults. Order
/// matters among equally deep categories: music.youtube.com is Music, not
/// Video. Anchored patterns like ^x\.com$ only match a whole app or domain.
pub const defaults = [
  Rule(
    0,
    "Work > Programming",
    "\\b(code|codium|vim|nvim|emacs|zed|kate|xcode|sublime_text)\\b|jetbrains|android studio|github|gitlab|codeberg|bitbucket|stack ?overflow|stackexchange|alacritty|kitty|wezterm|ghostty|\\bfoot\\b|konsole|gnome-terminal|terminal|iterm",
    True,
    [],
  ),
  Rule(
    0,
    "Work > Office",
    "libreoffice|soffice|onlyoffice|winword|microsoft word|\\bexcel\\b|powerpoint|google docs|docs\\.google|google sheets|google slides|notion|obsidian|logseq|joplin|overleaf",
    True,
    [],
  ),
  Rule(
    0,
    "Work > Design",
    "gimp|inkscape|krita|figma|blender|darktable|photoshop|illustrator|affinity|kdenlive|audacity",
    True,
    [],
  ),
  Rule(
    0,
    "Comms > Chat",
    "^(signal|element|telegram|telegramdesktop|whatsapp|discord|slack|mattermost|messenger)$|web\\.whatsapp|discord\\.com|app\\.slack|element\\.io",
    True,
    [],
  ),
  Rule(
    0,
    "Comms > Email",
    "thunderbird|betterbird|evolution|geary|outlook|gmail|mail\\.google|proton ?mail|mailspring|\\bmutt\\b|aerc",
    True,
    [],
  ),
  Rule(
    0,
    "Comms > Meetings",
    "\\bzoom\\b|\\bteams\\b|meet\\.google|google meet|jitsi|webex|bigbluebutton",
    True,
    [],
  ),
  Rule(
    0,
    "Media > Music",
    "spotify|deezer|tidal|soundcloud|music\\.youtube|youtube music|apple music|rhythmbox|strawberry",
    True,
    [],
  ),
  Rule(
    0,
    "Media > Video",
    "youtube|netflix|twitch|\\bplex\\b|jellyfin|\\bvlc\\b|\\bmpv\\b|disneyplus|disney\\+|primevideo|prime video|crunchyroll|kodi",
    True,
    [],
  ),
  Rule(
    0,
    "Media > Social Media",
    "reddit|facebook|instagram|twitter|^x\\.com$|tiktok|mastodon|bsky|bluesky|linkedin|threads\\.net|tumblr",
    True,
    [],
  ),
  Rule(
    0,
    "Media > Games",
    "steam|lutris|heroic|minecraft|epic games|gog galaxy|itch\\.io|retroarch",
    True,
    [],
  ),
  Rule(
    0,
    "Media > News",
    "\\bnews\\b|ycombinator|bbc\\.|nytimes|theguardian|reuters",
    True,
    [],
  ),
  Rule(0, "Shopping", "amazon|ebay|etsy|aliexpress|\\btemu\\b", True, []),
]

/// The alternatives of a regex, split at the `|` that are not inside a
/// group, a class or escaped: "a|(b|c)|d" -> ["a", "(b|c)", "d"]. Editors
/// show them one per line, `join_patterns` puts them back together.
pub fn split_patterns(regex: String) -> List(String) {
  let #(done, current, _, _, _) =
    string.to_graphemes(regex)
    |> list.fold(#([], "", 0, False, False), fn(state, char) {
      let #(done, current, depth, in_class, escaped) = state
      case char {
        _ if escaped -> #(done, current <> char, depth, in_class, False)
        "\\" -> #(done, current <> char, depth, in_class, True)
        "[" if !in_class -> #(done, current <> char, depth, True, False)
        "]" if in_class -> #(done, current <> char, depth, False, False)
        "(" if !in_class -> #(done, current <> char, depth + 1, in_class, False)
        ")" if !in_class -> #(done, current <> char, depth - 1, in_class, False)
        "|" if !in_class && depth == 0 -> #(
          [current, ..done],
          "",
          depth,
          in_class,
          False,
        )
        _ -> #(done, current <> char, depth, in_class, False)
      }
    })
  [current, ..done]
  |> list.reverse
  |> list.map(string.trim)
  |> list.filter(fn(pattern) { pattern != "" })
}

/// The regex of patterns, empty ones left out.
pub fn join_patterns(patterns: List(String)) -> String {
  list.map(patterns, string.trim)
  |> list.filter(fn(pattern) { pattern != "" })
  |> string.join("|")
}

/// `text` as a pattern that matches only itself: "x.com" -> "x\\.com"
pub fn escape(text: String) -> String {
  string.to_graphemes(text)
  |> list.map(fn(char) {
    case string.contains("\\^$.|?*+()[]{}", char) {
      True -> "\\" <> char
      False -> char
    }
  })
  |> string.concat
}

/// Whether `rule` matches an event, regardless of deeper rules.
pub fn matches(
  rule: Rule,
  regex: Regexp,
  device: String,
  app: String,
  title: String,
) -> Bool {
  { rule.devices == [] || list.contains(rule.devices, device) }
  && { regexp.check(regex, app) || regexp.check(regex, title) }
}

/// "Work>  Programming " -> "Work > Programming"
pub fn normalize_name(name: String) -> String {
  string.split(name, ">")
  |> list.map(string.trim)
  |> list.filter(fn(part) { part != "" })
  |> string.join(" > ")
}

pub fn compile(regex: String, ignore_case: Bool) -> Result(Regexp, String) {
  regexp.compile(
    regex,
    regexp.Options(case_insensitive: ignore_case, multi_line: False),
  )
  |> result.map_error(fn(err) {
    "Invalid regex at " <> int.to_string(err.byte_index) <> ": " <> err.error
  })
}

/// The category of an event on `device` with `app` and `title`. Rules that
/// don't compile are skipped, they are checked when they are saved.
pub fn categorizer(rules: List(Rule)) -> fn(String, String, String) -> String {
  let compiled =
    list.filter_map(rules, fn(rule) {
      compile(rule.regex, rule.ignore_case)
      |> result.map(fn(regex) {
        #(rule, regex, list.length(string.split(rule.name, " > ")))
      })
    })
  fn(device, app, title) {
    let #(name, _) =
      list.fold(compiled, #(uncategorized, 0), fn(best, candidate) {
        let #(rule, regex, depth) = candidate
        // the first of the deepest matches wins
        case
          depth > best.1
          && { rule.devices == [] || list.contains(rule.devices, device) }
          && { regexp.check(regex, app) || regexp.check(regex, title) }
        {
          True -> #(rule.name, depth)
          False -> best
        }
      })
    name
  }
}
