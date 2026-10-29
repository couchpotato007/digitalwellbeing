//// Categories are set up on the server, in the dashboard and the app. Most
//// events get theirs on their own: from a catalog of known apps, sites and
//// Android packages, from what Android says an app is, and browser windows
//// from the website shown. Apps and sites can be assigned to a category by
//// hand, and advanced rules (regexes on the app and title) cover the rest,
//// see `categorizer`. Each category is rated productive, neutral or
//// distracting.

import gleam/dict.{type Dict}
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

/// How a category counts on the dashboard.
pub type Rating {
  Productive
  Neutral
  Distracting
}

pub fn rating_to_string(rating: Rating) -> String {
  case rating {
    Productive -> "productive"
    Neutral -> "neutral"
    Distracting -> "distracting"
  }
}

pub fn rating_from_string(rating: String) -> Result(Rating, Nil) {
  case rating {
    "productive" -> Ok(Productive)
    "neutral" -> Ok(Neutral)
    "distracting" -> Ok(Distracting)
    _ -> Error(Nil)
  }
}

/// A category as set up on the server. `builtin` is the key of a built-in
/// one, its known apps follow it when it is renamed, "" for own ones.
pub type Category {
  Category(name: String, rating: Rating, builtin: String)
}

/// What a new server starts with, in the order of their colors. The key is
/// the name they start with.
pub const builtins = [
  #("Work > Programming", Productive),
  #("Work > Office", Productive),
  #("Work > Design", Productive),
  #("Comms > Chat", Neutral),
  #("Comms > Email", Neutral),
  #("Comms > Meetings", Neutral),
  #("Media > Music", Neutral),
  #("Media > Podcasts & Books", Neutral),
  #("Media > Video", Distracting),
  #("Media > Social Media", Distracting),
  #("Media > Games", Distracting),
  #("Media > News", Distracting),
  #("Media > Photos", Neutral),
  #("Browsing", Neutral),
  #("Navigation", Neutral),
  #("Shopping", Distracting),
  #("Utilities", Neutral),
]

