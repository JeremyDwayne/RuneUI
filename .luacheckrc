std = "lua54"

-- Globals the RS3 client provides to plugins.
read_globals = {
  "Event", "GameKey", "Inventory", "Mouse", "NPCList", "PersistentDB", "Player", "PlayerList", "ScreenConvert",
  "Vector3", "config", "id", "log",
  "prettyui", "ui", "var",
}

-- Lifecycle hooks the client calls by name.
globals = { "PluginShutdown" }

files["spec"] = { std = "+busted" }
-- .lua and .luarocks hold the toolchain CI installs into the checkout.
exclude_files = { ".scratch", ".lua", ".luarocks" }
-- Catalog data keeps one row per line, so its struct descriptions and frame statics run past the line limit.
files["src/catalog.lua"] = { max_line_length = false }
files["src/windowframes.lua"] = { max_line_length = false }
