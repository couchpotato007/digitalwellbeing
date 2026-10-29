import categories.{Category, Rule, Setup}
import gleam/dict
import gleam/list

fn builtins() {
  list.map(categories.builtins, fn(b) { Category(b.0, b.1, b.0) })
}

fn setup() {
  Setup(
    categories: [
      Category("Work", categories.Productive, ""),
      Category("Media", categories.Distracting, ""),
      Category("Work > Office", categories.Productive, ""),
      ..builtins()
    ],
    rules: [
      Rule(1, "Work", "inkpad", True, []),
      Rule(2, "Media", "youtube", False, []),
      Rule(3, "Work > Office", "Teams", False, ["work-laptop"]),
    ],
    assigned: dict.from_list([#("skat", "Work"), #("gone.app", "Deleted")]),
    types: dict.from_list([#("some game", "game"), #("trainapp", "maps")]),
  )
}

fn category(device, app, title, site) {
  categories.categorizer(setup())(device, app, title, site).category
}

pub fn assigned_wins_test() {
  // known as a game, but assigned, in any case
  let m = categories.categorizer(setup())("phone", "Skat", "pkg.skat", "")
  assert m.category == "Work"
  assert m.source == categories.Assigned
  // an assignment to a category that doesn't exist doesn't count
  assert category("pc", "gone.app", "", "") == "Uncategorized"
}

pub fn rules_test() {
  // rules match the title, the deepest wins, case only when told
  assert category("pc", "de.pahlx.inkpad", "help.txt — inkpad", "") == "Work"
  assert category("pc", "mpv", "youtube", "") == "Media"
  assert category("work-laptop", "Teams", "", "") == "Work > Office"
  assert category("laptop", "Teams", "", "") == "Comms > Meetings"
}

pub fn known_test() {
  assert category("pc", "Code", "db.gleam - digitalwellbeing", "")
    == "Work > Programming"
  assert category("phone", "Element X", "io.element.android.x", "")
    == "Comms > Chat"
  assert category("phone", "FairEmail", "eu.faircode.email", "")
    == "Comms > Email"
  assert category("phone", "AntennaPod", "de.danoeh.antennapod", "")
    == "Media > Podcasts & Books"
  assert category("phone", "Firefox", "org.mozilla.firefox", "") == "Browsing"
  // music.youtube.com is Music, not Video (in another case than the rule
  // "youtube", which wins otherwise)
  assert category("pc", "Music.YouTube.com", "", "") == "Media > Music"
  // a single-word window title isn't a package
  assert category("pc", "dropbox", "Files", "") == "Uncategorized"
  // a title with spaces is no package name, the catalog doesn't look at it
  assert category("pc", "kitty", "reading the news", "") == "Work > Programming"
  assert category("pc", "unknown", "the news today", "") == "Uncategorized"
}

pub fn android_types_test() {
  let m = categories.categorizer(setup())("phone", "Some Game", "x.y", "")
  assert m.category == "Media > Games"
  assert m.source == categories.AndroidType
  assert category("phone", "TrainApp", "a.b", "") == "Navigation"
}

pub fn sites_test() {
  let categorize = categories.categorizer(setup())
  // the website decides
  let m =
    categorize("pc", "app.zen_browser.zen", "PR — Zen Browser", "github.com")
  assert m.category == "Work > Programming" && m.item == "github.com"
  // an unknown one has the browser's category, listed as itself
  let m =
    categorize("pc", "app.zen_browser.zen", "Bank — Zen Browser", "bank.de")
  assert m.category == "Browsing" && m.item == "bank.de"
  assert m.source == categories.InBrowser
  // no app name: the title stands in
  let m = categorize("pc", "", "help.txt — inkpad", "")
  assert m.item == "inkpad"
  let m = categorize("pc", "", "Untitled", "")
  assert m.item == "Untitled"
}

pub fn renamed_and_deleted_builtins_test() {
  let renamed =
    Setup(
      ..setup(),
      categories: list.map(builtins(), fn(c) {
          case c.name {
            "Comms > Chat" -> Category(..c, name: "Messages")
            _ -> c
          }
        })
        |> list.filter(fn(c) { c.name != "Browsing" }),
    )
  let categorize = categories.categorizer(renamed)
  assert categorize("phone", "Signal", "org.thoughtcrime.securesms", "").category
    == "Messages"
  assert categorize("phone", "Firefox", "org.mozilla.firefox", "").category
    == "Uncategorized"
}

pub fn invalid_regex_is_skipped_test() {
  let s = Setup(..setup(), rules: [Rule(1, "Work", "(", False, [])])
  assert categories.categorizer(s)("laptop", "(", "", "").category
    == "Uncategorized"
}

pub fn normalize_name_test() {
  assert categories.normalize_name(" Work>  Programming >")
    == "Work > Programming"
}

pub fn catalog_compiles_test() {
  let assert Ok(_) =
    list.try_each(categories.catalog, fn(entry) {
      categories.compile(entry.1, True)
    })
  // every entry is of a built-in category
  let names = list.map(categories.builtins, fn(b) { b.0 })
  assert list.all(categories.catalog, fn(entry) {
    list.contains(names, entry.0)
  })
  assert list.all(categories.android_types, fn(entry) {
    list.contains(names, entry.1)
  })
}

pub fn split_patterns_test() {
  assert categories.split_patterns("a| b |(c|d)|[|]|e\\|f|")
    == ["a", "b", "(c|d)", "[|]", "e\\|f"]
  assert categories.split_patterns("") == []
}

pub fn join_patterns_test() {
  assert categories.join_patterns(["code", " ", " vim "]) == "code|vim"
}

pub fn escape_test() {
  let assert Ok(regex) =
    categories.compile(categories.escape("x.com (1)"), False)
  let rule = Rule(1, "Social", "", False, [])
  assert categories.matches(rule, regex, "laptop", "x.com (1)", "")
  assert !categories.matches(rule, regex, "laptop", "xycom (1)", "")
}
