-- Sky Islands BN Port - Mission System
-- Mission creation, completion, and rewards

local missions = {}
local util = require("util")

-- Mission reward table (mission_name -> shard count)
-- HACK: We're using mission names instead of mission type IDs because BN's Lua bindings
-- don't expose mission_type.id. The mission_type class exists in Lua but its 'id' field
-- is not bound (see catalua_bindings_mission.cpp line 47 comment). We could use
-- mission:get_type() but can't access .id on it. Using names works but is fragile if
-- mission names change. Ideally BN should expose mission_type.id or add a method like
-- mission:get_type_id_str() to make this cleaner.
local MISSION_REWARDS = {
  -- MGOAL_KILL_MONSTER_SPEC missions
  ["RAID: Kill 10 Zombies"] = 1,
  ["RAID: Kill 50 Zombies"] = 3,
  ["RAID: Kill 100 Zombies"] = 5,
  ["RAID: Kill a Mi-Go"] = 3,
  ["RAID: Kill 3 Nether Creatures"] = 4,
  ["RAID: Kill 5 Birds"] = 1,
  ["RAID: Kill 5 Mammals"] = 1,

  -- MGOAL_KILL_MONSTERS (combat) missions
  ["RAID: Clear zombie cluster"] = 3,
  ["RAID: Clear zombie horde"] = 4,
  ["RAID: Clear evolved zombies"] = 4,
  ["RAID: Clear evolved horde"] = 5,
  ["RAID: Clear fearsome zombies"] = 5,
  ["RAID: Clear elite zombies"] = 8,
  ["RAID: Kill zombie lord"] = 10,
  ["RAID: Kill zombie superteam"] = 10,
  ["RAID: Kill zombie leader + swarm"] = 12,
  ["RAID: Kill horde lord"] = 12,
  ["RAID: Clear mi-go threat"] = 9,
  ["RAID: Kill mi-go overlord"] = 12,
}

-- Give mission reward
local function give_mission_reward(player, mission_name, count)
  if count and count > 0 then
    -- Give warp shards directly using add_item_with_id
    -- BN requires an itype_id userdata object (string_id<itype>)
    local shard_id = ItypeId.new("skyisland_warp_shard")
    player:add_item_with_id(shard_id, count)
    gapi.add_msg(string.format("You completed a mission and were rewarded with %d warp shard%s.", count, count > 1 and "s" or ""))
    util.debug_log(string.format("Awarded %d warp shards for mission %s", count, mission_name))
  end
end

-- Get mission type ID suffix based on raid type
local function get_raid_suffix(storage)
  local raid_type = storage.current_raid_type or "short"
  if raid_type == "medium" then
    return "_MEDIUM"
  elseif raid_type == "long" then
    return "_LONG"
  else
    return "_SHORT"
  end
end

-- Get scouting suffix based on scouting level
local function get_scout_suffix(storage)
  local scouting_level = storage.scouting_unlocked or 0
  if scouting_level >= 2 then
    return "_SCOUT2"
  elseif scouting_level >= 1 then
    return "_SCOUT1"
  else
    return ""
  end
end

-- Create extraction mission(s)
-- With multiple_exits upgrade, spawns 2 exit portals
function missions.create_extraction_mission(center_omt, storage)
  local player = gapi.get_avatar()
  if not player then return end

  local multiple_exits = storage.multiple_exits_unlocked or 0
  local num_exits = multiple_exits >= 1 and 2 or 1

  -- Select mission type based on raid length and scouting level
  local raid_suffix = get_raid_suffix(storage)
  local scout_suffix = get_scout_suffix(storage)
  local mission_type_id = "MISSION_REACH_EXTRACT" .. raid_suffix .. scout_suffix
  util.debug_log(string.format("Creating extraction mission: %s (raid type: %s, scouting: %d)",
    mission_type_id, storage.current_raid_type or "unknown", storage.scouting_unlocked or 0))

  for i = 1, num_exits do
    local player_id = player:getID()
    local mission_type = MissionTypeIdRaw.new(mission_type_id)

    local new_mission = Mission.reserve_new(mission_type, player_id)
    if new_mission then
      new_mission:assign(player)
      if i == 1 then
        gapi.add_msg("Mission: Reach the exit portal!")
      else
        gapi.add_msg("Another exit portal has also been detected!")
      end
      -- Get actual target location from mission
      local target = new_mission:get_target_point()
      util.debug_log(string.format("Created extraction mission %d at: %d, %d, %d", i, target.x, target.y, target.z))

      -- Store first exit location for tracking
      if i == 1 then
        storage.exit_location = { x = target.x, y = target.y, z = target.z }
      end
    else
      gdebug.log_error(string.format("Failed to create extraction mission %d!", i))
    end
  end
