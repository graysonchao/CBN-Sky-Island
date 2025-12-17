-- Sky Islands BN Port - Mission System
-- Mission creation, completion, and rewards

local missions = {}

-- Mission spawn distance (in OMT tiles)
local MIN_MISSION_DISTANCE = 5
local MAX_MISSION_DISTANCE = 30

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
    gdebug.log_info(string.format("Awarded %d warp shards for mission %s", count, mission_name))
  end
end

-- Create extraction mission(s)
-- With multiple_exits upgrade, spawns 2 exit portals
function missions.create_extraction_mission(center_omt, storage)
  local player = gapi.get_avatar()
  if not player then return end

  local multiple_exits = storage.multiple_exits_unlocked or 0
  local num_exits = multiple_exits >= 1 and 2 or 1

  for i = 1, num_exits do
    -- Pick exit location using new distance range (5-30 OMTs)
    local distance = gapi.rng(MIN_MISSION_DISTANCE, MAX_MISSION_DISTANCE)
    local angle = gapi.rng(0, 359) * (math.pi / 180)
    local dx = math.floor(distance * math.cos(angle))
    local dy = math.floor(distance * math.sin(angle))

    local exit_omt = Tripoint.new(
      center_omt.x + dx,
      center_omt.y + dy,
      center_omt.z
    )

    -- Store first exit location for tracking
    if i == 1 then
      storage.exit_location = { x = exit_omt.x, y = exit_omt.y, z = exit_omt.z }
    end

    -- Create and assign mission using BN's mission API
    local player_id = player:getID()
    local mission_type = MissionTypeIdRaw.new("MISSION_REACH_EXTRACT")

    local new_mission = Mission.reserve_new(mission_type, player_id)
    if new_mission then
      new_mission:assign(player)
      if i == 1 then
        gapi.add_msg("Mission: Reach the exit portal!")
      else
        gapi.add_msg("A second exit portal has also been detected!")
      end
      gdebug.log_info(string.format("Created extraction mission %d at: %d, %d, %d (distance: %d OMT)", i, exit_omt.x, exit_omt.y, exit_omt.z, distance))
    else
      gdebug.log_error(string.format("Failed to create extraction mission %d!", i))
    end
  end
end

-- Create treasure mission
function missions.create_treasure_mission(center_omt)
  local player = gapi.get_avatar()
  if not player then return end

  -- Pick treasure location using new distance range (5-30 OMTs)
  local distance = gapi.rng(MIN_MISSION_DISTANCE, MAX_MISSION_DISTANCE)
  local angle = gapi.rng(0, 359) * (math.pi / 180)
  local dx = math.floor(distance * math.cos(angle))
  local dy = math.floor(distance * math.sin(angle))

  local treasure_omt = Tripoint.new(
    center_omt.x + dx,
    center_omt.y + dy,
    center_omt.z
  )

  local player_id = player:getID()
  local mission_type = MissionTypeIdRaw.new("MISSION_BONUS_TREASURE")

  local new_mission = Mission.reserve_new(mission_type, player_id)
  if new_mission then
    new_mission:assign(player)
    gapi.add_msg("Bonus Mission: Find the warp shards!")
    gdebug.log_info(string.format("Created treasure mission at: %d, %d, %d (distance: %d OMT)", treasure_omt.x, treasure_omt.y, treasure_omt.z, distance))
  else
    gdebug.log_error("Failed to create treasure mission!")
  end
end

-- Create slaughter mission
function missions.create_slaughter_mission()
  local player = gapi.get_avatar()
  if not player then return end

  -- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  -- !!! TEMPORARY DEBUG: FORCE KILL_MONSTERS MISSION FOR TESTING             !!!
  -- !!! REMOVE THIS BEFORE PRODUCTION - SEARCH FOR "TEMPORARY DEBUG"         !!!
  -- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  local DEBUG_FORCE_KILL_MONSTERS = true

  if DEBUG_FORCE_KILL_MONSTERS then
    gdebug.log_info("!!! TEMPORARY DEBUG: Forcing MISSION_BONUS_KILL_LIGHT for testing !!!")
    local player_id = player:getID()
    local mission_type = MissionTypeIdRaw.new("MISSION_BONUS_KILL_LIGHT")
    local new_mission = Mission.reserve_new(mission_type, player_id)
    if new_mission then
      new_mission:assign(player)
      gapi.add_msg("DEBUG: Mission: Kill the warp-draining zombies!")
      gdebug.log_info("DEBUG: Created KILL_MONSTERS mission: MISSION_BONUS_KILL_LIGHT")
    else
      gdebug.log_error("DEBUG: Failed to create KILL_MONSTERS mission!")
    end
    return
  end
  -- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  -- Weighted pool of slaughter missions (matching CDDA weights)
  local slaughter_missions = {
    { id = "MISSION_SLAUGHTER_ZOMBIES_10", weight = 10, name = "Kill 10 Zombies" },
    { id = "MISSION_SLAUGHTER_ZOMBIES_50", weight = 20, name = "Kill 50 Zombies" },
    { id = "MISSION_SLAUGHTER_BIRD", weight = 5, name = "Kill 5 Birds" },
    { id = "MISSION_SLAUGHTER_MAMMAL", weight = 5, name = "Kill 5 Mammals" },
    -- TODO: Add harder missions when difficulty system is implemented
    -- MISSION_SLAUGHTER_ZOMBIES_100, MISSION_SLAUGHTER_MIGO, MISSION_SLAUGHTER_NETHER
  }

  -- Calculate total weight
  local total_weight = 0
  for _, mission in ipairs(slaughter_missions) do
    total_weight = total_weight + mission.weight
  end

  -- Select random mission based on weight
  local roll = gapi.rng(1, total_weight)
  local selected_mission = nil
  local current_weight = 0

  for _, mission in ipairs(slaughter_missions) do
    current_weight = current_weight + mission.weight
    if roll <= current_weight then
      selected_mission = mission
      break
    end
  end

  if not selected_mission then
    gdebug.log_error("Failed to select slaughter mission!")
    return
  end

  local player_id = player:getID()
  local mission_type = MissionTypeIdRaw.new(selected_mission.id)

  local new_mission = Mission.reserve_new(mission_type, player_id)
  if new_mission then
    new_mission:assign(player)
    gapi.add_msg(string.format("Mission: %s!", selected_mission.name))
    gdebug.log_info(string.format("Created slaughter mission: %s", selected_mission.name))
  else
    gdebug.log_error("Failed to create slaughter mission!")
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
          gdebug.log_info(string.format("Completed mission: %s (GO_TO mission)", mission_name))
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
            gdebug.log_info(string.format("Completed mission: %s", mission_name))
            gapi.add_msg(string.format("Mission completed: %s", mission_name))
          else
            mission:fail()
            gdebug.log_info(string.format("Failed mission: %s", mission_name))
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
        gdebug.log_info(string.format("Failed raid mission on death: %s", mission_name))
      end
    end
  end
end

return missions
