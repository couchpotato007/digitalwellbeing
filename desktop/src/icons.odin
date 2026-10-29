package main

// The app's icons: SVG files in icons/, compiled into the binary. The menu and arrow icons are
// kiln's built-in ones.

import "lib:kiln"

ICON_LOGO :: kiln.Icon{svg = #load("icons/logo.svg", string)}
ICON_OVERVIEW :: kiln.Icon{svg = #load("icons/overview.svg", string)}
ICON_SETTINGS :: kiln.Icon{svg = #load("icons/settings.svg", string)}
ICON_REFRESH :: kiln.Icon{svg = #load("icons/refresh.svg", string)}