end

-- Create bonus mission (unified weighted selection based on upgrade tiers)
-- DDA weights: treasure=45, light=15, horde=10, mid=15, mid_horde=10
-- Hard missions add: hard=10, elite=5, boss=5, migo=5
-- Hardest missions add: boss_group=10, boss_horde=10, boss_multi=10, migo_elite=10
function missions.create_bonus_mission(center_omt, storage)
  local player = gapi.get_avatar()
  if not player then return end

  local hard_tier = storage.hard_missions_tier or 0
  local suffix = get_raid_suffix(storage)

  -- Build weighted mission pool
  local mission_pool = {
    -- Base missions (always available with bonus_missions_tier >= 1)
    { id = "MISSION_BONUS_TREASURE" .. suffix, weight = 45, name = "Find the warp shards", has_target = true },
    { id = "MISSION_BONUS_KILL_LIGHT", weight = 15, name = "Clear zombie cluster", has_target = true },
    { id = "MISSION_BONUS_KILL_HORDE", weight = 10, name = "Clear zombie horde", has_target = true },
    { id = "MISSION_BONUS_KILL_MID", weight = 15, name = "Clear evolved zombies", has_target = true },
    { id = "MISSION_BONUS_KILL_MID_HORDE", weight = 10, name = "Clear evolved horde", has_target = true },
  }

  -- Hard missions (hard_missions_tier >= 1)
  if hard_tier >= 1 then
    table.insert(mission_pool, { id = "MISSION_BONUS_KILL_HARD", weight = 10, name = "Clear fearsome zombies", has_target = true })
    table.insert(mission_pool, { id = "MISSION_BONUS_KILL_ELITE", weight = 5, name = "Clear elite zombies", has_target = true })
    table.insert(mission_pool, { id = "MISSION_BONUS_KILL_BOSS", weight = 5, name = "Kill zombie lord", has_target = true })
    table.insert(mission_pool, { id = "MISSION_BONUS_KILL_MIGO", weight = 5, name = "Clear mi-go threat", has_target = true })
  end

  -- Hardest missions (hard_missions_tier >= 2)
  if hard_tier >= 2 then
    table.insert(mission_pool, { id = "MISSION_BONUS_KILL_BOSS_GROUP", weight = 10, name = "Kill zombie leader + swarm", has_target = true })
    table.insert(mission_pool, { id = "MISSION_BONUS_KILL_BOSS_HORDE", weight = 10, name = "Kill horde lord", has_target = true })
    table.insert(mission_pool, { id = "MISSION_BONUS_KILL_BOSS_MULTI", weight = 10, name = "Kill zombie superteam", has_target = true })
    table.insert(mission_pool, { id = "MISSION_BONUS_KILL_MIGO_ELITE", weight = 10, name = "Kill mi-go overlord", has_target = true })
  end

  -- Calculate total weight
  local total_weight = 0
  for _, mission in ipairs(mission_pool) do
    total_weight = total_weight + mission.weight
  end

  -- Select random mission based on weight
  local roll = gapi.rng(1, total_weight)
  local selected = nil
  local current_weight = 0

  for _, mission in ipairs(mission_pool) do
    current_weight = current_weight + mission.weight
    if roll <= current_weight then
      selected = mission
      break
    end
  end

  if not selected then
    gdebug.log_error("Failed to select bonus mission!")
    return
  end

  util.debug_log(string.format("Creating bonus mission: %s", selected.id))

  local player_id = player:getID()
  local mission_type = MissionTypeIdRaw.new(selected.id)

  local new_mission = Mission.reserve_new(mission_type, player_id)
  if new_mission then
    new_mission:assign(player)
    gapi.add_msg(string.format("Bonus Mission: %s!", selected.name))
    if selected.has_target then
      local target = new_mission:get_target_point()
      util.debug_log(string.format("Created bonus mission at: %d, %d, %d", target.x, target.y, target.z))
    end
  else
    gdebug.log_error(string.format("Failed to create bonus mission: %s", selected.id))
  end
