package main

// The overview: screen time of all devices for a day, a week or 30 days, like the server's
// dashboard and the Android app.

import "core:fmt"
import "lib:kiln"

Dashboard :: struct {
	// What is shown: "" is today / all devices.
	date:          string,
	days:          int,
	device:        string,
	report:        ^Parsed(Report),
	loading:       bool,
	error:         string,
	gen:           int,

	// The block of the activity view whose apps are shown in the dialog.
	block:         ^Parsed(Block),
	block_title:   string,
	block_detail:  string,
	block_loading: bool,
	block_error:   string,
	block_gen:     int,
}

RANGES := [?]string{"Day", "Week", "30 days"}
RANGE_DAYS := [?]int{1, 7, 30}
HOURS := [?]string{"0", "6", "12", "18", "24"}

Set_Days :: struct {
	days: int,
}
Set_Date :: struct {
	date: string,
}
Set_Device :: struct {
	device: string,
}
Refresh :: struct {}
Open_Block :: struct {
	strip, segment: int,
}
Open_Settings :: struct {}

Dashboard_Msg :: union {
	Set_Days,
	Set_Date,
	Set_Device,
	Refresh,
	Open_Block,
	Open_Settings,
}

dashboard_init :: proc(d: ^Dashboard) {
	d.days = 1
}

// Asks the server for the report of the current selection.
reload :: proc(d: ^Dashboard, server: Server) {
	when FIXTURE != "" {return}
	if len(server.url) == 0 {return}
	d.gen += 1
	d.loading = true
	path := fmt.tprintf("/api/stats?date=%s&days=%d&device=%s", url_encode(d.date), d.days, url_encode(d.device))
	api_get(server, .Stats, d.gen, path)
}

// Forgets the report, e.g. when the server changed.
dashboard_reset :: proc(d: ^Dashboard, server: Server) {
	destroy_parsed(d.report)
	d.report = nil
	d.loading = false
	set_string(&d.error, "")
	set_string(&d.device, "")
	reload(d, server)
}

dashboard_update :: proc(d: ^Dashboard, server: Server, msg: Dashboard_Msg) {
	switch v in msg {
	case Set_Days:
		d.days = v.days
	case Set_Date:
		set_string(&d.date, v.date)
	case Set_Device:
		set_string(&d.device, v.device)
	case Refresh:
	case Open_Block:
		open_block(d, server, v)
		return
	case Open_Settings:
		return
	}
	reload(d, server)
}

dashboard_receive :: proc(d: ^Dashboard, r: Response) {
	defer response_destroy(r)
	switch r.kind {
	case .Stats:
		if r.gen != d.gen {return}
		d.loading = false
		if e := describe(r); len(e) > 0 {
			set_string(&d.error, e)
			return
		}
		p, ok := parse(Report, r.body)
		if !ok {
			set_string(&d.error, "The server sent something that is not a report")
			return
		}
		destroy_parsed(d.report)
		d.report = p
		d.days = p.value.days // the server decides, e.g. for unknown ranges
		set_string(&d.error, "")
	case .Block:
		if r.gen != d.block_gen {return}
		d.block_loading = false
		if e := describe(r); len(e) > 0 {
			set_string(&d.block_error, e)
			return
		}
		p, ok := parse(Block, r.body)
		if !ok {
			set_string(&d.block_error, "The server sent something unexpected")
			return
		}
		destroy_parsed(d.block)
		d.block = p
	case .Test:
	}
}

@(private = "file")
open_block :: proc(d: ^Dashboard, server: Server, v: Open_Block) {
	if d.report == nil {return}
	r := &d.report.value
	strip := r.strips[v.strip]
	seg := strip.segments[v.segment]
	// rows of a day are per device, older servers send no device with the segment
	device := seg.device
	if len(device) == 0 && len(strip.date) == 0 {device = strip.label}

	destroy_parsed(d.block)
	d.block = nil
	set_string(&d.block_error, "")
	set_string(&d.block_title, seg.category)
	date := len(strip.date) > 0 ? strip.date : r.date
	set_string(
		&d.block_detail,
		fmt.tprintf(
			"%s · %s, %s–%s",
			len(device) > 0 ? device : "all devices",
			short_date(date),
			clock(seg.start_ms - strip.start_ms),
			clock(seg.end_ms - strip.start_ms),
		),
	)
	d.block_gen += 1
	d.block_loading = true
	when FIXTURE == "" {
		path := fmt.tprintf(
			"/api/block?device=%s&category=%s&since_ms=%d&until_ms=%d",
			url_encode(device),
			url_encode(seg.category),
			seg.start_ms,
			seg.end_ms,
		)
		api_get(server, .Block, d.block_gen, path)
	}
}