/// Known apps, sites and Android packages per built-in category. The first
/// that matches wins, so music.youtube.com is Music, not Video. Anchored
/// patterns like ^x\.com$ only match a whole name.
pub const catalog = [
  #(
    "Work > Programming",
    "\\b(code|codium|vscodium|vim|nvim|neovim|helix|emacs|zed|kate|xcode|sublime_text)\\b|jetbrains|android studio|github|gitlab|codeberg|bitbucket|stack ?overflow|stackexchange|alacritty|kitty|wezterm|ghostty|\\bfoot\\b|konsole|gnome-terminal|terminal|iterm|termux|lazygit|docs\\.rs|hexdocs|crates\\.io|npmjs|pypi",
  ),
  #(
    "Work > Office",
    "libreoffice|soffice|onlyoffice|collabora|winword|microsoft word|\\bexcel\\b|powerpoint|google docs|docs\\.google|google sheets|google slides|notion|obsidian|logseq|joplin|overleaf|todoist|tasks\\.org|ticktick|google keep|\\bkeep notes\\b|nextcloud notes|standard ?notes|zotero",
  ),
  #(
    "Work > Design",
    "gimp|inkscape|krita|figma|blender|darktable|photoshop|illustrator|affinity|kdenlive|audacity|penpot",
  ),
  #(
    "Comms > Meetings",
    "\\bzoom\\b|\\bteams\\b|meet\\.google|google meet|jitsi|webex|bigbluebutton",
  ),
  #(
    "Comms > Chat",
    "^(signal|molly|element|element x|telegram|telegramdesktop|whatsapp|discord|slack|mattermost|messenger|threema|session|briar|simplex|wire|nheko|fractal|gajim|conversations)$|web\\.whatsapp|discord\\.com|app\\.slack|element\\.io|app\\.element|org\\.thoughtcrime|im\\.molly|io\\.element|im\\.vector|org\\.telegram|com\\.whatsapp|ch\\.threema|com\\.discord|eu\\.siacs\\.conversations",
  ),
  #(
    "Comms > Email",
    "thunderbird|betterbird|evolution|geary|outlook|gmail|mail\\.google|proton ?mail|mailspring|\\bmutt\\b|aerc|faircode|fairemail|k-9|k9mail|tutanota|\\btuta\\b|com\\.google\\.android\\.gm$",
  ),
  #(
    "Media > Podcasts & Books",
    "antennapod|pocket ?casts|podcast|absorb|audiobookshelf|lissen|audible|libby|kindle|play books|play bücher|apps\\.books|readera|librera|koreader|moon\\+ reader|calibre|tolino|kobo|audiobook|hörbuch",
  ),
  #(
    "Media > Music",
    "spotify|deezer|tidal|soundcloud|music\\.youtube|youtube music|apple music|rhythmbox|strawberry|symfonium|feishin|auxio|retro music|poweramp|bandcamp|apps\\.youtube\\.music",
  ),
  #(
    "Media > Video",
    "youtube|netflix|twitch|\\bplex\\b|jellyfin|\\bvlc\\b|\\bmpv\\b|disneyplus|disney\\+|primevideo|prime video|crunchyroll|kodi|newpipe|tubular|freetube|grayjay|justwatch|mediathek|\\barte\\b|vimeo|joyn",
  ),
  #(
    "Media > Social Media",
    "reddit|facebook|instagram|twitter|^x\\.com$|tiktok|mastodon|bsky|bluesky|linkedin|threads\\.net|tumblr|pinterest|snapchat|lemmy|jerboa|tusky|moshidon|pixelfed|bumble|tinder|hinge|com\\.zhiliaoapp",
  ),
  #(
    "Media > Games",
    "steam|lutris|heroic|minecraft|epic games|gog galaxy|itch\\.io|retroarch|skat|chess|lichess|sudoku|solitaire|puzzle|candy crush|clash of|pokémon|pokemon|nintendo",
  ),
  #(
    "Media > News",
    "\\bnews\\b|ycombinator|bbc\\.|nytimes|theguardian|reuters|spiegel|tagesschau|zeit\\.de|heise|golem\\.de|feeder|read you|newsblur|feedly|flipboard|apps\\.magazines",
  ),
  #(
    "Media > Photos",
    "^(photos|fotos|gallery|galerie|camera|kamera|aves)$|immich|lightroom|snapseed|apps\\.photos|fossify gallery",
  ),
  #(
    "Shopping",
    "amazon|ebay|etsy|aliexpress|\\btemu\\b|zalando|kleinanzeigen|vinted|idealo|\\bdhl\\b|de\\.dhl|hermes|kitchenowl|\\bbring!?\\b",
  ),
  #(
    "Navigation",
    "^(maps|karten)$|google maps|apps\\.maps|osmand|organic ?maps|comaps|öffi|db navigator|komoot|citymapper|\\bwaze\\b|transit",
  ),
  #(
    "Browsing",
    "firefox|zen browser|zen_browser|chrom|brave|vivaldi|\\bedge\\b|msedge|\\bopera\\b|librewolf|floorp|waterfox|tor ?browser|torproject|duckduckgo|samsung internet|sbrowser|ironfox|fennec|\\bmull\\b|cromite|vanadium|epiphany|qutebrowser",
  ),
  #(
    "Utilities",
    "^(settings|einstellungen|files|dateien|clock|uhr|calculator|rechner|contacts|kontakte|phone|telefon|wellbeing|activitywatch)$|play store|com\\.android\\.vending|f-droid|obtainium|aurora store|droid-ify|bitwarden|keepass|proton pass|1password|authenticator|aegis|nautilus|dolphin|thunar|pavucontrol|systemsettings|gnome-control-center|wireguard|tailscale|google drive|nextcloud|syncthing|localsend|com\\.android\\.settings",
  ),
]