end

-- Create slaughter mission (kill X of species)
-- These are simpler kill-count missions that don't require going to a specific location
function missions.create_slaughter_mission(center_omt, storage)
  local player = gapi.get_avatar()
  if not player then return end

  -- Build weighted mission pool
  -- More common/easier missions have higher weights
  local mission_pool = {
    { id = "MISSION_SLAUGHTER_ZOMBIES_10", weight = 40, name = "Kill 10 Zombies" },
    { id = "MISSION_SLAUGHTER_ZOMBIES_50", weight = 20, name = "Kill 50 Zombies" },
    { id = "MISSION_SLAUGHTER_ZOMBIES_100", weight = 10, name = "Kill 100 Zombies" },
    { id = "MISSION_SLAUGHTER_BIRD", weight = 15, name = "Kill 5 Birds" },
    { id = "MISSION_SLAUGHTER_MAMMAL", weight = 15, name = "Kill 5 Mammals" },
    { id = "MISSION_SLAUGHTER_MIGO", weight = 5, name = "Kill a Mi-Go" },
    { id = "MISSION_SLAUGHTER_NETHER", weight = 5, name = "Kill 3 Nether Creatures" },
  }

  -- Calculate total weight
  local total_weight = 0
  for _, mission in ipairs(mission_pool) do
    total_weight = total_weight + mission.weight
  end

  -- Select random mission based on weight
  local roll = gapi.rng(1, total_weight)
  local selected = nil
  local current_weight = 0

  for _, mission in ipairs(mission_pool) do
    current_weight = current_weight + mission.weight
    if roll <= current_weight then
      selected = mission
      break
    end
  end

  if not selected then
    gdebug.log_error("Failed to select slaughter mission!")
    return
  end

  util.debug_log(string.format("Creating slaughter mission: %s", selected.id))

  local player_id = player:getID()
  local mission_type = MissionTypeIdRaw.new(selected.id)

  local new_mission = Mission.reserve_new(mission_type, player_id)
  if new_mission then
    new_mission:assign(player)
    gapi.add_msg(string.format("Slaughter Mission: %s!", selected.name))
    util.debug_log(string.format("Created slaughter mission: %s", selected.id))
  else
    gdebug.log_error(string.format("Failed to create slaughter mission: %s", selected.id))
  end
end

-- Complete or fail all raid missions
function missions.complete_or_fail_missions(player, storage)
  local missions_list = player:get_active_missions()

  for _, mission in ipairs(missions_list) do
    if mission:in_progress() and not mission:has_failed() then
      local mission_name = mission:name()

      -- Only process raid missions (prefixed with "RAID: ")
      if mission_name:sub(1, 6) == "RAID: " then
        -- Check mission type and handle appropriately
        if mission_name == "RAID: Reach the exit portal!" or mission_name == "RAID: Find the warp shards!" then
          -- GO_TO missions: Always complete (survival = success)
          mission:wrap_up()
          util.debug_log(string.format("Completed mission: %s (GO_TO mission)", mission_name))
          gapi.add_msg(string.format("Mission completed: %s", mission_name))
        else
          -- KILL missions: Check if goal was actually met
          local is_complete = mission:is_complete()

          if is_complete then
            -- Give reward before completing mission
            local reward_count = MISSION_REWARDS[mission_name]
            if reward_count then
              give_mission_reward(player, mission_name, reward_count)
            end

            mission:wrap_up()
            util.debug_log(string.format("Completed mission: %s", mission_name))
            gapi.add_msg(string.format("Mission completed: %s", mission_name))
          else
            mission:fail()
            util.debug_log(string.format("Failed mission: %s", mission_name))
            gapi.add_msg(string.format("Mission failed: %s", mission_name))
          end
        end
      end
    end
  end
end

-- Fail all raid missions (used on death)
function missions.fail_all_raid_missions(player)
  local missions_list = player:get_active_missions()
  for _, mission in ipairs(missions_list) do
    if mission:in_progress() and not mission:has_failed() then
      local mission_name = mission:name()
      -- Only fail raid missions (prefixed with "RAID: ")
      if mission_name:sub(1, 6) == "RAID: " then
        mission:fail()
        util.debug_log(string.format("Failed raid mission on death: %s", mission_name))
      end
    end
  end
end

return missions