// ---------------------------------------------------------------------------
// View
// ---------------------------------------------------------------------------

dashboard_view :: proc(m: ^Model, out: ^[dynamic]Dashboard_Msg) {
	d := &m.dashboard

	if d.report == nil && len(m.config.server.url) == 0 && FIXTURE == "" {
		if kiln.empty_state("No server yet", "Add your wellbeing server to see the screen time of all your devices.") {
			if kiln.button("Open settings") {append(out, Open_Settings{})}
		}
		return
	}

	if kiln.every("refresh", REFRESH_SECONDS) && !d.loading {append(out, Refresh{})}

	controls(d, out)

	if len(d.error) > 0 {
		if kiln.callout(.Danger, "Could not load the dashboard") {
			kiln.text(d.error)
			if kiln.button("Retry", .Secondary) {append(out, Refresh{})}
		}
	}

	if d.report == nil {
		if d.loading {
			if kiln.row() {
				kiln.spinner()
				kiln.text("Loading ...", .Body, .Muted)
			}
		}
		return
	}
	r := &d.report.value

	summary(r)

	if kiln.adaptive(900) {
		if kiln.card(r.days == 1 ? "Per hour" : "Per day · click a day to open it") {
			if i, ok := time_chart(r.timeline, r.today, 200); ok && is_day(r.timeline[i]) {
				append(out, Set_Days{1})
				append(out, Set_Date{r.timeline[i].name})
			}
		}
		if kiln.column(.MD, width = 360) {
			category_card(r)
		}
	}

	if len(r.strips) > 0 {
		if kiln.card(r.days == 1 ? "Activity per device · click a block for its apps" : "Activity per day · click a block for its apps") {
			activity(r, out)
		}
	}

	if r.days > 1 {
		if kiln.card("By hour of day · average per day") {
			hours := make([]Usage, len(r.hours), context.temp_allocator)
			for h, i in r.hours {hours[i] = {h.name, h.detail, h.ms / i64(r.days)}}
			time_chart(hours, height = 120)
		}
	}

	if kiln.grid(380) {
		usage_card("Apps", r.apps)
		usage_card("Window titles", r.titles)
		usage_card("Browser domains", r.domains)
		if len(r.device) == 0 {usage_card("Devices · last active", r.devices)}
	}

	block_dialog(d)
}

// Range, date and device.
@(private = "file")
controls :: proc(d: ^Dashboard, out: ^[dynamic]Dashboard_Msg) {
	compact := kiln.screen() == .Compact
	selected := 0
	for days, i in RANGE_DAYS {if days == d.days {selected = i}}

	if kiln.adaptive(900) {
		if kiln.row(.SM) {
			if i, ok := kiln.segmented(selected, RANGES[:], fill = compact); ok {
				append(out, Set_Days{RANGE_DAYS[i]})
			}
		}
		if d.report != nil {
			r := &d.report.value
			shown, _ := kiln.date_parse(r.date)
			today, _ := kiln.date_parse(r.today)
			if kiln.row(.XS) {
				if kiln.button("‹", .Ghost) {append(out, Set_Date{r.previous_date})}
				kiln.tooltip("Earlier")
				if kiln.column(.None, width = compact ? 0 : 180) {
					if day, ok := kiln.date_field(shown, max = today, key = "date"); ok {
						append(out, Set_Date{kiln.date_format(day)})
					}
				}
				if kiln.button("›", .Ghost, disabled = r.date >= r.today) {append(out, Set_Date{r.next_date})}
				kiln.tooltip("Later")
				if kiln.button("Today", .Secondary, disabled = r.date == r.today) {append(out, Set_Date{""})}
				reload_button(d, out)
			}
		} else {
			reload_button(d, out)
		}
	}

	if d.report == nil {return}
	r := &d.report.value
	if len(r.device_names) > 1 {
		labels := make([]string, len(r.device_names) + 1, context.temp_allocator)
		labels[0] = "All devices"
		current := 0
		for name, i in r.device_names {
			labels[i + 1] = device_label(r, name)
			if name == d.device {current = i + 1}
		}
		if i, ok := kiln.chips(current, labels); ok {
			append(out, Set_Device{i == 0 ? "" : r.device_names[i - 1]})
		}
	}
}

