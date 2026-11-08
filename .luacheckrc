std = "lua54"

-- Globals the RS3 client provides to plugins.
read_globals = {
  "Event", "GameKey", "Inventory", "Mouse", "NPCList", "PersistentDB", "Player", "config", "id", "log", "prettyui",
  "ui", "var",
}

-- Lifecycle hooks the client calls by name.
globals = { "PluginShutdown" }

files["spec"] = { std = "+busted" }
-- .lua and .luarocks hold the toolchain CI installs into the checkout.
exclude_files = { ".scratch", ".lua", ".luarocks" }
-- Catalog data keeps one row per line, so its struct descriptions run past the line limit.
files["src/catalog.lua"] = { max_line_length = false }
