import categories.{Rule}
import gleam/list

const rules = [
  Rule(1, "Work", "code|terminal", True, []),
  Rule(2, "Work > Programming", "github", True, []),
  Rule(3, "Media", "youtube", False, []),
  Rule(4, "Work > Office", "Teams", False, ["work-laptop"]),
]

pub fn deepest_match_wins_test() {
  let category = categories.categorizer(rules)
  assert category("laptop", "Code", "server.gleam") == "Work"
  assert category("laptop", "firefox", "Pull requests · GitHub")
    == "Work > Programming"
  assert category("laptop", "firefox", "news") == "Uncategorized"
}

pub fn ignore_case_test() {
  let category = categories.categorizer(rules)
  assert category("laptop", "firefox", "YouTube") == "Uncategorized"
  assert category("laptop", "firefox", "youtube") == "Media"
}

pub fn devices_test() {
  let category = categories.categorizer(rules)
  assert category("work-laptop", "Teams", "") == "Work > Office"
  assert category("laptop", "Teams", "") == "Uncategorized"
}

pub fn invalid_regex_is_skipped_test() {
  let category = categories.categorizer([Rule(1, "Broken", "(", False, [])])
  assert category("laptop", "(", "") == "Uncategorized"
}

pub fn normalize_name_test() {
  assert categories.normalize_name(" Work>  Programming >")
    == "Work > Programming"
}

pub fn defaults_compile_test() {
  let assert Ok(_) =
    list.try_each(categories.defaults, fn(rule) {
      categories.compile(rule.regex, rule.ignore_case)
    })
}

pub fn defaults_test() {
  let category = categories.categorizer(categories.defaults)
  assert category("laptop", "Code", "db.gleam - digitalwellbeing")
    == "Work > Programming"
  assert category("laptop", "github.com", "Pull requests")
    == "Work > Programming"
  assert category("laptop", "Signal", "Signal") == "Comms > Chat"
  assert category("laptop", "music.youtube.com", "Liked music")
    == "Media > Music"
  assert category("laptop", "youtube.com", "Some video") == "Media > Video"
  assert category("laptop", "x.com", "Home") == "Media > Social Media"
  assert category("laptop", "dropbox.com", "Files") == "Uncategorized"
  assert category("laptop", "firefox", "A complex football story")
    == "Uncategorized"
}

pub fn split_patterns_test() {
  assert categories.split_patterns("a| b |(c|d)|[|]|e\\|f|")
    == ["a", "b", "(c|d)", "[|]", "e\\|f"]
  assert categories.split_patterns("") == []
}

pub fn join_patterns_test() {
  assert categories.join_patterns(["code", " ", " vim "]) == "code|vim"
}

pub fn defaults_split_and_join_test() {
  list.each(categories.defaults, fn(rule) {
    assert categories.join_patterns(categories.split_patterns(rule.regex))
      == rule.regex
  })
}

pub fn escape_test() {
  let assert Ok(regex) =
    categories.compile(categories.escape("x.com (1)"), False)
  let rule = Rule(1, "Social", "", False, [])
  assert categories.matches(rule, regex, "laptop", "x.com (1)", "")
  assert !categories.matches(rule, regex, "laptop", "xycom (1)", "")
}