@(private = "file")
reload_button :: proc(d: ^Dashboard, out: ^[dynamic]Dashboard_Msg) {
	if kiln.button("↻", .Ghost, disabled = d.loading) {append(out, Refresh{})}
	kiln.tooltip("Reload")
	if d.loading {kiln.spinner()}
}

@(private = "file")
summary :: proc(r: ^Report) {
	before: string
	switch r.days {
	case 1:
		before = "the day before"
	case 7:
		before = "the week before"
	case:
		before = fmt.tprintf("the %d days before", r.days)
	}

	change := ""
	tone := kiln.Tone.Default
	if r.previous_ms > 0 {
		percent := (r.total_ms - r.previous_ms) * 100 / r.previous_ms
		switch {
		case percent > 0:
			change, tone = fmt.tprintf("↑ %d%%", percent), .Warning
		case percent < 0:
			change, tone = fmt.tprintf("↓ %d%%", -percent), .Success
		case:
			change = "±0%"
		}
	}

	device := len(r.device) > 0 ? r.device : "All devices"
	if os, ok := r.device_os[r.device]; ok {device = fmt.tprintf("%s · %s", r.device, os)}

	if kiln.card() {
		if kiln.adaptive(700, .LG) {
			if kiln.column(.XS, width = 280) {
				kiln.stat(
					"Screen time",
					duration(r.total_ms),
					note = fmt.tprintf("vs. %s (%s)", before, duration(r.previous_ms)),
					delta = change,
					delta_tone = tone,
					large = true,
				)
				kiln.text(fmt.tprintf("%s · %s", device, period(r)), .Caption, .Muted)
			}
			if kiln.grid(140, .MD) {
				if r.days > 1 {kiln.stat("Daily average", duration(r.total_ms / i64(r.days)))}
				kiln.stat("Sessions", fmt.tprint(r.sessions), note = "breaks of 5+ min")
				kiln.stat("Longest session", duration(r.longest_session_ms))
				if r.days == 1 {
					kiln.stat("First active", len(r.first_active) > 0 ? r.first_active : "–")
					kiln.stat("Last active", len(r.last_active) > 0 ? r.last_active : "–")
				} else {
					busiest := -1
					for b, i in r.timeline {
						if b.ms > 0 && (busiest < 0 || b.ms > r.timeline[busiest].ms) {busiest = i}
					}
					if busiest >= 0 {
						b := r.timeline[busiest]
						kiln.stat("Busiest day", fmt.tprintf("%s %s", b.detail, short_date(b.name)), note = duration(b.ms))
					} else {
						kiln.stat("Busiest day", "–")
					}
				}
			}
		}
	}
}

// Bars per hour ("07") or day ("2026-10-26"), `today` highlighted. Returns a clicked bar.
@(private = "file")
time_chart :: proc(buckets: []Usage, today := "", height: f32 = 150) -> (int, bool) {
	if len(buckets) == 0 {
		kiln.text("No screen time", .Body, .Muted)
		return -1, false
	}
	values := make([]f32, len(buckets), context.temp_allocator)
	labels := make([]string, len(buckets), context.temp_allocator)
	highlight := -1
	for b, i in buckets {
		values[i] = f32(b.ms) / 60_000
		switch {
		case !is_day(b):
			labels[i] = b.name
		case len(buckets) <= 7:
			labels[i] = fmt.tprintf("%s %s", b.detail, b.name[8:])
		case:
			labels[i] = b.name[8:]
		}
		if len(today) > 0 && b.name == today {highlight = i}
	}
	minutes :: proc(v: f32) -> string {return duration(i64(v * 60_000))}
	return kiln.bar_chart(values, labels, height = height, format = minutes, highlight = highlight, value_axis = true)
}

// Buckets of days are named like "2026-10-26", buckets of hours like "07".
is_day :: proc(b: Usage) -> bool {
	return len(b.name) == 10
}

