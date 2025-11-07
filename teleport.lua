-- Sky Islands BN Port - Teleportation System
-- Handles warp obelisk, return obelisk, and teleportation logic

local teleport = {}

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

    -- Teleport to random location at ground level (z=0)
    -- Distance: 5-30 OM tiles from home (matching CDDA short raid)
    local distance = gapi.rng(5, 30)
    local angle = gapi.rng(0, 359) * (math.pi / 180)  -- Random angle in radians
    local dx = math.floor(distance * math.cos(angle))
    local dy = math.floor(distance * math.sin(angle))

    local dest_omt = Tripoint.new(
      home_omt.x + dx,
      home_omt.y + dy,
      0  -- Always teleport to ground level to avoid fall damage
    )

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
  gapi.add_msg("Using emergency warp to return home...")

  local player = gapi.get_avatar()
  if not player then return end

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

  gapi.add_msg("You respawn at home, badly wounded!")
  gdebug.log_info(string.format("Resurrected at home abs_ms: %d, %d, %d", home_abs_ms.x, home_abs_ms.y, home_abs_ms.z))
end

return teleport
