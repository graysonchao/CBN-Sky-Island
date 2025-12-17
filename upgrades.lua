-- Sky Islands BN Port - Upgrades System
-- Handles upgrade item activation and storage tracking

local upgrades = {}

-- Upgrade definitions
-- Maps upgrade key to: storage_field, required_level (current level must equal this), new_level, success_message
-- DDA has 4 stability upgrades, each adding +1 pulse to grace period (8 -> 9 -> 10 -> 11 -> 12)
local UPGRADE_DEFS = {
  stability1 = {
    field = "stability_unlocked",
    required = 0,
    new_level = 1,
    message = "Your resistance to the chaos of the warpstream increases. In every future expedition, you will be able to endure 1 additional warp pulse (9 total)."
  },
  stability2 = {
    field = "stability_unlocked",
    required = 1,
    new_level = 2,
    message = "Your warp resistance grows stronger. You can now endure 2 additional warp pulses (10 total)."
  },
  stability3 = {
    field = "stability_unlocked",
    required = 2,
    new_level = 3,
    message = "Your stability increases further. You can now endure 3 additional warp pulses (11 total)."
  },
  scouting1 = {
    field = "scouting_unlocked",
    required = 0,
    new_level = 1,
    message = "Your vision expands. A 3x3 area around your landing zone will be revealed on future expeditions."
  },
  scouting2 = {
    field = "scouting_unlocked",
    required = 1,
    new_level = 2,
    message = "Your foresight sharpens. A 5x5 area around your landing zone will be revealed on future expeditions."
  },
  exits1 = {
    field = "multiple_exits_unlocked",
    required = 0,
    new_level = 1,
    message = "The paths multiply. Two return obelisks will now spawn per expedition, giving you more options to escape."
  },
  raidlength1 = {
    field = "longer_raids_unlocked",
    required = 0,
    new_level = 1,
    message = "Large Expeditions are now available at the warp obelisk. You will have double the grace period before warp sickness sets in."
  },
  raidlength2 = {
    field = "longer_raids_unlocked",
    required = 1,
    new_level = 2,
    message = "Extended Expeditions are now available. You will have triple the grace period for maximum exploration time."
  }
}

-- Check if near the Heart of the Island
local function is_near_heart(player)
  -- The crafting already requires being near the heart (fakeitem_heart tool),
  -- so if they crafted the item, they were near the heart.
  -- For activation, we trust that they crafted it properly.
  -- In the future, we could add a proximity check here.
  return true
end

-- Generic upgrade activation function
local function activate_upgrade(who, item, pos, storage, upgrade_key)
  local def = UPGRADE_DEFS[upgrade_key]
  if not def then
    gapi.add_msg("ERROR: Unknown upgrade key: " .. upgrade_key)
    return 0
  end

  local player = gapi.get_avatar()
  if not player then
    return 0
  end

  -- Check current level
  local current_level = storage[def.field] or 0
  if current_level ~= def.required then
    if current_level >= def.new_level then
      gapi.add_msg("You have already unlocked this upgrade.")
    else
      gapi.add_msg("You must unlock the previous tier of this upgrade first.")
    end
    return 0
  end

  -- Apply the upgrade
  storage[def.field] = def.new_level
  gapi.add_msg("=== UPGRADE UNLOCKED ===")
  gapi.add_msg(def.message)
  gdebug.log_info(string.format("Upgrade %s activated: %s = %d", upgrade_key, def.field, def.new_level))

  -- Consume the item (return 1 to consume)
  return 1
end

-- Individual upgrade handlers (called by main.lua iuse registrations)
function upgrades.use_stability1(who, item, pos, storage)
  return activate_upgrade(who, item, pos, storage, "stability1")
end

function upgrades.use_stability2(who, item, pos, storage)
  return activate_upgrade(who, item, pos, storage, "stability2")
end

function upgrades.use_stability3(who, item, pos, storage)
  return activate_upgrade(who, item, pos, storage, "stability3")
end

function upgrades.use_scouting1(who, item, pos, storage)
  return activate_upgrade(who, item, pos, storage, "scouting1")
end

function upgrades.use_scouting2(who, item, pos, storage)
  return activate_upgrade(who, item, pos, storage, "scouting2")
end

function upgrades.use_exits1(who, item, pos, storage)
  return activate_upgrade(who, item, pos, storage, "exits1")
end

function upgrades.use_raidlength1(who, item, pos, storage)
  return activate_upgrade(who, item, pos, storage, "raidlength1")
end

function upgrades.use_raidlength2(who, item, pos, storage)
  return activate_upgrade(who, item, pos, storage, "raidlength2")
end

return upgrades