// When which category was used, a row per device (one day) or per day.
@(private = "file")
activity :: proc(r: ^Report, out: ^[dynamic]Dashboard_Msg) {
	rows := make([]kiln.Timeline_Row, len(r.strips), context.temp_allocator)
	shown := make(map[string]bool, allocator = context.temp_allocator)
	for strip, i in r.strips {
		segments := make([]kiln.Timeline_Segment, len(strip.segments), context.temp_allocator)
		for seg, j in strip.segments {
			shown[top_level(seg.category)] = true
			segments[j] = {
				start   = f64(seg.start_ms),
				end     = f64(seg.end_ms),
				color   = category_color(r.category_order, seg.category),
				tooltip = fmt.tprintf(
					"%s · %s%s%s–%s (%s)",
					seg.category,
					seg.device,
					len(seg.device) > 0 ? " · " : "",
					clock(seg.start_ms - strip.start_ms),
					clock(seg.end_ms - strip.start_ms),
					duration(seg.end_ms - seg.start_ms),
				),
			}
		}
		rows[i] = {strip.label, f64(strip.start_ms), f64(strip.end_ms), segments}
	}

	if row, segment, ok := kiln.timeline(rows, HOURS[:]); ok {
		switch {
		case segment >= 0:
			append(out, Open_Block{row, segment})
			kiln.show("block")
		case len(r.strips[row].date) > 0:
			append(out, Set_Days{1})
			append(out, Set_Date{r.strips[row].date})
		}
	}

	// The top-level categories in the rows, in the order of the rules, then the others.
	items := make([dynamic]kiln.Legend_Item, context.temp_allocator)
	for name in r.category_order {
		if shown[name] {
			append(&items, kiln.Legend_Item{name, category_color(r.category_order, name)})
			delete_key(&shown, name)
		}
	}
	for name in shown {append(&items, kiln.Legend_Item{name, category_color(r.category_order, name)})}
	kiln.legend(items[:])
}

@(private = "file")
category_card :: proc(r: ^Report) {
	if kiln.card("Categories") {
		if len(r.categories) == 0 {
			kiln.text("Nothing yet", .Body, .Muted)
			return
		}
		total: i64 = 0
		top: i64 = 1
		for c in r.categories {
			total += c.ms
			top = max(top, c.ms)
		}
		for c in r.categories {
			color := category_color(r.category_order, c.name)
			if kiln.column(.XS) {
				if kiln.row(.SM) {
					kiln.swatch(color)
					kiln.text(c.name, ellipsis = true)
					kiln.spacer()
					kiln.text(fmt.tprintf("%d%%", c.ms * 100 / max(total, 1)), .Caption, .Faint)
					kiln.text(duration(c.ms))
				}
				kiln.progress(f32(c.ms) / f32(top), color = color, thin = true)
			}
		}
	}
}

USAGE_SHOWN :: 8

@(private = "file")
usage_card :: proc(title: string, items: []Usage) {
	if len(items) == 0 {return}
	if kiln.card(title) {
		top: i64 = 1
		for it in items {top = max(top, it.ms)}
		for it in items[:min(len(items), USAGE_SHOWN)] {usage_row(it, top)}
		if len(items) > USAGE_SHOWN {
			if kiln.collapsible(fmt.tprintf("%d more", len(items) - USAGE_SHOWN)) {
				for it in items[USAGE_SHOWN:] {usage_row(it, top)}
			}
		}
	}
}

@(private = "file")
usage_row :: proc(it: Usage, top: i64) {
	if kiln.column(.XS) {
		if kiln.row(.SM) {
			if kiln.column(.None) {
				kiln.text(len(it.name) > 0 ? it.name : "(no title)", ellipsis = true)
				if len(it.detail) > 0 {kiln.text(it.detail, .Caption, .Muted, ellipsis = true)}
			}
			kiln.text(duration(it.ms))
		}
		kiln.progress(f32(it.ms) / f32(top), thin = true)
	}
}

// The apps and titles of a block of the activity view.
@(private = "file")
block_dialog :: proc(d: ^Dashboard) {
	if kiln.dialog("block", d.block_title) {
		kiln.text(d.block_detail, .Caption, .Muted)
		switch {
		case d.block_loading:
			if kiln.row() {
				kiln.spinner()
				kiln.text("Loading ...", .Body, .Muted)
			}
		case len(d.block_error) > 0:
			if kiln.callout(.Danger) {kiln.text(d.block_error)}
		case d.block != nil:
			b := &d.block.value
			top: i64 = 1
			for it in b.apps {top = max(top, it.ms)}
			for it in b.titles {top = max(top, it.ms)}
			if len(b.apps) > 0 {kiln.text("Apps", .Subtitle)}
			for it in b.apps {usage_row(it, top)}
			if len(b.titles) > 0 {kiln.text("Window titles", .Subtitle)}
			for it in b.titles {usage_row(it, top)}
			if len(b.apps) == 0 && len(b.titles) == 0 {kiln.text("Nothing recorded", .Body, .Muted)}
		}
		if kiln.actions() {
			if kiln.button("Close", .Secondary) {kiln.hide()}
		}
	}
}
