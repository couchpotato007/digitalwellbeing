#!/data/data/com.termux/files/usr/bin/sh
# The agent for Android, as a shell script for Termux (needs `pkg install curl jq`).
# Does one sync like agent/: asks the server where it left off, queries the
# ActivityWatch app for the app usage since then and uploads it.
# Schedule it with termux-job-scheduler, see README.md.
set -eu

# termux-job-scheduler starts scripts without our environment
config=${WELLBEING_CONFIG:-$HOME/.config/digitalwellbeing.env}
[ -f "$config" ] && . "$config"
: "${SERVER_URL:?}" "${TOKEN:?}" "${DEVICE:?}"
aw=${ACTIVITYWATCH_URL:-http://localhost:5600}
device_url="$SERVER_URL/api/devices/$DEVICE"

server() {
  curl -fsS -H "Authorization: Bearer $TOKEN" -H "content-type: application/json" "$@"
}

# Same as agent/: 30 days on the first sync, afterwards the last 10 minutes
# again because ActivityWatch still corrects them.
cursor=$(server "$device_url/cursor" | jq .cursor_ms)
now_ms=$(($(date +%s) * 1000))
if [ "$cursor" -eq 0 ]; then
  from_ms=$((now_ms - 30 * 86400000))
else
  from_ms=$((cursor - 600000))
fi

bucket=$(curl -fsS "$aw/api/0/buckets/" | jq -r '
  to_entries | map(select(.value.type == "currentwindow"
    and (.key | contains("synced-from") | not)))
  | first.key // empty')
[ -n "$bucket" ] || { echo "ActivityWatch has no window/app bucket" >&2; exit 1; }

# The regex categories from the ActivityWatch settings, as `categorize` takes them
categories=$({ curl -fsS "$aw/api/0/settings/classes" || echo '[]'; } | jq -c '
  map(select(.rule.type == "regex" and (.rule.regex // "") != "")
    | [.name, {type: "regex", regex: .rule.regex, ignore_case: (.rule.ignore_case // false)}])')

events=$(jq -nc --arg bucket "$bucket" --argjson categories "$categories" \
  --argjson from "$from_ms" --argjson to "$now_ms" '{
    timeperiods: ["\($from / 1000 | floor | todate)/\($to / 1000 | floor | todate)"],
    query: ["window = flood(query_bucket(\($bucket | tojson))); RETURN = categorize(window, \($categories | tojson));"]
  }' | curl -fsS -H "content-type: application/json" --data-binary @- "$aw/api/0/query/")

# ActivityWatch timestamps are UTC, like 2026-10-26T12:00:00.123+00:00
echo "$events" | jq -c --argjson from "$from_ms" '
  def ms: (.[0:19] + "Z" | fromdateiso8601) * 1000
    + ((capture("\\.(?<f>[0-9]+)").f // "0") + "00" | .[0:3] | tonumber);
  {from_ms: $from, events: [.[][] | {
    kind: "window",
    start_ms: (.timestamp | ms),
    duration_ms: (.duration * 1000 | round),
    app: (.data.app // "unknown"),
    title: (.data.title // ""),
    category: ((.data["$category"] // ["Uncategorized"]) | join(" > "))
  } | select(.duration_ms > 0)]}' |
  server --data-binary @- "$device_url/events"

echo "Synced $DEVICE to $SERVER_URL"
