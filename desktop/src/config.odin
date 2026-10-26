package main

// The saved settings: the server and the look. They live in
// $XDG_CONFIG_HOME/digitalwellbeing/desktop.json, readable only by the user (it holds the token).

import "core:encoding/json"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "lib:kiln"

Server :: struct {
	url:   string, // "" while no server is set up
	token: string,
}

Config :: struct {
	server: Server,
	flavor: kiln.Flavor,
}

config_path :: proc(allocator := context.allocator) -> string {
	dir, err := os.user_config_dir(context.temp_allocator)
	if err != nil {return ""}
	path, _ := filepath.join({dir, "digitalwellbeing", "desktop.json"}, allocator)
	return path
}

// The saved config, or the defaults if there is none. Strings are allocated.
load_config :: proc() -> Config {
	path := config_path(context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {return {}}
	cfg: Config
	if json.unmarshal(data, &cfg) != nil {return {}}
	return cfg
}

save_config :: proc(cfg: Config) -> bool {
	path := config_path(context.temp_allocator)
	if len(path) == 0 {return false}
	os.make_directory_all(filepath.dir(path))
	data, err := json.marshal(cfg, {pretty = true}, context.temp_allocator)
	if err != nil {return false}
	return os.write_entire_file(path, data, perm = {.Read_User, .Write_User}) == nil
}

// Whether `url` looks like a server address.
valid_url :: proc(url: string) -> bool {
	for scheme in ([]string{"https://", "http://"}) {
		if strings.has_prefix(url, scheme) && len(url) > len(scheme) {return true}
	}
	return false
}
