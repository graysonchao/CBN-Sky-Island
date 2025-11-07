-- Sky Islands BN Port - Proof of Concept
-- preload.lua - Hook and iuse registration

local mod = game.mod_runtime[game.current_mod]

-- Register item use functions
game.iuse_functions["SKYISLAND_WARP_OBELISK"] = function(...)
  return mod.use_warp_obelisk(...)
end

game.iuse_functions["SKYISLAND_RETURN_OBELISK"] = function(...)
  return mod.use_return_obelisk(...)
end

game.iuse_functions["SKYISLAND_HEART_MENU"] = function(...)
  return mod.use_heart_menu(...)
end

-- Register hooks
table.insert(game.hooks.on_game_started, function(...)
  return mod.on_game_started(...)
end)

table.insert(game.hooks.on_game_load, function(...)
  return mod.on_game_load(...)
end)

table.insert(game.hooks.on_game_save, function(...)
  return mod.on_game_save(...)
end)

table.insert(game.hooks.on_char_death, function(...)
  return mod.on_char_death(...)
end)

table.insert(game.hooks.on_character_death, function(...)
  return mod.on_character_death(...)
end)

gdebug.log_info("Sky Islands PoC preload complete")
