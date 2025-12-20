-- Sky Islands BN Port - Main Module
-- Hooks, initialization, and module integration

local mod = game.mod_runtime[game.current_mod]
local storage = game.mod_storage[game.current_mod]

-- Load modules
local missions = require("missions")
local warp_sickness = require("warp_sickness")
local teleport = require("teleport")
local heart = require("heart")
local upgrades = require("upgrades")

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

-- Upgrade item activations
mod.use_upgrade_stability1 = function(who, item, pos)
  return upgrades.use_stability1(who, item, pos, storage)
end

mod.use_upgrade_stability2 = function(who, item, pos)
  return upgrades.use_stability2(who, item, pos, storage)
end

mod.use_upgrade_stability3 = function(who, item, pos)
  return upgrades.use_stability3(who, item, pos, storage)
end

mod.use_upgrade_scouting1 = function(who, item, pos)
  return upgrades.use_scouting1(who, item, pos, storage)
end

mod.use_upgrade_scouting2 = function(who, item, pos)
  return upgrades.use_scouting2(who, item, pos, storage)
end

mod.use_upgrade_exits1 = function(who, item, pos)
  return upgrades.use_exits1(who, item, pos, storage)
end

mod.use_upgrade_raidlength1 = function(who, item, pos)
  return upgrades.use_raidlength1(who, item, pos, storage)
end

mod.use_upgrade_raidlength2 = function(who, item, pos)
  return upgrades.use_raidlength2(who, item, pos, storage)
end

mod.use_upgrade_basements = function(who, item, pos)
  return upgrades.use_basements(who, item, pos, storage)
end

mod.use_upgrade_roofs = function(who, item, pos)
  return upgrades.use_roofs(who, item, pos, storage)
end

mod.use_upgrade_labs = function(who, item, pos)
  return upgrades.use_labs(who, item, pos, storage)
end

-- Utility item activations
mod.use_quickheal = function(who, item, pos)
  local player = gapi.get_avatar()
  if not player then return 0 end

  -- Only works on the island (not away from home)
  if storage.is_away_from_home then
    gapi.add_msg("The quickheal pill only works on your sanctuary island.")
    return 0
  end

  -- Heal all body parts to max
  player:healall(999)
  gapi.add_msg("A warm sensation washes over you as your wounds heal.")
  return 1  -- Consume the item
end

mod.use_earthbound_pill = function(who, item, pos)
  local player = gapi.get_avatar()
  if not player then return 0 end

  -- Only works during expedition
  if not storage.is_away_from_home then
    gapi.add_msg("You're not on an expedition. Save this for when you need more time earthside.")
    return 0
  end

  -- Reduce pulse count by 4 (extend time)
  storage.warp_pulse_count = math.max(0, (storage.warp_pulse_count or 0) - 4)
  gapi.add_msg("The pill dissolves on your tongue. You feel the warp's grip on you loosen. (+4 pulses of time)")
  gdebug.log_info(string.format("Earthbound pill used. Pulse count now: %d", storage.warp_pulse_count))
  return 1  -- Consume the item
end

mod.use_skyward_beacon = function(who, item, pos)
  local player = gapi.get_avatar()
  if not player then return 0 end

  -- Only works during expedition
  if not storage.is_away_from_home then
    gapi.add_msg("You're already home. The beacon has no effect here.")
    return 0
  end

  -- Return home with all items
  gapi.add_msg("The beacon flares with brilliant light. You feel yourself being pulled skyward...")
  teleport.return_home_success(storage, missions, warp_sickness)
  return 1  -- Consume the item
end

