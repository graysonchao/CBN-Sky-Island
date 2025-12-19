-- Sky Islands BN Port - Teleportation System
-- Handles warp obelisk, return obelisk, and teleportation logic

local teleport = {}

-- Red room bounds relative to obelisk position
-- The interior of the room is 3 tiles in one axis and 2 in the other from the obelisk
-- Since the room can rotate, we use 3 for both axes to be safe
local RED_ROOM_RANGE = 3  -- tiles in each direction

-- Helper: Store items from the red room in temporary storage (survives map changes)
-- Returns the number of items stored
local function store_red_room_items(obelisk_pos)
  local game_map = gapi.get_map()
  local items_stored = 0

  gdebug.log_info(string.format("Scanning red room around obelisk at (%d, %d, %d)",
    obelisk_pos.x, obelisk_pos.y, obelisk_pos.z))

  -- Scan area inside the red room (not including walls)
  for dx = -RED_ROOM_RANGE, RED_ROOM_RANGE do
    for dy = -RED_ROOM_RANGE, RED_ROOM_RANGE do
      local check_pos = Tripoint.new(
        obelisk_pos.x + dx,
        obelisk_pos.y + dy,
        obelisk_pos.z
      )

      -- Check if there are items at this position
      if game_map:has_items_at(check_pos) then
        local items_stack = game_map:get_items_at(check_pos)

        -- Collect all items at this position into a list first
        -- (can't modify while iterating)
        local items_to_store = {}
        for _, it in pairs(items_stack:as_item_stack()) do
          table.insert(items_to_store, it)
        end

        -- Now store each item (removes from map, puts in temporary storage)
        for _, it in ipairs(items_to_store) do
          local index = game_map:store_item(check_pos, it)
          if index >= 0 then
            items_stored = items_stored + 1
          end
        end
      end
    end
  end

  if items_stored > 0 then
    gdebug.log_info(string.format("Total: %d items stored from red room", items_stored))
  else
    gdebug.log_info("No items found in red room")
  end

  return items_stored
end

-- Helper: Retrieve stored items and place them at home position
local function retrieve_stored_items_at_home(home_pos)
  local game_map = gapi.get_map()
  local stored_count = game_map:get_stored_item_count()
  local items_retrieved = 0

  gdebug.log_info(string.format("Retrieving %d stored items at home (%d, %d, %d)",
    stored_count, home_pos.x, home_pos.y, home_pos.z))

  -- Retrieve each stored item (indices 0 to stored_count-1)
  for i = 0, stored_count - 1 do
    if game_map:retrieve_stored_item(i, home_pos) then
      items_retrieved = items_retrieved + 1
    end
  end

  -- Clear the storage
  game_map:clear_stored_items()

  if items_retrieved > 0 then
    gapi.add_msg(string.format("%d items from the red room were teleported home with you!", items_retrieved))
    gdebug.log_info(string.format("Retrieved %d items at home", items_retrieved))
  end

  return items_retrieved
end

-- Raid configuration
-- Distances are in OMT (overmap terrain tiles). One overmap is 180x180 OMT.
-- Timing: Base pulse interval is 15 minutes. Multiplier extends this.
-- DDA timing: 8 pulses grace, then sickness stages 9-12, disintegration at 12+
-- Short (1x): 15 min pulses = 2 hour grace, 3 hour disintegration
-- Medium (2x): 30 min pulses = 4 hour grace, 6 hour disintegration
-- Long (3x): 45 min pulses = 6 hour grace, 9 hour disintegration
local RAID_CONFIG = {
  short = {
    name = "Quick Expedition",
    description = "Normal time limit (2 hours grace). Exits will be close together.",
    pulse_multiplier = 1,
    material_tokens = 50,
    token_cost = 0,  -- Free - no softlock risk
    -- Landing spot distance
    min_distance = 200,
    max_distance = 1200,
    -- Mission/exit distances (from landing spot)
    mission_min = 5,
    mission_max = 30,
    exit_min = 5,
    exit_max = 35
  },
  medium = {
    name = "Large Expedition",
    description = "Double time limit (4 hours grace). Exits scattered over wider area.",
    pulse_multiplier = 2,
    material_tokens = 125,
    min_distance = 200,
    max_distance = 1200,
    mission_min = 20,
    mission_max = 60,
    exit_min = 30,
    exit_max = 90
  },
  long = {
    name = "Extended Expedition",
    description = "Triple time limit (6 hours grace). Exits very far away.",
    pulse_multiplier = 3,
    material_tokens = 200,
    min_distance = 200,
    max_distance = 1200,
    mission_min = 30,
    mission_max = 80,
    exit_min = 50,
    exit_max = 160
  }
}

-- Starting location configuration
local LOCATION_CONFIG = {
  field = {
    name = "Field",
    description = "Arrive in a barren field. Usually wilderness, but could be an empty lot in town.",
    terrain_type = "field",
    match_type = OtMatchType.EXACT,
    z_level = 0,
    unlock_key = nil,  -- Always available
    catalyst_item = nil
  },
  basement = {
    name = "Basement",
    description = "Arrive inside an underground basement. Usually suburbia.",
    terrain_type = "basement",
    match_type = OtMatchType.CONTAINS,
    z_level = -1,
    unlock_key = "basements_unlocked",
    catalyst_item = nil
  },
  roof = {
    name = "Rooftop",
    description = "Arrive on a building roof. Usually houses, one story up.",
    terrain_type = "roof",
    match_type = OtMatchType.CONTAINS,
    z_level = 1,
    unlock_key = "roofs_unlocked",
    catalyst_item = nil
  },
  labs = {
    name = "Science Lab",
    description = "Arrive in a subterranean science lab. DANGEROUS! Costs 1 Labs Catalyst. You will be sealed inside - bring an exit strategy!",
    terrain_type = "lab",
    match_type = OtMatchType.CONTAINS,
    z_level = -2,
    unlock_key = "labs_unlocked",
    catalyst_item = "skyisland_labs_catalyst"
  }
}

-- Helper: Get player position in OMT coordinates
local function get_player_omt()
  local player = gapi.get_avatar()
  if not player then return nil end

  local pos_ms = player:get_pos_ms()
  local abs_ms = gapi.get_map():get_abs_ms(pos_ms)
  local omt, _ = coords.ms_to_omt(abs_ms)
  return omt
end

-- Helper: Teleport player to OMT coordinates with offset
local function teleport_to_omt(omt, offset_tiles)
  gdebug.log_info(string.format("Teleporting to OMT: %s, %s, %s", omt.x, omt.y, omt.z))
  gapi.place_player_overmap_at(omt)

  -- If offset specified, move player after teleport
  if offset_tiles then
    local player = gapi.get_avatar()
    if player then
      local current_pos = player:get_pos_ms()
      local new_pos = Tripoint.new(
        current_pos.x + offset_tiles.x,
        current_pos.y + offset_tiles.y,
        current_pos.z + offset_tiles.z
      )
      player:set_pos_ms(new_pos)
      gdebug.log_info(string.format("Applied offset: %d, %d, %d", offset_tiles.x, offset_tiles.y, offset_tiles.z))
    end
  end

  gapi.add_msg("You feel reality shift around you...")
end

-- Use warp obelisk - start expedition
function teleport.use_warp_obelisk(who, item, pos, storage, missions, warp_sickness)
  if storage.is_away_from_home then
    gapi.add_msg("You are already on an expedition!")
    return 0
  end

  -- Store home location as absolute MS coordinates (for resurrection) - only once
  if not storage.home_location then
    local player_pos_ms = who:get_pos_ms()
    local home_abs_ms = gapi.get_map():get_abs_ms(player_pos_ms)
    storage.home_location = { x = home_abs_ms.x, y = home_abs_ms.y, z = home_abs_ms.z }
    gdebug.log_info(string.format("Home location set to: %d, %d, %d", home_abs_ms.x, home_abs_ms.y, home_abs_ms.z))
  end

  -- Also get OMT for teleportation
  local home_omt = get_player_omt()
  if not home_omt then
    gapi.add_msg("ERROR: Could not determine position!")
    return 0
  end

  -- Check what raid lengths are unlocked
  local longer_raids = storage.longer_raids_unlocked or 0

  -- Show raid type menu
  local ui = UiList.new()
  ui:title(locale.gettext("Select Expedition Type"))

  local menu_index = 1
  local raid_options = {}

  -- Short raids always available
  ui:add(menu_index, locale.gettext(string.format("%s (reward: %d tokens)", RAID_CONFIG.short.name, RAID_CONFIG.short.material_tokens)))
  raid_options[menu_index] = "short"
  menu_index = menu_index + 1

  -- Medium raids require upgrade
  if longer_raids >= 1 then
    ui:add(menu_index, locale.gettext(string.format("%s (reward: %d tokens)", RAID_CONFIG.medium.name, RAID_CONFIG.medium.material_tokens)))
    raid_options[menu_index] = "medium"
    menu_index = menu_index + 1
  end

  -- Long raids require further upgrade
  if longer_raids >= 2 then
    ui:add(menu_index, locale.gettext(string.format("%s (reward: %d tokens)", RAID_CONFIG.long.name, RAID_CONFIG.long.material_tokens)))
    raid_options[menu_index] = "long"
    menu_index = menu_index + 1
  end

  ui:add(menu_index, locale.gettext("Cancel"))

  local choice = ui:query()
  local selected_raid = raid_options[choice]

  if not selected_raid then
    gapi.add_msg("Warp cancelled.")
    return 0
  end

  local config = RAID_CONFIG[selected_raid]

  -- Store raid type for token rewards on return
  storage.current_raid_type = selected_raid
  storage.current_raid_pulse_multiplier = config.pulse_multiplier
  -- Store distance values for mission spawning
  storage.current_mission_min = config.mission_min
  storage.current_mission_max = config.mission_max
  storage.current_exit_min = config.exit_min
  storage.current_exit_max = config.exit_max

  -- Show location type menu
  local loc_ui = UiList.new()
  loc_ui:title(locale.gettext("Select Starting Location"))

  local loc_index = 1
  local loc_options = {}
  local loc_order = { "field", "basement", "roof", "labs" }

  for _, loc_key in ipairs(loc_order) do
    local loc_config = LOCATION_CONFIG[loc_key]
    local is_unlocked = true
    local has_catalyst = true
    local suffix = ""

    -- Check if location type is unlocked
    if loc_config.unlock_key then
      is_unlocked = storage[loc_config.unlock_key] or false
    end

    -- Check if catalyst is available (for labs)
    if loc_config.catalyst_item and is_unlocked then
      has_catalyst = who:has_item_with_id(ItypeId.new(loc_config.catalyst_item))
      if not has_catalyst then
        suffix = " [No Catalyst]"
      end
    end

    if is_unlocked then
      local display_name = loc_config.name
      if loc_config.catalyst_item then
        display_name = display_name .. " (requires catalyst)"
      end
      loc_ui:add(loc_index, locale.gettext(display_name .. suffix))
      if has_catalyst then
        loc_options[loc_index] = loc_key
      else
        loc_options[loc_index] = nil  -- Can't select without catalyst
      end
      loc_index = loc_index + 1
    end
  end

  loc_ui:add(loc_index, locale.gettext("Cancel"))

  local loc_choice = loc_ui:query()
  local selected_location = loc_options[loc_choice]

  if not selected_location then
    gapi.add_msg("Warp cancelled.")
    return 0
  end

  local loc_config = LOCATION_CONFIG[selected_location]

  -- Consume catalyst if required
  if loc_config.catalyst_item then
    local catalyst_id = ItypeId.new(loc_config.catalyst_item)
    who:remove_items_with_id(catalyst_id, 1)
    gapi.add_msg("The Labs Catalyst crumbles to dust as dimensional barriers part...")
  end

  gapi.add_msg(string.format("Initiating %s to %s...", config.name, loc_config.name))
  gapi.add_msg("Searching for suitable location...")

  -- Build search parameters based on location type
  local params = OmtFindParams.new()
  params:add_type(loc_config.terrain_type, loc_config.match_type)

  -- For field, also add forest as fallback options
  if selected_location == "field" then
    params:add_type("forest", OtMatchType.EXACT)
    params:add_type("forest_thick", OtMatchType.EXACT)
  end

  -- Set search range
  params:set_search_range(config.min_distance, config.max_distance)
  -- Search at the appropriate z-level
  params:set_search_layers(loc_config.z_level, loc_config.z_level)

  -- Use ground-level origin for searching (sky islands are at z > 0)
  local search_origin = Tripoint.new(home_omt.x, home_omt.y, loc_config.z_level)

  gdebug.log_info(string.format("Searching for %s terrain in range %d-%d at z=%d from (%d, %d, %d)",
    loc_config.terrain_type, config.min_distance, config.max_distance, loc_config.z_level,
    search_origin.x, search_origin.y, search_origin.z))

  -- Debug: Try find_all to see how many results we get
  local all_results = overmapbuffer.find_all(search_origin, params)
  gdebug.log_info(string.format("find_all returned %d results", #all_results))

  -- Find a random location matching parameters
  local dest_omt = overmapbuffer.find_random(search_origin, params)

  if dest_omt then
    gdebug.log_info(string.format("Found raid location at (%d, %d, %d)", dest_omt.x, dest_omt.y, dest_omt.z))
  else
    -- Fallback: widen the search range significantly
    gdebug.log_info("Primary search failed, trying wider range...")
    local fallback_params = OmtFindParams.new()
    fallback_params:add_type(loc_config.terrain_type, loc_config.match_type)
    if selected_location == "field" then
      fallback_params:add_type("forest", OtMatchType.EXACT)
    end
    fallback_params:set_search_range(10, 2000)  -- Much wider range
    fallback_params:set_search_layers(loc_config.z_level, loc_config.z_level)

    local fallback_results = overmapbuffer.find_all(search_origin, fallback_params)
    gdebug.log_info(string.format("Fallback find_all returned %d results", #fallback_results))

    dest_omt = overmapbuffer.find_random(search_origin, fallback_params)

    if dest_omt then
      gdebug.log_info(string.format("Fallback found terrain at (%d, %d, %d)", dest_omt.x, dest_omt.y, dest_omt.z))
    else
      -- Absolute last resort - this shouldn't happen but just in case
      gapi.add_msg("WARNING: Could not find suitable terrain. Aborting warp.")
      gdebug.log_info("ERROR: All terrain searches failed!")
      -- Refund catalyst if we consumed one
      if loc_config.catalyst_item then
        who:add_item_with_id(ItypeId.new(loc_config.catalyst_item), 1)
        gapi.add_msg("Your Labs Catalyst is returned.")
      end
      return 0
    end
  end

  teleport_to_omt(dest_omt)

  -- Reveal overmap if scouting is unlocked
  local scouting_level = storage.scouting_unlocked or 0
  if scouting_level > 0 then
    local reveal_radius = scouting_level == 1 and 1 or 2  -- 3x3 or 5x5
    for dx = -reveal_radius, reveal_radius do
      for dy = -reveal_radius, reveal_radius do
        local reveal_pos = Tripoint.new(dest_omt.x + dx, dest_omt.y + dy, dest_omt.z)
        overmapbuffer.set_seen(reveal_pos, true)
      end
    end
    local area_size = (reveal_radius * 2 + 1)
    gapi.add_msg(string.format("Your scouting reveals a %dx%d area around the landing zone.", area_size, area_size))
  end

  -- Set away status
  storage.is_away_from_home = true
  storage.warp_pulse_count = 0
  storage.raids_total = (storage.raids_total or 0) + 1

  -- Create missions
  missions.create_extraction_mission(dest_omt, storage)
  missions.create_slaughter_mission()
  missions.create_treasure_mission(dest_omt, storage)

  -- Start warp sickness (apply initial effects)
  warp_sickness.start(storage)
  -- Start sickness timer (progressive worsening)
  warp_sickness.start_timer(storage)

  gapi.add_msg(string.format("You arrive at the %s!", loc_config.name:lower()))
  gapi.add_msg("Find the red room exit portal to return home before warp sickness kills you.")

  return 1
end

-- Use return obelisk - return home
function teleport.use_return_obelisk(who, item, pos, storage, missions, warp_sickness)
  if not storage.is_away_from_home then
    gapi.add_msg("You are already home!")
    return 0
  end

  if not storage.home_location then
    gapi.add_msg("ERROR: Home location not set!")
    return 0
  end

  local confirm_ui = UiList.new()
  confirm_ui:title("Return home?")
  confirm_ui:add(1, locale.gettext("Yes, return home"))
  confirm_ui:add(2, locale.gettext("No, stay"))
  local confirm = confirm_ui:query()

  if confirm == 1 then
    -- Store items from the red room in temporary storage BEFORE teleporting
    -- This removes them from the map and holds them in C++ storage that survives map changes
    local items_stored = store_red_room_items(pos)

    -- Convert stored abs_ms coordinates to OMT for teleportation
    local home_abs_ms = Tripoint.new(
      storage.home_location.x,
      storage.home_location.y,
      storage.home_location.z
    )
    local home_omt = coords.ms_to_omt(home_abs_ms)

    -- Offset 1 tile north (negative Y in map coordinates)
    teleport_to_omt(home_omt, Tripoint.new(0, -1, 0))

    -- Retrieve stored items and place them at home
    if items_stored > 0 then
      local player = gapi.get_avatar()
      local player_pos = player:get_pos_ms()
      retrieve_stored_items_at_home(player_pos)
    end

    -- Complete missions when returning home
    local player = gapi.get_avatar()
    if player then
      missions.complete_or_fail_missions(player, storage)
    end

    -- Award material tokens for successful return based on raid type
    local raid_type = storage.current_raid_type or "short"
    local config = RAID_CONFIG[raid_type]
    local material_tokens = config and config.material_tokens or 50

    player:add_item_with_id(ItypeId.new("skyisland_material_token"), material_tokens)
    gapi.add_msg(string.format("You've returned home safely! Earned %d material tokens.", material_tokens))

    -- Clear away status and increment wins
    storage.is_away_from_home = false
    storage.warp_pulse_count = 0
    local old_raids_won = storage.raids_won or 0
    storage.raids_won = old_raids_won + 1

    -- Stop warp sickness (remove all effects)
    warp_sickness.stop()

    -- Check for progress gate rank-ups (automatic at 10 and 20 wins)
    if old_raids_won < 10 and storage.raids_won >= 10 then
      gapi.add_msg("=== RANK UP ===")
      gapi.add_msg("You have survived 10 expeditions and achieved Adept rank!")
      gapi.add_msg("New features and recipes may now be available.")
    elseif old_raids_won < 20 and storage.raids_won >= 20 then
      gapi.add_msg("=== RANK UP ===")
      gapi.add_msg("You have survived 20 expeditions and achieved Master rank!")
      gapi.add_msg("New features and recipes may now be available.")
    end

    gapi.add_msg(string.format(
      "Stats: %d/%d raids completed successfully",
      storage.raids_won,
      storage.raids_total
    ))

    return 1
  else
    gapi.add_msg("Cancelled.")
    return 0
  end
end

-- Return home successfully (used by return obelisk and skyward beacon)
-- Does NOT prompt for confirmation - caller should handle that
function teleport.return_home_success(storage, missions, warp_sickness)
  if not storage.home_location then
    gapi.add_msg("ERROR: Home location not set!")
    return
  end

  -- Convert stored abs_ms coordinates to OMT for teleportation
  local home_abs_ms = Tripoint.new(
    storage.home_location.x,
    storage.home_location.y,
    storage.home_location.z
  )
  local home_omt = coords.ms_to_omt(home_abs_ms)

  -- Offset 1 tile north (negative Y in map coordinates)
  teleport_to_omt(home_omt, Tripoint.new(0, -1, 0))

  -- Complete missions when returning home
  local player = gapi.get_avatar()
  if player then
    missions.complete_or_fail_missions(player, storage)
  end

  -- Award material tokens for successful return based on raid type
  local raid_type = storage.current_raid_type or "short"
  local config = RAID_CONFIG[raid_type]
  local material_tokens = config and config.material_tokens or 50

  player:add_item_with_id(ItypeId.new("skyisland_material_token"), material_tokens)
  gapi.add_msg(string.format("You've returned home safely! Earned %d material tokens.", material_tokens))

  -- Clear away status and increment wins
  storage.is_away_from_home = false
  storage.warp_pulse_count = 0
  local old_raids_won = storage.raids_won or 0
  storage.raids_won = old_raids_won + 1

  -- Stop warp sickness (remove all effects)
  warp_sickness.stop()

  -- Check for progress gate rank-ups (automatic at 10 and 20 wins)
  if old_raids_won < 10 and storage.raids_won >= 10 then
    gapi.add_msg("=== RANK UP ===")
    gapi.add_msg("You have survived 10 expeditions and achieved Adept rank!")
    gapi.add_msg("New features and recipes may now be available.")
  elseif old_raids_won < 20 and storage.raids_won >= 20 then
    gapi.add_msg("=== RANK UP ===")
    gapi.add_msg("You have survived 20 expeditions and achieved Master rank!")
    gapi.add_msg("New features and recipes may now be available.")
  end

  gapi.add_msg(string.format(
    "Stats: %d/%d raids completed successfully",
    storage.raids_won,
    storage.raids_total
  ))
end

-- Resurrection handler - teleport player home after death
function teleport.resurrect_at_home(storage, missions, warp_sickness)
  if not storage.home_location then
    return  -- No home to resurrect at
  end

  gdebug.log_info("Sky Islands: Resurrecting at home")

  local player = gapi.get_avatar()
  if not player then return end

  -- DROP ALL ITEMS before teleporting - this is the death penalty!
  -- Items are dropped at the death location (lost forever)
  player:drop_all_items()
  gapi.add_msg("Your belongings scatter as reality tears you away...")

  -- Build home position from stored abs_ms coordinates
  local home_abs_ms = Tripoint.new(
    storage.home_location.x,
    storage.home_location.y,
    storage.home_location.z
  )

  -- Convert abs_ms to OMT for overmap placement
  local home_omt = coords.ms_to_omt(home_abs_ms)
  gapi.place_player_overmap_at(home_omt)

  -- Convert abs_ms to local_ms for exact positioning
  local local_pos = gapi.get_map():get_local_ms(home_abs_ms)
  gapi.place_player_local_at(local_pos)

  -- Fail all raid missions on death
  missions.fail_all_raid_missions(player)

  -- Mark raid as failed
  storage.is_away_from_home = false
  storage.warp_pulse_count = 0
  storage.raids_lost = (storage.raids_lost or 0) + 1

  -- Stop warp sickness (remove all effects before applying resurrection sickness)
  warp_sickness.stop()

  -- Apply resurrection sickness
  warp_sickness.apply_resurrection_sickness()

  gapi.add_msg("You respawn at home, naked and wounded!")
  gdebug.log_info(string.format("Resurrected at home abs_ms: %d, %d, %d", home_abs_ms.x, home_abs_ms.y, home_abs_ms.z))
end

return teleport
