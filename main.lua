-- Sky Islands BN Port - Main Module
-- Hooks, initialization, and module integration

local mod = game.mod_runtime[game.current_mod]
local storage = game.mod_storage[game.current_mod]

-- Load modules
local missions = require("missions")
local warp_sickness = require("warp_sickness")
local teleport = require("teleport")
local heart = require("heart")

-- Initialize storage defaults (only for new games)
-- These will be overwritten by saved data on load
storage.home_location = storage.home_location or nil
storage.is_away_from_home = storage.is_away_from_home or false
storage.warp_pulse_count = storage.warp_pulse_count or 0
storage.raids_total = storage.raids_total or 0
storage.raids_won = storage.raids_won or 0
storage.raids_lost = storage.raids_lost or 0

-- Use warp obelisk - start expedition
mod.use_warp_obelisk = function(who, item, pos)
  return teleport.use_warp_obelisk(who, item, pos, storage, missions, warp_sickness)
end

-- Use return obelisk - return home
mod.use_return_obelisk = function(who, item, pos)
  return teleport.use_return_obelisk(who, item, pos, storage, missions, warp_sickness)
end

-- Use Heart of the Island - show interactive menu
mod.use_heart_menu = function(who, item, pos)
  return heart.use_heart(who, item, pos, storage)
end

-- Game started hook - initialize for new games only
mod.on_game_started = function()
  -- Reset to defaults for new game
  storage.home_location = nil
  storage.is_away_from_home = false
  storage.warp_pulse_count = 0
  storage.raids_total = 0
  storage.raids_won = 0
  storage.raids_lost = 0

  gdebug.log_info("Sky Islands: New game started")
  gapi.add_msg("Sky Islands PoC loaded! Use warp remote to start.")
end

-- Game load hook - restore state (storage auto-loaded)
mod.on_game_load = function()
  gdebug.log_info("Sky Islands: Game loaded")
  gdebug.log_info(string.format("  Away from home: %s", tostring(storage.is_away_from_home)))
  gdebug.log_info(string.format("  Warp pulse count: %d", storage.warp_pulse_count or 0))

  -- If we were away, restart the sickness timer
  if storage.is_away_from_home then
    gapi.add_msg("Resuming expedition... warp sickness timer restarted.")
    warp_sickness.start_timer(storage)
  end
end

-- Game save hook
mod.on_game_save = function()
  gdebug.log_info("Sky Islands: Game saving")
  gdebug.log_info(string.format("  Saving state: Away=%s, Pulses=%d",
    tostring(storage.is_away_from_home), storage.warp_pulse_count or 0))
end

-- Character death hook (early) - clear effects and heal before broken limbs lock in
mod.on_char_death = function()
  gdebug.log_info("Sky Islands: on_char_death fired")

  if storage.home_location then
    local player = gapi.get_avatar()
    if not player then return end

    -- Clear all effects (including broken limb effects) EARLY
    player:clear_effects()
    -- Heal everything to prevent broken limbs from locking in
    player:set_all_parts_hp_cur(10)

    gdebug.log_info("Sky Islands: Cleared effects and healed in on_char_death")
  end
end

-- Character death hook (late) - actual resurrection and teleportation
mod.on_character_death = function()
  gdebug.log_info("Sky Islands: on_character_death fired")
  gdebug.log_info(string.format("  home_location: %s", tostring(storage.home_location)))

  if storage.home_location then
    teleport.resurrect_at_home(storage, missions, warp_sickness)
  end
end

gdebug.log_info("Sky Islands PoC main.lua loaded")