-- Warp status crystal - show detailed expedition status
mod.use_warp_crystal = function(who, item, pos)
  local player = gapi.get_avatar()
  if not player then return 0 end

  -- Get warp status info
  local status_info = warp_sickness.get_status_info(storage)

  -- Create status display menu
  local menu = UiList.new()
  menu:title("Warp Status Crystal")
  menu:desc_enabled(true)

  if not storage.is_away_from_home then
    menu:text("You are HOME SAFE on your sanctuary island.\n\nThe warp has no hold on you here.")
    menu:add(0, "Close")
  else
    -- Build status text
    local pulse_multiplier = storage.current_raid_pulse_multiplier or 1
    local interval_minutes = 15 * pulse_multiplier
    local raid_type = storage.current_raid_type or "short"
    local raid_name = raid_type:sub(1,1):upper() .. raid_type:sub(2)

    local status_text = string.format(
      "Current Expedition: %s\n" ..
      "Pulse Interval: %d minutes\n" ..
      "Current Pulse: %d\n" ..
      "Grace Period: %d pulses\n\n",
      raid_name,
      interval_minutes,
      status_info.current_pulse,
      status_info.grace_period
    )

    if status_info.in_grace_period then
      status_text = status_text .. string.format(
        "STATUS: STABLE\n" ..
        "Safe pulses remaining: %d\n" ..
        "Time until sickness begins: ~%d minutes",
        status_info.pulses_remaining,
        status_info.pulses_remaining * interval_minutes
      )
    else
      status_text = status_text .. string.format(
        "STATUS: %s (Intensity %d/%d)\n" ..
        "Pulses until disintegration: %d",
        status_info.status_name,
        status_info.current_intensity,
        6,
        status_info.pulses_to_disintegration
      )
    end

    menu:text(status_text)

    -- Add entries showing what happens at each stage
    menu:add_w_desc(1, "Stage 1: Warp Stability", "Grace period. No effects. You feel fine.")
    menu:add_w_desc(2, "Stage 2: Warp Sickness", "Intensity 1. -2 to all stats. Mild discomfort.")
    menu:add_w_desc(3, "Stage 3: Warp Nausea", "Intensity 2. -4 to all stats. Growing pain.")
    menu:add_w_desc(4, "Stage 4: Warp Debilitation", "Intensity 3. -6 to all stats. Severely impaired.")
    menu:add_w_desc(5, "Stage 5: Warp Necrosis", "Intensity 4. -8 to all stats. Body failing.")
    menu:add_w_desc(6, "Stage 6: Warp Disintegration!", "Intensity 5+. -10+ to stats. Constant damage. DEATH IMMINENT.")
    menu:add(0, "Close")
  end

  menu:query()
  return 0  -- Don't consume
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
-- mod.on_char_death = function()
--   gdebug.log_info("Sky Islands: on_char_death fired")
-- 
--   if storage.home_location then
--     local player = gapi.get_avatar()
--     if not player then return end
-- 
--     -- Clear all effects (including broken limb effects) EARLY
--     player:clear_effects()
--     -- Heal everything to prevent broken limbs from locking in
--     player:set_all_parts_hp_cur(10)
-- 
--     gdebug.log_info("Sky Islands: Cleared effects and healed in on_char_death")
--   end
-- end

-- Character death hook (late) - actual resurrection and teleportation
mod.on_character_death = function()
  gdebug.log_info("Sky Islands: on_character_death fired")
  gdebug.log_info(string.format("  home_location: %s", tostring(storage.home_location)))

  if not storage.home_location then
    return  -- No home set, can't resurrect
  end

  local player = gapi.get_avatar()
  if not player then return end

  -- Check for homeward mote (life insurance)
  local mote_id = ItypeId.new("skyisland_homeward_mote")
  local has_mote = player:has_item_with_id(mote_id, false)

  if has_mote then
    -- Homeward mote saves you! Keep all items, consume mote
    gdebug.log_info("Sky Islands: Homeward mote activated!")
    local mote_item = player:get_item_with_id(mote_id, false)
    if mote_item then
      player:remove_item(mote_item)
    end
    gapi.add_msg("The homeward mote flares brilliantly, yanking you from death's grasp!")
    gapi.add_msg("You arrive home alive, with all your belongings intact.")

    -- Teleport home WITH items (use the success path)
    teleport.return_home_success(storage, missions, warp_sickness)

    -- Mote save doesn't count as win or loss - undo the win increment from return_home_success
    storage.raids_won = (storage.raids_won or 1) - 1

    -- Full heal for mote saves
    player:clear_effects()
    player:healall(999)
  else
    -- Normal death - lose items, get resurrected at low HP
    teleport.resurrect_at_home(storage, missions, warp_sickness)

    -- resurrect_at_home already handles effects clearing and low HP via warp_sickness.apply_resurrection_sickness
  end
end

gdebug.log_info("Sky Islands PoC main.lua loaded")
