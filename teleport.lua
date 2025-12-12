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

-- Material token rewards per raid type
local MATERIAL_TOKEN_REWARDS = {
  short = 50,   -- Currently the only option
  medium = 125, -- TODO: Implement when raid duration selection is added
  long = 200,   -- TODO: Implement when raid duration selection is added
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

  -- Show raid type menu
  local ui = UiList.new()
  ui:title(locale.gettext("Select Expedition Type"))
  ui:add(1, locale.gettext("Quick Raid (Test)"))
  ui:add(2, locale.gettext("Cancel"))

  local choice = ui:query()

  if choice == 1 then
    -- Start quick raid
    gapi.add_msg("Initiating warp sequence...")
    gapi.add_msg("Searching for suitable raid location...")

    -- Build search parameters for suitable terrain 200-1200 OMT away
    local params = OmtFindParams.new()
    -- Use helper methods to add terrain types to search for
    params:add_type("house", OtMatchType.CONTAINS)
    params:add_type("forest", OtMatchType.CONTAINS)
    params:add_type("field", OtMatchType.CONTAINS)
    params:set_search_range(200, 1200)  -- Search between 200-1200 OMT from home

    -- Find a random location matching parameters (only searches existing overmaps)
    -- find_random_existing returns a single tripoint or nil
    local dest_omt = overmapbuffer.find_random(home_omt, params)

    if dest_omt then
      gdebug.log_info(string.format("Found raid location at (%d, %d, %d)", dest_omt.x, dest_omt.y, dest_omt.z))
    else
      -- Fallback: pick a random point if search failed
      local distance = gapi.rng(200, 1200)
      local angle = gapi.rng(0, 359) * (math.pi / 180)
      local start_x = home_omt.x + math.floor(distance * math.cos(angle))
      local start_y = home_omt.y + math.floor(distance * math.sin(angle))
      dest_omt = Tripoint.new(start_x, start_y, 0)
      gdebug.log_info("No suitable terrain found, using random fallback location")
    end

    teleport_to_omt(dest_omt)

    -- Set away status
    storage.is_away_from_home = true
    storage.warp_pulse_count = 0
    storage.raids_total = (storage.raids_total or 0) + 1

    -- Create missions
    missions.create_extraction_mission(dest_omt, storage)
    missions.create_slaughter_mission()
    missions.create_treasure_mission(dest_omt)

    -- Start warp sickness (apply initial effects)
    warp_sickness.start(storage)
    -- Start sickness timer (progressive worsening)
    warp_sickness.start_timer(storage)

    gapi.add_msg("You arrive at the raid location!")
    gapi.add_msg("Find the red room exit portal to return home before warp sickness kills you.")

    return 1
  else
    gapi.add_msg("Warp cancelled.")
    return 0
  end
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

    -- Award material tokens for successful return
    -- Formula from CDDA: lengthofthisraid * 75 + 50
    -- Short raid: 50 tokens, Medium: 125 tokens, Long: 200 tokens
    -- TODO: When raid duration selection is implemented, calculate based on raid length
    local material_tokens = MATERIAL_TOKEN_REWARDS.short
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
