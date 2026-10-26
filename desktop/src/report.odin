package main

// What the server's dashboard shows, from `GET /api/stats` (see server/src/stats.gleam), and
// helpers to format it.

import "core:encoding/json"
import "core:fmt"
import "core:mem/virtual"
import "core:strings"
import "lib:kiln"

Report :: struct {
	date:               string,
	first_date:         string,
	days:               int,
	device:             string, // "" is all devices
	previous_date:      string,
	next_date:          string,
	today:              string,
	total_ms:           i64,
	previous_ms:        i64,
	sessions:           int,
	longest_session_ms: i64,
	first_active:       string, // local time like "07:45", "" if there was no screen time
	last_active:        string,
	timeline:           []Usage, // per hour ("07") for one day, otherwise per day ("2026-10-26", detail is the weekday)
	hours:              []Usage, // per hour of the day, summed over all days
	strips:             []Strip, // per device for one day, otherwise per day
	category_order:     []string, // top-level categories, the index picks the color
	device_names:       []string,
	device_os:          map[string]string, // like "NixOS 25.05 (Warbler)", missing if unknown
	devices:            []Usage, // detail is the OS and when the device was last active
	categories:         []Usage,
	apps:               []Usage,
	titles:             []Usage,
	domains:            []Usage,
}

Usage :: struct {
	name:   string,
	detail: string,
	ms:     i64,
}

// A row of the activity view. `date` is set for rows of a day, "" for rows of a device.
Strip :: struct {
	label:    string,
	date:     string,
	start_ms: i64,
	end_ms:   i64,
	segments: []Segment,
}

Segment :: struct {
	start_ms: i64,
	end_ms:   i64,
	device:   string,
	category: string,
}

// What a block of the activity view was made of, from `GET /api/block`.
Block :: struct {
	apps:   []Usage,
	titles: []Usage,
}

// A value parsed from JSON together with the arena that holds its strings and slices.
Parsed :: struct($T: typeid) {
	value: T,
	arena: virtual.Arena,
}

parse :: proc($T: typeid, body: string) -> (p: ^Parsed(T), ok: bool) {
	p = new(Parsed(T))
	if virtual.arena_init_growing(&p.arena) != nil {
		free(p)
		return nil, false
	}
	err := json.unmarshal(transmute([]u8)body, &p.value, allocator = virtual.arena_allocator(&p.arena))
	if err != nil {
		destroy_parsed(p)
		return nil, false
	}
	return p, true
}

destroy_parsed :: proc(p: ^Parsed($T)) {
	if p == nil {return}
	virtual.arena_destroy(&p.arena)
	free(p)
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

// "3h 12m", "12m" or "40s", like the web dashboard.
duration :: proc(ms: i64) -> string {
	minutes := ms / 60_000
	switch {
	case minutes == 0:
		return fmt.tprintf("%ds", ms / 1000)
	case minutes < 60:
		return fmt.tprintf("%dm", minutes)
	}
	return fmt.tprintf("%dh %dm", minutes / 60, minutes % 60)
}

// Milliseconds since the start of a day as "07:45".
clock :: proc(ms: i64) -> string {
	minutes := max(ms, 0) / 60_000
	return fmt.tprintf("%02d:%02d", minutes / 60, minutes % 60)
}

// "NixOS 25.05 (Warbler)" -> "NixOS"
os_name :: proc(os: string) -> string {
	if i := strings.index_byte(os, ' '); i >= 0 {return os[:i]}
	return os
}

// "Work > Programming" -> "Work"
top_level :: proc(category: string) -> string {
	if i := strings.index(category, " > "); i >= 0 {return category[:i]}
	return category
}

// A device with its OS, "laptop · NixOS".
device_label :: proc(r: ^Report, name: string) -> string {
	if os, ok := r.device_os[name]; ok {return fmt.tprintf("%s · %s", name, os_name(os))}
	return name
}

// ---------------------------------------------------------------------------
// Dates (the server sends "2026-10-26")
// ---------------------------------------------------------------------------

WEEKDAY_NAMES := [7]string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}

// "Oct", from the theme's locale.
month_short :: proc(month: int) -> string {
	name := kiln.theme().locale.months[month - 1]
	return name[:min(3, len(name))]
}

// "Mon, 26 Oct 2026", or the input if it is no date.
long_date :: proc(s: string) -> string {
	d, ok := kiln.date_parse(s)
	if !ok {return s}
	return fmt.tprintf("%s, %d %s %d", WEEKDAY_NAMES[kiln.date_weekday(d)], d.day, month_short(d.month), d.year)
}

// "26 Oct"
short_date :: proc(s: string) -> string {
	d, ok := kiln.date_parse(s)
	if !ok {return s}
	return fmt.tprintf("%d %s", d.day, month_short(d.month))
}

// "Mon, 26 Oct 2026" or "20 Oct – 26 Oct 2026"
period :: proc(r: ^Report) -> string {
	if r.days == 1 {return long_date(r.date)}
	d, ok := kiln.date_parse(r.date)
	if !ok {return fmt.tprintf("%s – %s", r.first_date, r.date)}
	return fmt.tprintf("%s – %s %d", short_date(r.first_date), short_date(r.date), d.year)
}

// The color of a category: the theme's chart color of its top level, gray from the 9th on.
category_color :: proc(order: []string, category: string) -> kiln.Color {
	top := top_level(category)
	for name, i in order {
		if name == top {return kiln.chart_color(i)}
	}
	return kiln.chart_color(-1)
}
