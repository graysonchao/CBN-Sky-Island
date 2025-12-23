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

-- Upgrade item activations
game.iuse_functions["SKYISLAND_UPGRADE_STABILITY1"] = function(...)
  return mod.use_upgrade_stability1(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_STABILITY2"] = function(...)
  return mod.use_upgrade_stability2(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_STABILITY3"] = function(...)
  return mod.use_upgrade_stability3(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_SCOUTING1"] = function(...)
  return mod.use_upgrade_scouting1(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_SCOUTING2"] = function(...)
  return mod.use_upgrade_scouting2(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_EXITS1"] = function(...)
  return mod.use_upgrade_exits1(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_RAIDLENGTH1"] = function(...)
  return mod.use_upgrade_raidlength1(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_RAIDLENGTH2"] = function(...)
  return mod.use_upgrade_raidlength2(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_BASEMENTS"] = function(...)
  return mod.use_upgrade_basements(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_ROOFS"] = function(...)
  return mod.use_upgrade_roofs(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_LABS"] = function(...)
  return mod.use_upgrade_labs(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_SCOUTING_CLAIRVOYANCE1"] = function(...)
  return mod.use_upgrade_scouting_clairvoyance1(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_SCOUTING_CLAIRVOYANCE2"] = function(...)
  return mod.use_upgrade_scouting_clairvoyance2(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_BONUSMISSIONS1"] = function(...)
  return mod.use_upgrade_bonusmissions1(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_BONUSMISSIONS2"] = function(...)
  return mod.use_upgrade_bonusmissions2(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_BONUSMISSIONS3"] = function(...)
  return mod.use_upgrade_bonusmissions3(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_BONUSMISSIONS4"] = function(...)
  return mod.use_upgrade_bonusmissions4(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_BONUSMISSIONS5"] = function(...)
  return mod.use_upgrade_bonusmissions5(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_HARDMISSIONS1"] = function(...)
  return mod.use_upgrade_hardmissions1(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_HARDMISSIONS2"] = function(...)
  return mod.use_upgrade_hardmissions2(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_SLAUGHTER"] = function(...)
  return mod.use_upgrade_slaughter(...)
end

game.iuse_functions["SKYISLAND_UPGRADE_LANDING_FLIGHT"] = function(...)
  return mod.use_upgrade_landing_flight(...)
end

-- Utility item activations
game.iuse_functions["SKYISLAND_QUICKHEAL"] = function(...)
  return mod.use_quickheal(...)
end

game.iuse_functions["SKYISLAND_EARTHBOUND_PILL"] = function(...)
  return mod.use_earthbound_pill(...)
end

game.iuse_functions["SKYISLAND_SKYWARD_BEACON"] = function(...)
  return mod.use_skyward_beacon(...)
end

game.iuse_functions["SKYISLAND_WARP_CRYSTAL"] = function(...)
  return mod.use_warp_crystal(...)
end

game.iuse_functions["SKYISLAND_ANIMAL_TELEPORTER"] = function(...)
  return mod.use_animal_teleporter(...)
end

game.iuse_functions["SKYISLAND_WARP_FOCUS"] = function(...)
  return mod.use_warp_focus(...)
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

-- table.insert(game.hooks.on_char_death, function(...)
--   return mod.on_char_death(...)
-- end)

table.insert(game.hooks.on_character_death, function(...)
  return mod.on_character_death(...)
end)

gdebug.log_info("Sky Islands PoC preload complete")