/// What Android says an app is (`ApplicationInfo.category`, the phone sends
/// it along), as a built-in category.
pub const android_types = [
  #("game", "Media > Games"),
  #("audio", "Media > Music"),
  #("video", "Media > Video"),
  #("image", "Media > Photos"),
  #("social", "Media > Social Media"),
  #("news", "Media > News"),
  #("maps", "Navigation"),
  #("productivity", "Work > Office"),
  #("accessibility", "Utilities"),
]

/// The rules a server had before categories were set up like now, which
/// the catalog does now. Unchanged copies of them are dropped.
pub const old_defaults = [
  #(
    "Work > Programming",
    "\\b(code|codium|vim|nvim|emacs|zed|kate|xcode|sublime_text)\\b|jetbrains|android studio|github|gitlab|codeberg|bitbucket|stack ?overflow|stackexchange|alacritty|kitty|wezterm|ghostty|\\bfoot\\b|konsole|gnome-terminal|terminal|iterm",
  ),
  #(
    "Work > Office",
    "libreoffice|soffice|onlyoffice|winword|microsoft word|\\bexcel\\b|powerpoint|google docs|docs\\.google|google sheets|google slides|notion|obsidian|logseq|joplin|overleaf",
  ),
  #(
    "Work > Design",
    "gimp|inkscape|krita|figma|blender|darktable|photoshop|illustrator|affinity|kdenlive|audacity",
  ),
  #(
    "Comms > Chat",
    "^(signal|element|telegram|telegramdesktop|whatsapp|discord|slack|mattermost|messenger)$|web\\.whatsapp|discord\\.com|app\\.slack|element\\.io",
  ),
  #(
    "Comms > Email",
    "thunderbird|betterbird|evolution|geary|outlook|gmail|mail\\.google|proton ?mail|mailspring|\\bmutt\\b|aerc",
  ),
  #(
    "Comms > Meetings",
    "\\bzoom\\b|\\bteams\\b|meet\\.google|google meet|jitsi|webex|bigbluebutton",
  ),
  #(
    "Media > Music",
    "spotify|deezer|tidal|soundcloud|music\\.youtube|youtube music|apple music|rhythmbox|strawberry",
  ),
  #(
    "Media > Video",
    "youtube|netflix|twitch|\\bplex\\b|jellyfin|\\bvlc\\b|\\bmpv\\b|disneyplus|disney\\+|primevideo|prime video|crunchyroll|kodi",
  ),
  #(
    "Media > Social Media",
    "reddit|facebook|instagram|twitter|^x\\.com$|tiktok|mastodon|bsky|bluesky|linkedin|threads\\.net|tumblr",
  ),
  #(
    "Media > Games",
    "steam|lutris|heroic|minecraft|epic games|gog galaxy|itch\\.io|retroarch",
  ),
  #("Media > News", "\\bnews\\b|ycombinator|bbc\\.|nytimes|theguardian|reuters"),
  #("Shopping", "amazon|ebay|etsy|aliexpress|\\btemu\\b"),
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

/// Why an event is in its category.
pub type Source {
  /// Assigned by hand
  Assigned
  /// An advanced rule
  ByRule
  /// A known app, site or package
  Known
  /// What Android says the app is
  AndroidType
  /// A website without a category of its own, it has its browser's
  InBrowser
  /// Nothing matched
  NoSource
}

pub fn source_to_string(source: Source) -> String {
  case source {
    Assigned -> "assigned"
    ByRule -> "rule"
    Known -> "known"
    AndroidType -> "android"
    InBrowser -> "browser"
    NoSource -> "none"
  }
}

/// A category of an event, why, and what decided it: the website for pieces
/// of a browser window that have one, otherwise the app.
pub type Match {
  Match(category: String, source: Source, item: String)
}

/// Everything categories come from: the categories, the advanced rules, apps
/// assigned by hand (lowercase app or site -> category) and what Android
/// says apps are (lowercase app -> type).
pub type Setup {
  Setup(
    categories: List(Category),
    rules: List(Rule),
    assigned: Dict(String, String),
    types: Dict(String, String),
  )
}

