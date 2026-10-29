package main

// Desktop app for the wellbeing server: the dashboard of all devices and the server settings.
// One Elm-style model; requests to the server are kiln tasks whose answers (`Response`) come
// back through `update`.
//
//   cd desktop && odin run src -collection:lib=external/kiln
//   odin run src -collection:lib=external/kiln -define:KILN_SNAPSHOT=true -define:FIXTURE=stats.json

import "core:os"
import "core:strings"
import "lib:kiln"

// For snapshots: a saved `/api/stats` answer to show instead of asking the server.
FIXTURE :: #config(FIXTURE, "")
// First page shown (index into `Page`), handy for snapshots.
START_PAGE :: #config(START_PAGE, 0)
// For snapshots: a dialog to render as well ("jump", "block", "remove").
SNAPSHOT_OPEN :: #config(SNAPSHOT_OPEN, "")

// The dashboard reloads itself this often while it is shown, in seconds.
REFRESH_SECONDS :: 300

Page :: enum {
	Overview,
	Settings,
}

PAGES := [Page]kiln.NavItem {
	.Overview = {ICON_OVERVIEW, "Overview"},
	.Settings = {ICON_SETTINGS, "Settings"},
}

SIDEBAR_WIDTH :: 220
RAIL_WIDTH :: 64
CONTENT_MAX_WIDTH :: 1280

Model :: struct {
	page:      Page,
	config:    Config, // what is saved
	dashboard: Dashboard,
	settings:  Settings,
}

Go_To :: struct {
	page: Page,
}

Msg :: union {
	Go_To,
	Response,
	Dashboard_Msg,
	Settings_Msg,
}

init :: proc() -> Model {
	m := Model {
		page   = Page(START_PAGE),
		config = load_config(),
	}
	kiln.set_colors(kiln.catppuccin(m.config.flavor).colors)
	dashboard_init(&m.dashboard)
	settings_init(&m.settings, m.config)

	if len(m.config.server.url) > 0 {
		reload(&m.dashboard, m.config.server)
	} else if FIXTURE == "" {
		m.page = .Settings
	}
	return m
}

update :: proc(m: ^Model, msg: Msg) {
	switch v in msg {
	case Go_To:
		m.page = v.page
	case Response:
		switch v.kind {
		case .Stats, .Block:
			dashboard_receive(&m.dashboard, v)
		case .Test:
			settings_receive(&m.settings, v)
		}
	case Dashboard_Msg:
		if _, ok := v.(Open_Settings); ok {
			m.page = .Settings
			return
		}
		dashboard_update(&m.dashboard, m.config.server, v)
	case Settings_Msg:
		settings_update(m, v)
	}
}

view :: proc(m: ^Model, out: ^[dynamic]Msg) {
	screen := kiln.screen()

	if kiln.row(gap = .None, fill = .Both, align = .Start) {
		if screen != .Compact {sidebar(m, out, collapsed = screen == .Medium)}

		if kiln.column(gap = .None, fill = .Both) {
			if screen == .Compact {top_bar(m)}

			if kiln.scroll(padding = kiln.by_screen(kiln.Space.MD, .LG, .XL)) {
				if kiln.column(align = .Center) {
					if kiln.column(.LG, max_width = CONTENT_MAX_WIDTH) {
						switch m.page {
						case .Overview:
							kiln.embed(out, m, dashboard_view)
						case .Settings:
							kiln.embed(out, m, settings_view)
						}
					}
				}
			}
		}
	}

	if kiln.drawer("nav") {
		brand(collapsed = false)
		if p, ok := kiln.nav(m.page, PAGES); ok {
			append(out, Go_To{p})
			kiln.hide()
		}
	}
}

sidebar :: proc(m: ^Model, out: ^[dynamic]Msg, collapsed: bool) {
	if kiln.column(
		.SM,
		.MD,
		fill = .Height,
		width = collapsed ? RAIL_WIDTH : SIDEBAR_WIDTH,
		bg = .Sunken,
	) {
		brand(collapsed)
		if p, ok := kiln.nav(m.page, PAGES, collapsed); ok {append(out, Go_To{p})}
		kiln.spacer()
		if !collapsed {
			url := m.config.server.url
			kiln.text(len(url) > 0 ? url : "No server", .Caption, .Faint, ellipsis = true)
		}
	}
	kiln.separator()
}

brand :: proc(collapsed: bool) {
	if kiln.row(.SM, padding = .SM) {
		kiln.icon(ICON_LOGO, .Title, .Primary)
		if !collapsed {kiln.text("Wellbeing", .Title)}
	}
}

top_bar :: proc(m: ^Model) {
	if kiln.row(.SM, padding = .SM, bg = .Sunken) {
		if kiln.button(kiln.ICON_MENU, .Ghost) {kiln.show("nav")}
		kiln.text("Wellbeing", .Subtitle)
		kiln.spacer()
		kiln.badge(PAGES[m.page].label, .Primary)
	}
	kiln.separator()
}

// Replaces an allocated string of the model.
set_string :: proc(s: ^string, value: string) {
	delete(s^)
	s^ = strings.clone(value)
}

// Snapshots: show the saved report instead of asking the server.
snapshot_setup :: proc(model: rawptr) {
	if FIXTURE == "" {return}
	m := (^Model)(model)
	if data, err := os.read_entire_file(FIXTURE, context.allocator); err == nil {
		dashboard_receive(
			&m.dashboard,
			{kind = .Stats, gen = m.dashboard.gen, status = 200, body = string(data)},
		)
	}
}

main :: proc() {
	api_init()
	open := [?]string{SNAPSHOT_OPEN}
	kiln.run(
		kiln.App(Model, Msg){init = init, update = update, view = view},
		{
			title = "Wellbeing",
			width = 1280,
			height = 860,
			snapshot_setup = snapshot_setup,
			snapshot_open = len(SNAPSHOT_OPEN) > 0 ? open[:] : nil,
		},
	)
}
