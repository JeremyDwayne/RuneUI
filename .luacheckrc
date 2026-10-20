std = "lua54"

-- Globals the RS3 client provides to plugins.
read_globals = {
  "Event", "GameKey", "Inventory", "Keyboard", "Mouse", "NPCList", "PersistentDB", "Player", "PlayerList",
  "SkillType", "Vector4", "config", "formatStr", "id", "log", "ui", "var",
}

-- Lifecycle hooks the client calls by name.
globals = { "PluginShutdown" }

files["spec"] = { std = "+busted" }
exclude_files = { ".scratch" }
