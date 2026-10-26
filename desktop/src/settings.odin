package main

// The server (URL and token, with a connection test) and the look of the app.

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "lib:kiln"

FLAVOR_NAMES := [kiln.Flavor]string {
	.Mocha     = "Mocha (dark)",
	.Macchiato = "Macchiato (dark)",
	.Frappe    = "Frappé (dark)",
	.Latte     = "Latte (light)",
}

Settings :: struct {
	// The form, saved with "Save".
	url:        string,
	token:     string,
	testing:   bool,
	test_gen:  int,
	status:    string, // outcome of the last test or save, "" for none
	status_ok: bool,
}

Set_Url :: struct {
	url: string,
}
Set_Token :: struct {
	token: string,
}
Test_Connection :: struct {}
Save_Server :: struct {}
Remove_Server :: struct {}
Set_Flavor :: struct {
	flavor: kiln.Flavor,
}

Settings_Msg :: union {
	Set_Url,
	Set_Token,
	Test_Connection,
	Save_Server,
	Remove_Server,
	Set_Flavor,
}

settings_init :: proc(s: ^Settings, cfg: Config) {
	s.url = strings.clone(len(cfg.server.url) > 0 ? cfg.server.url : "https://")
	s.token = strings.clone(cfg.server.token)
}

// The server as entered in the form.
entered :: proc(s: ^Settings) -> Server {
	return {strings.trim_space(s.url), strings.trim_space(s.token)}
}

form_valid :: proc(s: ^Settings) -> bool {
	e := entered(s)
	return valid_url(e.url) && len(e.token) > 0
}

settings_update :: proc(m: ^Model, msg: Settings_Msg) {
	s := &m.settings
	switch v in msg {
	case Set_Url:
		set_string(&s.url, v.url)
		set_string(&s.status, "") // a result is only about the values it was made with
	case Set_Token:
		set_string(&s.token, v.token)
		set_string(&s.status, "")
	case Test_Connection:
		s.test_gen += 1
		s.testing = true
		set_string(&s.status, "")
		api_get(entered(s), .Test, s.test_gen, "/api/stats?days=1")
	case Save_Server:
		e := entered(s)
		set_string(&m.config.server.url, e.url)
		set_string(&m.config.server.token, e.token)
		save_settings(m, "Saved. The overview now shows this server.")
		dashboard_reset(&m.dashboard, m.config.server)
	case Remove_Server:
		set_string(&m.config.server.url, "")
		set_string(&m.config.server.token, "")
		set_string(&s.url, "https://")
		set_string(&s.token, "")
		save_settings(m, "Removed. The server keeps its data.")
		dashboard_reset(&m.dashboard, m.config.server)
	case Set_Flavor:
		m.config.flavor = v.flavor
		kiln.set_colors(kiln.catppuccin(v.flavor).colors)
		if !save_config(m.config) {kiln.toast("Could not save the settings", .Danger)}
	}
}

@(private = "file")
save_settings :: proc(m: ^Model, message: string) {
	s := &m.settings
	if save_config(m.config) {
		s.status_ok = true
		set_string(&s.status, message)
	} else {
		s.status_ok = false
		set_string(&s.status, fmt.tprintf("Could not write %s", config_path(context.temp_allocator)))
	}
}

settings_receive :: proc(s: ^Settings, r: Response) {
	defer response_destroy(r)
	if r.gen != s.test_gen {return}
	s.testing = false
	if e := describe(r); len(e) > 0 {
		s.status_ok = false
		set_string(&s.status, e)
		return
	}
	// Only the device list is of interest here.
	Devices :: struct {
		device_names: []string,
	}
	d: Devices
	if json.unmarshal(transmute([]u8)r.body, &d, allocator = context.temp_allocator) != nil {
		s.status_ok = false
		set_string(&s.status, "This answered, but is not a wellbeing server")
		return
	}
	s.status_ok = true
	switch len(d.device_names) {
	case 0:
		set_string(&s.status, "Connected. No devices have sent anything yet.")
	case:
		set_string(
			&s.status,
			fmt.tprintf(
				"Connected. %d device%s: %s",
				len(d.device_names),
				len(d.device_names) == 1 ? "" : "s",
				strings.join(d.device_names, ", ", context.temp_allocator),
			),
		)
	}
}

settings_view :: proc(m: ^Model, out: ^[dynamic]Settings_Msg) {
	s := &m.settings
	saved := m.config.server
	e := entered(s)
	valid := form_valid(s)

	if kiln.column(.XS) {
		kiln.text("Settings", .Headline)
		kiln.text("The server whose screen time is shown, and the look of the app.", .Body, .Muted)
	}

	if kiln.card("Server") {
		kiln.text(
			len(saved.url) == 0 ? "Add your wellbeing server to see the screen time of all your devices." : fmt.tprintf("Showing %s", saved.url),
			.Body,
			.Muted,
		)
		url_error := ""
		if len(e.url) > 0 && e.url != "https://" && !valid_url(e.url) {
			url_error = "Starts with https:// or http://"
		}
		if kiln.field("Server URL", "Like https://wellbeing.example.org", url_error) {
			if t, ok := kiln.text_field(s.url, "Server URL"); ok {append(out, Set_Url{t})}
		}
		if kiln.field("Token", "The server's ADMIN_TOKEN") {
			if t, ok := kiln.text_field(s.token, "Token", password = true); ok {append(out, Set_Token{t})}
			if kiln.submitted() && valid {append(out, Save_Server{})}
		}

		if len(s.status) > 0 {
			if kiln.callout(s.status_ok ? .Success : .Danger) {kiln.text(s.status)}
		}

		if kiln.actions() {
			if s.testing {kiln.spinner()}
			if len(saved.url) > 0 {
				if kiln.button("Remove server", .Ghost, tone = .Danger) {kiln.show("remove")}
			}
			if kiln.button("Test connection", .Secondary, disabled = !valid || s.testing) {
				append(out, Test_Connection{})
			}
			if kiln.button(len(saved.url) == 0 ? "Add server" : "Save", disabled = !valid || e == saved) {
				append(out, Save_Server{})
			}
		}
	}

	if kiln.card("Appearance") {
		if kiln.field("Colors", "Catppuccin flavor") {
			if f, ok := kiln.select(m.config.flavor, FLAVOR_NAMES); ok {append(out, Set_Flavor{f})}
		}
		kiln.text("Ctrl +/− changes the zoom, Ctrl 0 resets it.", .Caption, .Faint)
	}

	kiln.text(fmt.tprintf("Settings are stored in %s", config_path(context.temp_allocator)), .Caption, .Faint)

	if kiln.dialog("remove", "Remove server?") {
		kiln.text("The app forgets the server and its token. What the server already has stays there.")
		if kiln.actions() {
			if kiln.button("Cancel", .Ghost) {kiln.hide()}
			if kiln.button("Remove", .Danger) {
				append(out, Remove_Server{})
				kiln.hide()
			}
		}
	}
}