/// The categorizer of a setup: an event on `device` with `app`, `title` and
/// `site` (the website, "" if none) gets, in this order,
///
/// 1. the category its site or app is assigned to,
/// 2. the deepest advanced rule that matches the site or app or the title
///    (the first of equally deep ones),
/// 3. the built-in category of a known site, app or package (titles only
///    count when they are a package name, like phones send: with dots, no
///    spaces),
/// 4. what Android says the app is,
///
/// trying the site first, then the app. Categories that don't exist (any
/// more) don't count, so deleting a built-in one also stops its known apps.
pub fn categorizer(
  setup: Setup,
) -> fn(String, String, String, String) -> Match {
  let names = list.map(setup.categories, fn(c) { c.name })
  let current = fn(name) {
    case list.contains(names, name) {
      True -> Ok(name)
      False -> Error(Nil)
    }
  }
  // built-in keys to the names they have now
  let builtin =
    list.filter(setup.categories, fn(c) { c.builtin != "" })
    |> list.map(fn(c) { #(c.builtin, c.name) })
    |> dict.from_list
  let compiled =
    list.filter_map(setup.rules, fn(rule) {
      compile(rule.regex, rule.ignore_case)
      |> result.map(fn(regex) {
        #(rule, regex, list.length(string.split(rule.name, " > ")))
      })
    })
  let known =
    list.filter_map(catalog, fn(entry) {
      use name <- result.try(dict.get(builtin, entry.0))
      compile(entry.1, True)
      |> result.replace_error(Nil)
      |> result.map(fn(regex) { #(name, regex) })
    })
  let types =
    list.filter_map(android_types, fn(entry) {
      dict.get(builtin, entry.1) |> result.map(fn(name) { #(entry.0, name) })
    })
    |> dict.from_list

  let by = fn(device, target, title) {
    let assigned =
      dict.get(setup.assigned, string.lowercase(target))
      |> result.try(current)
      |> result.map(fn(name) { Match(name, Assigned, target) })
    use <- result.lazy_or(assigned)
    let #(best, _) =
      list.fold(compiled, #(Error(Nil), 0), fn(best, candidate) {
        let #(rule, regex, depth) = candidate
        // the first of the deepest matches wins
        case
          depth > best.1
          && { rule.devices == [] || list.contains(rule.devices, device) }
          && { regexp.check(regex, target) || regexp.check(regex, title) }
        {
          True -> #(Ok(rule.name), depth)
          False -> best
        }
      })
    let ruled =
      result.try(best, current)
      |> result.map(fn(name) { Match(name, ByRule, target) })
    use <- result.lazy_or(ruled)
    // like "org.mozilla.firefox", window titles aren't
    let package = case
      string.contains(title, ".") && !string.contains(title, " ")
    {
      True -> title
      False -> ""
    }
    let catalogued =
      list.find(known, fn(entry) {
        regexp.check(entry.1, target)
        || { package != "" && regexp.check(entry.1, package) }
      })
      |> result.map(fn(entry) { Match(entry.0, Known, target) })
    use <- result.lazy_or(catalogued)
    dict.get(setup.types, string.lowercase(target))
    |> result.try(dict.get(types, _))
    |> result.map(fn(name) { Match(name, AndroidType, target) })
  }

  fn(device, app, title, site) {
    // some windows have no app name, the end of their title ("test.md —
    // inkpad") or the whole title stands in
    let app = case app, string.split(title, " — ") |> list.last {
      "", Ok(name) -> string.trim(name)
      "", Error(Nil) -> title
      app, _ -> app
    }
    let by_site = case site {
      "" -> Error(Nil)
      site -> by(device, site, title)
    }
    // a site without a category of its own has the browser's, but is still
    // listed as itself, to be assigned
    by_site
    |> result.lazy_or(fn() {
      by(device, app, title)
      |> result.map(fn(m) {
        case site {
          "" -> m
          site -> Match(..m, source: InBrowser, item: site)
        }
      })
    })
    |> result.unwrap(
      Match(uncategorized, NoSource, case site {
        "" -> app
        site -> site
      }),
    )
  }
}
