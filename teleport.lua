-- Sky Islands BN Port - Teleportation System
-- Handles warp obelisk, return obelisk, and teleportation logic

local teleport = {}
local util = require("util")

-- Red-room contents are staged in the player's inventory, not in a Lua-only
-- detached_ptr.  The marker and source coordinates are serialized with the
-- item, so an engine autosave/reload cannot destroy a failed transfer.
local ROOM_TRANSFER_VAR = "skyisland_room_transfer"
local red_room_item_storage = {}

-- Red room bounds relative to obelisk position
-- The interior of the room is 3 tiles in one axis and 2 in the other from the obelisk
-- Since the room can rotate, we use 3 for both axes to be safe
local RED_ROOM_RANGE = 3  -- tiles in each direction

-- These items don't disappear when you die. Table tracks how many
-- the player had when they died
local items_preserved_on_death = {
  skyisland_warp_shard = 0,
  skyisland_material_token = 0,
  skyisland_vortex_token = 0,
}

local function item_transfer_marker(item)
  if not item or type(item.get_var_str) ~= "function" then return "" end
  return item:get_var_str(ROOM_TRANSFER_VAR, "")
end

local function marker_position(marker)
  local x, y, z = marker:match("^(%-?%d+),(%-?%d+),(%-?%d+)$")
  if not x then return nil end
  return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

local function staged_items(player)
  local result = {}
  if not player or type(player.all_items) ~= "function" then return result end
  for _, item in ipairs(player:all_items(false)) do
    local marker = item_transfer_marker(item)
    if marker ~= "" and marker_position(marker) then
      table.insert(result, { item = item, marker = marker, position = marker_position(marker) })
    end
  end
  return result
end

local function has_staged_room_items()
  return #staged_items(gapi.get_avatar()) > 0
end

-- Detach each item only long enough to transfer ownership to the character's
-- inventory.  Character inventory is engine-serialized and therefore durable
-- across the autosave/reload boundary.
local function store_red_room_items(obelisk_pos)
  local game_map = gapi.get_map()
  local player = gapi.get_avatar()
  local items_stored = 0
  red_room_item_storage = {}

  util.debug_log(string.format("Scanning red room around obelisk at (%d, %d, %d)",
    obelisk_pos.x, obelisk_pos.y, obelisk_pos.z))

  for dx = -RED_ROOM_RANGE, RED_ROOM_RANGE do
    for dy = -RED_ROOM_RANGE, RED_ROOM_RANGE do
      local check_pos = TripointBubMs.new(
        obelisk_pos.x + dx,
        obelisk_pos.y + dy,
        obelisk_pos.z
      )
      if game_map:has_items_at(check_pos) then
        local items_stack = game_map:get_items_at(check_pos)
        for _, it in ipairs(items_stack:items()) do
          local detached = game_map:detach_item_at(check_pos, it)
          if detached then
            local marker = string.format("%d,%d,%d", check_pos.x, check_pos.y, check_pos.z)
            detached:set_var_str(ROOM_TRANSFER_VAR, marker)
            player:add_item(detached)
            table.insert(red_room_item_storage, { marker = marker, position = {
              x = check_pos.x, y = check_pos.y, z = check_pos.z,
            } })
            items_stored = items_stored + 1
          end
        end
      end
    end
  end

  util.debug_log(string.format("Staged %d room items in serialized inventory", items_stored))
  return items_stored
end

-- Move a staged item while clearing its marker only after ownership leaves
-- the inventory.  On failure, restore the marker before returning it to the
-- durable inventory owner.
local function place_transfer_item(game_map, position, detached)
  local marker = item_transfer_marker(detached)
  detached:set_var_str(ROOM_TRANSFER_VAR, "")
  local failed = game_map:add_item(position, detached)
  if failed then failed:set_var_str(ROOM_TRANSFER_VAR, marker) end
  return failed
end

-- Put staged room items back into their source map after a failed transition.
-- Marked inventory items remain durable even if this operation is interrupted.
local function restore_stored_items_at_source()
  local player = gapi.get_avatar()
  local game_map = gapi.get_map()
  local restored = 0
  for _, entry in ipairs(staged_items(player)) do
    local detached = player:remove_item(entry.item)
    if detached then
      local source = TripointBubMs.new(entry.position.x, entry.position.y, entry.position.z)
      local failed = place_transfer_item(game_map, source, detached)
      if failed then player:add_item(failed) else restored = restored + 1 end
    end
  end
  red_room_item_storage = {}
  util.debug_log(string.format("Restored %d staged room items after failed travel", restored))
  return restored
end

-- Retrieve serialized room items at home.  Failed placement returns ownership
-- to the character inventory, where it survives a save/reload for retry.
local function retrieve_stored_items_at_home(home_pos)
  local player = gapi.get_avatar()
  local game_map = gapi.get_map()
  local entries = staged_items(player)
  local items_retrieved = 0

  util.debug_log(string.format("Retrieving %d staged room items at home (%d, %d, %d)",
    #entries, home_pos.x, home_pos.y, home_pos.z))

  for _, entry in ipairs(entries) do
    local detached = player:remove_item(entry.item)
    if detached then
      local failed = place_transfer_item(game_map, home_pos, detached)
      if failed then
        for radius = 1, 3 do
          if not failed then break end
          for dx = -radius, radius do
            for dy = -radius, radius do
              if math.abs(dx) == radius or math.abs(dy) == radius then
                failed = place_transfer_item(
                  game_map, TripointBubMs.new(home_pos.x + dx, home_pos.y + dy, home_pos.z), failed )
                if not failed then break end
              end
            end
            if not failed then break end
          end
        end
      end
      if failed then player:add_item(failed) else items_retrieved = items_retrieved + 1 end
    end
  end
  red_room_item_storage = {}

  if items_retrieved > 0 then
    gapi.add_msg(string.format(locale.gettext("%d items from the red room were teleported home with you!"), items_retrieved))
  end
  if has_staged_room_items() then
    gapi.add_msg(locale.gettext("Some room items could not be placed yet; they remain safely in your inventory for retry."))
  end
  return items_retrieved
end

function teleport.retry_staged_room_items(storage)
  if storage.is_away_from_home or not has_staged_room_items() then return not has_staged_room_items() end
  retrieve_stored_items_at_home(gapi.get_avatar():get_pos_ms())
  if not has_staged_room_items() then
    teleport.cleanup_raid_dimension(storage)
    return true
  end
  return false
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
    name = locale.gettext("Quick Expedition"),
    description = locale.gettext("Normal time limit (2 hours grace). Exits will be close together."),
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
    name = locale.gettext("Large Expedition"),
    description = locale.gettext("Double time limit (4 hours grace). Exits scattered over wider area."),
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
    name = locale.gettext("Extended Expedition"),
    description = locale.gettext("Triple time limit (6 hours grace). Exits very far away."),
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
    name = locale.gettext("Field"),
    description = locale.gettext("Arrive in a barren field. Usually wilderness, but could be an empty lot in town."),
    terrain_type = "field",
    match_type = OtMatchType.EXACT,
    z_level = 0,
    unlock_key = nil,  -- Always available
    catalyst_item = nil
  },
  basement = {
    name = locale.gettext("Basement"),
    description = locale.gettext("Arrive inside an underground basement. Usually suburbia."),
    terrain_type = "basement",
    match_type = OtMatchType.CONTAINS,
    z_level = -1,
    unlock_key = "basements_unlocked",
    catalyst_item = nil
  },
  roof = {
    name = locale.gettext("Rooftop"),
    description = locale.gettext("Arrive on a building roof. Usually houses, one story up."),
    terrain_type = "roof",
    match_type = OtMatchType.CONTAINS,
    z_level = 1,
    unlock_key = "roofs_unlocked",
    catalyst_item = nil
  },
  labs = {
    name = locale.gettext("Science Lab"),
    description = locale.gettext("Arrive in a subterranean science lab. DANGEROUS! Costs 1 Labs Catalyst. You will be sealed inside - bring an exit strategy!"),
    terrain_type = "lab",
    match_type = OtMatchType.CONTAINS,
    z_level = -2,
    unlock_key = "labs_unlocked",
    catalyst_item = "skyisland_labs_catalyst"
  }
}

local STORAGE_VERSION = 2
local HOME_DIMENSION_ID = "sky_island_home"
-- Keep the complete special inside one overmap, with the surface open to the sky.
local HOME_OMT = { x = 2, y = 2, z = 10 }
local HOME_BOUNDS_MIN_OMT = { x = 0, y = 0, z = 9 }
local HOME_BOUNDS_MAX_OMT = { x = 4, y = 4, z = 10 }
local RAID_DIMENSION_PREFIX = "sky_island_raid_"
local RAID_DIMENSION_STRIDE = 4096
local DESTINATION_SEARCH_ATTEMPTS = 8
local DESTINATION_SEARCH_SAMPLE_LIMIT = 64
local DESTINATION_FALLBACK_SAMPLE_LIMIT = 192

local teleport_to_omt

---@class SkyIslandPosition
---@field x integer
---@field y integer
---@field z integer

---@class SkyIslandHomeStorage
---@field home_location? SkyIslandPosition
---@field home_omt? SkyIslandPosition
---@field home_dimension_id? string
---@field current_raid_dimension_id? string
---@field raid_dimension_serial? integer
---@field skyisland_storage_version? integer

---@param pos SkyIslandPosition
local function abs_omt_from_table(pos)
  return TripointAbsOmt.new(pos.x, pos.y, pos.z)
end

local function dimension_travel_available()
  return gapi and type(gapi.place_player_dimension_at) == "function"
end

local function get_current_dimension_id()
  if gapi and type(gapi.get_current_dimension_id) == "function" then
    return gapi.get_current_dimension_id()
  end
  return ""
end

---@param storage SkyIslandHomeStorage
local function remember_player_home(storage)
  local player = gapi.get_avatar()
  if not player then return end

  local player_pos_ms = player:get_pos_ms()
  local home_abs_ms = gapi.get_map():bub_to_abs(player_pos_ms)
  local home_omt = home_abs_ms:to_omt()

  storage.home_location = { x = home_abs_ms.x, y = home_abs_ms.y, z = home_abs_ms.z }
  storage.home_omt = { x = home_omt.x, y = home_omt.y, z = home_omt.z }
  storage.home_dimension_id = get_current_dimension_id()

  util.debug_log(string.format(
    "Home location set to dim='%s' abs_ms=(%d,%d,%d) omt=(%d,%d,%d)",
    storage.home_dimension_id,
    home_abs_ms.x,
    home_abs_ms.y,
    home_abs_ms.z,
    home_omt.x,
    home_omt.y,
    home_omt.z
  ))
end

local function derive_home_omt_from_location(storage)
  if storage.home_omt or not storage.home_location then
    return
  end

  local home_abs_ms = TripointAbsMs.new(
    storage.home_location.x,
    storage.home_location.y,
    storage.home_location.z
  )
  local home_omt = home_abs_ms:to_omt()
  storage.home_omt = { x = home_omt.x, y = home_omt.y, z = home_omt.z }
end

function teleport.migrate_legacy_storage(storage)
  if (storage.skyisland_storage_version or 0) >= STORAGE_VERSION then
    return
  end

  storage.raid_dimension_serial = storage.raid_dimension_serial or 0
  storage.current_raid_dimension_id = storage.current_raid_dimension_id or nil

  if not storage.home_location and not storage.is_away_from_home then
    remember_player_home(storage)
  end

  derive_home_omt_from_location(storage)

  if storage.home_location and storage.home_dimension_id == nil then
    -- Legacy saves kept the sanctuary in the overworld.  Preserve that home instead
    -- of replacing the player's established island with a fresh pocket copy.
    storage.home_dimension_id = ""
  end

  storage.skyisland_storage_version = STORAGE_VERSION
  util.debug_log(string.format(
    "Migrated Sky Island storage to v%d (home_dim='%s')",
    STORAGE_VERSION,
    tostring(storage.home_dimension_id)
  ))
end

---@param storage SkyIslandHomeStorage
function teleport.ensure_home_dimension(storage)
  if not dimension_travel_available() then
    return false
  end

  if get_current_dimension_id() == HOME_DIMENSION_ID then
    if not storage.home_location then
      remember_player_home(storage)
    end
    storage.home_dimension_id = HOME_DIMENSION_ID
    storage.skyisland_storage_version = STORAGE_VERSION
    return true
  end

  local options = {
    dimension_id = HOME_DIMENSION_ID,
    target_omt = abs_omt_from_table(HOME_OMT),
    world_type = "pocket_dimension",
    bounds_min_omt = abs_omt_from_table(HOME_BOUNDS_MIN_OMT),
    bounds_max_omt = abs_omt_from_table(HOME_BOUNDS_MAX_OMT),
    pregen_special_id = "Sky Island Pocket",
    pregen_special_omt = abs_omt_from_table(HOME_OMT),
  }
  if storage.home_dimension_id == HOME_DIMENSION_ID and storage.home_location then
    -- Re-enter saved islands at the exact saved map-square position.  Using
    -- only target_omt would silently snap branch-era saves to the OMT center.
    options = {
      dimension_id = HOME_DIMENSION_ID,
      target_ms = TripointAbsMs.new(
        storage.home_location.x,
        storage.home_location.y,
        storage.home_location.z
      ),
    }
  elseif storage.home_dimension_id == HOME_DIMENSION_ID and storage.home_omt then
    -- Older pocket saves may have the OMT but not the exact map-square point.
    options = {
      dimension_id = HOME_DIMENSION_ID,
      target_omt = abs_omt_from_table(storage.home_omt),
    }
  end
  local entered = gapi.place_player_dimension_at(options)

  if entered then
    storage.home_dimension_id = HOME_DIMENSION_ID
    remember_player_home(storage)
    storage.skyisland_storage_version = STORAGE_VERSION
    util.debug_log("Sky Island home moved into pocket dimension")
    return true
  end

  gapi.add_msg(locale.gettext("ERROR: Could not enter the Sky Island pocket dimension."))
  util.debug_log("ERROR: place_player_dimension_at failed for Sky Island home")
  return false
end

local function add_location_search_types(params, selected_location, loc_config)
  params:add_type(loc_config.terrain_type, loc_config.match_type)

  if selected_location == "field" then
    params:add_type("forest", OtMatchType.EXACT)
    params:add_type("forest_thick", OtMatchType.EXACT)
  end
end

local function build_location_search_params(selected_location, loc_config, min_distance, max_distance)
  local params = OmtFindParams.new()
  add_location_search_types(params, selected_location, loc_config)
  params:set_search_range(min_distance, max_distance)
  params:set_search_layers(loc_config.z_level, loc_config.z_level)
  return params
end

local function find_raid_destination(search_origin, selected_location, loc_config, config)
  local search_span = math.max(0, config.max_distance - config.min_distance)
  local band_width = math.max(40, math.min(160, math.floor(search_span / 4)))
  local max_band_start = math.max(config.min_distance, config.max_distance - band_width)

  for attempt = 1, DESTINATION_SEARCH_ATTEMPTS do
    local band_min = config.min_distance
    if max_band_start > config.min_distance then
      band_min = gapi.rng(config.min_distance, max_band_start)
    end
    local band_max = math.min(config.max_distance, band_min + band_width)
    local params = build_location_search_params(selected_location, loc_config, band_min, band_max)
    params.max_results = DESTINATION_SEARCH_SAMPLE_LIMIT
    local dest_omt = overmapbuffer.find_random(search_origin, params)

    if dest_omt then
      util.debug_log(string.format(
        "Found raid location on attempt %d in band %d-%d: (%d,%d,%d)",
        attempt,
        band_min,
        band_max,
        dest_omt.x,
        dest_omt.y,
        dest_omt.z
      ))
      return dest_omt
    end
  end

  local fallback_params = build_location_search_params(
    selected_location,
    loc_config,
    config.min_distance,
    config.max_distance
  )
  fallback_params.max_results = DESTINATION_FALLBACK_SAMPLE_LIMIT
  local fallback_dest = overmapbuffer.find_random(search_origin, fallback_params)
  if fallback_dest then
    util.debug_log(string.format("Fallback raid search found location at (%d,%d,%d)", fallback_dest.x, fallback_dest.y, fallback_dest.z))
    return fallback_dest
  end

  local closest_params = build_location_search_params(
    selected_location,
    loc_config,
    config.min_distance,
    config.max_distance
  )
  local closest_dest = overmapbuffer.find_closest(search_origin, closest_params)
  if closest_dest then
    util.debug_log(string.format("Closest raid search found location at (%d,%d,%d)", closest_dest.x, closest_dest.y, closest_dest.z))
    return closest_dest
  end

  return nil
end

local function make_raid_origin(storage, z_level)
  local serial = storage.raid_dimension_serial or 1
  local base = serial * RAID_DIMENSION_STRIDE
  local y_sign = gapi.rng(0, 1) == 0 and -1 or 1
  return TripointAbsOmt.new(
    base + gapi.rng(-1024, 1024),
    (base * y_sign) + gapi.rng(-1024, 1024),
    z_level
  )
end

local function enter_new_raid_dimension(storage, loc_config)
  if not dimension_travel_available() then
    return nil
  end

  storage.raid_dimension_serial = (storage.raid_dimension_serial or 0) + 1
  local raid_dimension_id = string.format("%s%06d", RAID_DIMENSION_PREFIX, storage.raid_dimension_serial)
  local raid_origin = make_raid_origin(storage, loc_config.z_level)

  local entered = gapi.place_player_dimension_at({
    dimension_id = raid_dimension_id,
    target_omt = raid_origin,
    world_type = "default",
  })

  if not entered then
    storage.raid_dimension_serial = storage.raid_dimension_serial - 1
    util.debug_log(string.format("ERROR: Could not enter raid dimension '%s'", raid_dimension_id))
    return nil
  end

  storage.current_raid_dimension_id = raid_dimension_id
  util.debug_log(string.format(
    "Entered raid dimension '%s' at search origin (%d,%d,%d)",
    raid_dimension_id,
    raid_origin.x,
    raid_origin.y,
    raid_origin.z
  ))
  return raid_origin
end

local function get_stored_home_omt(storage)
  local home_omt = storage.home_omt or HOME_OMT
  return TripointAbsOmt.new(home_omt.x, home_omt.y, home_omt.z)
end

local function return_to_home(storage)
  if dimension_travel_available() and storage.home_dimension_id ~= nil then
    -- The engine intentionally treats same-dimension travel as a no-op.  This
    -- matters for a legacy away save whose current dimension is already the
    -- overworld: explicitly place the avatar at the saved MS coordinate.
    if get_current_dimension_id() == storage.home_dimension_id and storage.home_location then
      local home_abs_ms = TripointAbsMs.new(
        storage.home_location.x,
        storage.home_location.y,
        storage.home_location.z
      )
      -- Reload the local map around the saved overmap tile before applying
      -- the exact MS offset; place_player_local_at alone cannot move across
      -- an overworld reality bubble.
      gapi.place_player_overmap_at(home_abs_ms:to_omt())
      local local_pos = gapi.get_map():abs_to_bub(home_abs_ms)
      gapi.place_player_local_at(local_pos)
      gapi.add_msg(locale.gettext("You feel reality shift around you..."))
      return true
    end

    local options = {
      dimension_id = storage.home_dimension_id,
    }
    if storage.home_location then
      -- Preserve the exact home MS coordinate for both pocket and legacy
      -- overworld saves.  target_omt is only a fallback for old incomplete data.
      options.target_ms = TripointAbsMs.new(
        storage.home_location.x,
        storage.home_location.y,
        storage.home_location.z
      )
    else
      options.target_omt = get_stored_home_omt(storage)
    end
    local entered = gapi.place_player_dimension_at(options)

    if not entered then
      gapi.add_msg(locale.gettext("ERROR: Could not return to the Sky Island home dimension."))
      util.debug_log(string.format(
        "ERROR: place_player_dimension_at failed while returning home to '%s'",
        tostring(storage.home_dimension_id)
      ))
      return false
    end

    gapi.add_msg(locale.gettext("You feel reality shift around you..."))
    return true
  end

  if not storage.home_location then
    return false
  end

  local home_abs_ms = TripointAbsMs.new(
    storage.home_location.x,
    storage.home_location.y,
    storage.home_location.z
  )
  local home_omt = home_abs_ms:to_omt()
  teleport_to_omt(home_omt, TripointRelOmt.new(0, -1, 0))
  return true
end

---@param storage SkyIslandHomeStorage
function teleport.cleanup_raid_dimension(storage)
  local raid_dimension_id = storage.current_raid_dimension_id
  if not raid_dimension_id then
    return true
  end

  if not gapi or type(gapi.delete_dimension) ~= "function" then
    return false
  end

  -- delete_dimension fully saves first, so clear the reference before invoking it.
  storage.current_raid_dimension_id = nil
  if gapi.delete_dimension(raid_dimension_id) then
    util.debug_log(string.format("Deleted expedition dimension '%s'", raid_dimension_id))
    return true
  end

  storage.current_raid_dimension_id = raid_dimension_id
  gapi.add_msg(string.format(
    locale.gettext("ERROR: Could not delete expedition dimension '%s'. It will be retried before the next expedition."),
    raid_dimension_id
  ))
  util.debug_log(string.format("ERROR: Could not delete expedition dimension '%s'", raid_dimension_id))
  return false
end

-- Helper: Get player position in OMT coordinates
local function get_player_omt()
  local player = gapi.get_avatar()
  if not player then return nil end

  local pos_ms = player:get_pos_ms()
  local abs_ms = gapi.get_map():bub_to_abs(pos_ms)
  local omt = abs_ms:to_omt()
  return omt
end

-- Filter: Require ROOF flag (for rooftop spawns)
local function roof_filter(game_map, pos)
  local ter_id = game_map:get_ter_at(pos)
  if not ter_id then return false end
  local ter_data = ter_id:obj()
  if not ter_data then return false end
  local has_roof = ter_data:has_flag("ROOF")
  -- util.debug_log(string.format("roof_filter: has_roof=%s", tostring(has_roof)))
  return has_roof
end

-- Helper: Check if a position is safe to spawn
-- additional_filter is an optional func(game_map, pos) for spawn-type-specific checks
local function is_safe_spawn(game_map, pos, additional_filter)
  local ter_id = game_map:get_ter_at(pos)
  if not ter_id then return false end

  local ter_data = ter_id:obj()
  if not ter_data then return false end

  local movecost = ter_data:get_movecost()
  if movecost <= 0 then return false end

  for _, unsafe_flag in pairs({ "DEEP_WATER", "NO_FLOOR" }) do
    if ter_data:has_flag(unsafe_flag) then return false end
  end

  -- local ter_id_str = tostring(ter_id)
  -- util.debug_log(string.format("is_safe_spawn check: ter='%s' movecost=%d", ter_id_str, movecost))

  -- Also check furniture
  local furn_id = game_map:get_furn_at(pos)
  if furn_id then
    local furn_data = furn_id:obj()
    if furn_data then
      local furn_movecost = furn_data:get_movecost()
      -- Furniture movecost of -1 means impassable
      if furn_movecost < 0 then return false end
    end
  end

  -- Apply additional filter if provided
  if additional_filter and not additional_filter(game_map, pos) then
    return false
  end

  return true
end

-- Helper: Find a safe position near the player after teleport
-- additional_filter is an optional func(game_map, pos) for spawn-type-specific checks
local function find_safe_position(player, additional_filter)
  local game_map = gapi.get_map()
  local current_pos = player:get_pos_ms()

  util.debug_log(string.format("find_safe_position: checking at pos (%d, %d, %d)",
    current_pos.x, current_pos.y, current_pos.z))

  -- If current position is safe, no need to move
  if is_safe_spawn(game_map, current_pos, additional_filter) then
    util.debug_log("Current position is safe, no move needed")
    return nil
  end

  util.debug_log("Player landed in unsafe terrain, searching for safe position...")

  -- Search in expanding squares around current position
  for radius = 1, 10 do
    for dx = -radius, radius do
      for dy = -radius, radius do
        -- Only check the edge of the square (optimization)
        if math.abs(dx) == radius or math.abs(dy) == radius then
          local check_pos = TripointBubMs.new(
            current_pos.x + dx,
            current_pos.y + dy,
            current_pos.z
          )
          if is_safe_spawn(game_map, check_pos, additional_filter) then
            util.debug_log(string.format("Found safe position at offset (%d, %d)", dx, dy))
            return check_pos
          end
        end
      end
    end
  end

  util.debug_log("WARNING: Could not find safe position within radius 10!")
  return nil
end

-- Helper: Teleport player to OMT coordinates with offset
-- spawn_filter is an optional func(game_map, pos) for spawn-type-specific safety checks
teleport_to_omt = function(omt, offset_tiles, spawn_filter)
  local player = gapi.get_avatar()

  if player then
    -- we need noclip so that we can avoid falling before we find a safe position
    player:set_mutation(MutationBranchId.new("DEBUG_NOCLIP"))
    util.debug_log(string.format("Teleporting to OMT: %s, %s, %s", omt.x, omt.y, omt.z))
    gapi.place_player_overmap_at(omt)
    -- DEBUG: Show actual position after teleport
    local actual_pos = player:get_pos_ms()
    util.debug_log(string.format("After teleport: pos.z=%d (requested omt.z=%d)", actual_pos.z, omt.z))

    -- If offset specified, move player after teleport
    if offset_tiles then
      local current_pos = player:get_pos_ms()
      local new_pos = TripointBubMs.new(
        current_pos.x + offset_tiles.x,
        current_pos.y + offset_tiles.y,
        current_pos.z + offset_tiles.z
      )
      player:set_pos_ms(new_pos)
      util.debug_log(string.format("Applied offset: %d, %d, %d", offset_tiles.x, offset_tiles.y, offset_tiles.z))
    end

    -- Find safe position if landed in wall or unsafe terrain
    local safe_pos = find_safe_position(player, spawn_filter)
    if safe_pos then
      player:set_pos_ms(safe_pos)
      util.debug_log("Moved player to safe position")
    end
    player:unset_mutation(MutationBranchId.new("DEBUG_NOCLIP"))
  end

  gapi.add_msg(locale.gettext("You feel reality shift around you..."))
end

-- Helper: Apply warpcloak landing protection effects
-- Base effect: 60 seconds of invisibility + feather fall
-- Conditional bonuses based on upgrades
local function apply_landing_protection(storage)
  local player = gapi.get_avatar()
  if not player then return end

  -- Base warpcloak duration: 60 seconds
  local cloak_duration = TimeDuration.from_seconds(60)

  -- Apply base warpcloak (invisibility + feather fall)
  local warpcloak_id = EffectTypeId.new("skyisland_warpcloak")
  player:add_effect(warpcloak_id, cloak_duration)
  util.debug_log("Applied warpcloak landing protection (60s)")

  -- Check for landing upgrades and apply bonus effects

  -- Scouting clairvoyance bonus (based on upgrade level)
  local clairvoyance_time = storage.scouting_clairvoyance_time or 0
  if clairvoyance_time > 0 then
    local clairvoyance_id = EffectTypeId.new("skyisland_clairvoyance")
    local clairvoyance_duration = TimeDuration.from_seconds(clairvoyance_time)
    player:add_effect(clairvoyance_id, clairvoyance_duration)
    util.debug_log(string.format("Applied scouting clairvoyance (%ds)", clairvoyance_time))
  end

  -- Landing flight bonus (real flight via mutation)
  if storage.landing_flight_unlocked then
    local flight_trait = MutationBranchId.new("SKYISLAND_WARP_FLIGHT")
    player:set_mutation(flight_trait)
    gapi.add_msg(locale.gettext("Warp energy lifts you into the air!"))
    util.debug_log("Applied landing flight mutation (60s)")

    -- Schedule removal of flight mutation after 60 seconds
    gapi.add_on_every_x_hook(cloak_duration, function()
      local p = gapi.get_avatar()
      if p then
        p:unset_mutation(flight_trait)
        gapi.add_msg(locale.gettext("Your feet touch the ground as the warp flight fades."))
        util.debug_log("Removed landing flight mutation")
      end
      return false  -- One-shot: stop after first execution
    end)
  end
end

-- Sanctuary animals remain in the persistent home dimension while the player
-- raids.  Do not serialize visible monsters and respawn copies on return: the
-- old snapshot/restore path duplicated every friendly animal on each raid.
local function save_island_animals(storage)
  storage.island_animals = nil
end

local function restore_island_animals(storage)
  -- Discard queues written by older versions.  Their source monsters were never
  -- transferred out of the home map, so replaying them would duplicate them.
  storage.island_animals = nil
  return 0
end

-- Spawn warped animals at home location.  As with island animals, retain
-- failed entries so a transient map/load failure cannot duplicate or lose them.
local warped_spawn_scheduled = false
function teleport.spawn_warped_animals(storage)
  if not storage.warped_animals or #storage.warped_animals == 0 then
    return 0
  end
  if warped_spawn_scheduled then return #storage.warped_animals end

  warped_spawn_scheduled = true
  util.debug_log(string.format("Queuing %d animals for delayed spawn", #storage.warped_animals))
  gapi.add_on_every_x_hook(TimeDuration.from_seconds(1), function()
    -- Never deliver captured animals into an active raid dimension.
    if storage.is_away_from_home then
      warped_spawn_scheduled = false
      return false
    end
    local player = gapi.get_avatar()
    if not player then
      -- Keep the periodic callback alive until the avatar/map is available;
      -- the serialized queue remains the durable fallback across reload.
      return true
    end

    local player_pos = player:get_pos_ms()
    local remaining = {}
    local spawned_count = 0
    for _, animal_data in ipairs(storage.warped_animals or {}) do
      local type_str = animal_data.type_id
      local extracted = type_str:match("MonsterTypeId%[(.+)%]")
      if extracted then type_str = extracted end
      local spawned_monster = gapi.place_monster_around(MonsterTypeId.new(type_str), player_pos, 3)
      if spawned_monster then
        spawned_monster:set_hp(animal_data.hp)
        spawned_monster:make_friendly()
        spawned_count = spawned_count + 1
        util.debug_log(string.format("Spawned: %s with HP %d", type_str, animal_data.hp))
      else
        table.insert(remaining, animal_data)
        util.debug_log(string.format("FAILED to spawn: %s", type_str))
      end
    end
    storage.warped_animals = remaining
    warped_spawn_scheduled = false

    if spawned_count > 0 then
      gapi.add_msg(string.format(locale.gettext("%d warped animal%s arrived at your island!"),
        spawned_count, spawned_count > 1 and "s" or ""))
    end
    return false
  end)
  return #storage.warped_animals
end

-- Re-arm delayed animal delivery after a save/reload that happened between
-- travel and the one-shot callback.
function teleport.restore_pending_animals(storage)
  if storage.is_away_from_home then return end
  restore_island_animals(storage)
  teleport.spawn_warped_animals(storage)
end

-- Use warp obelisk - start expedition
function teleport.use_warp_obelisk(who, item, pos, storage, missions, warp_sickness)
  if storage.is_away_from_home then
    gapi.add_msg(locale.gettext("You are already on an expedition!"))
    return 0
  end

  teleport.migrate_legacy_storage(storage)

  if dimension_travel_available() and not teleport.cleanup_raid_dimension(storage) then
    return 0
  end

  -- New saves keep the sanctuary in a bounded pocket dimension.  Legacy saves
  -- keep their original overworld sanctuary so existing island changes survive.
  if dimension_travel_available() and storage.home_dimension_id == HOME_DIMENSION_ID then
    if not teleport.ensure_home_dimension(storage) then
      return 0
    end
    who = gapi.get_avatar()
  elseif not storage.home_location then
    remember_player_home(storage)
  end

  -- Also get OMT for legacy same-dimension teleportation/search fallback.
  local home_omt = get_player_omt()
  if not home_omt then
    gapi.add_msg(locale.gettext("ERROR: Could not determine position!"))
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
  ui:add(menu_index, string.format(locale.gettext("%s (reward: %d tokens)"), RAID_CONFIG.short.name, RAID_CONFIG.short.material_tokens))
  raid_options[menu_index] = "short"
  menu_index = menu_index + 1

  -- Medium raids require upgrade
  if longer_raids >= 1 then
    ui:add(menu_index, string.format(locale.gettext("%s (reward: %d tokens)"), RAID_CONFIG.medium.name, RAID_CONFIG.medium.material_tokens))
    raid_options[menu_index] = "medium"
    menu_index = menu_index + 1
  end

  -- Long raids require further upgrade
  if longer_raids >= 2 then
    ui:add(menu_index, string.format(locale.gettext("%s (reward: %d tokens)"), RAID_CONFIG.long.name, RAID_CONFIG.long.material_tokens))
    raid_options[menu_index] = "long"
    menu_index = menu_index + 1
  end

  ui:add(menu_index, locale.gettext("Cancel"))

  local choice = ui:query()
  local selected_raid = raid_options[choice]

  if not selected_raid then
    gapi.add_msg(locale.gettext("Warp cancelled."))
    return 0
  end

  local config = RAID_CONFIG[selected_raid]

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
      has_catalyst = who:has_item_with_id(ItypeId.new(loc_config.catalyst_item), false)
      if not has_catalyst then
        suffix = locale.gettext(" [No Catalyst]")
      end
    end

    if is_unlocked then
      local display_name = loc_config.name
      if loc_config.catalyst_item then
        display_name = display_name .. locale.gettext(" (requires catalyst)")
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
    gapi.add_msg(locale.gettext("Warp cancelled."))
    return 0
  end

  local loc_config = LOCATION_CONFIG[selected_location]

  -- Consume catalyst if required
  if loc_config.catalyst_item then
    local catalyst_id = ItypeId.new(loc_config.catalyst_item)
    local catalyst_item = who:get_item_with_id(catalyst_id, false)
    if catalyst_item then
      if catalyst_item:is_stackable() and catalyst_item.charges > 1 then
        catalyst_item:mod_charges(-1)
      else
        who:remove_item(catalyst_item)
      end
    end
    gapi.add_msg(locale.gettext("The Labs Catalyst crumbles to dust as dimensional barriers part..."))
  end

  gapi.add_msg(string.format(locale.gettext("Initiating %s to %s..."), config.name, loc_config.name))
  save_island_animals(storage)
  gapi.add_msg(locale.gettext("Searching for suitable location..."))

  local search_origin = nil
  if dimension_travel_available() then
    search_origin = enter_new_raid_dimension(storage, loc_config)
    if not search_origin then
      gapi.add_msg(locale.gettext("WARNING: Could not create a fresh expedition dimension. Aborting warp."))
      restore_island_animals(storage)
      if loc_config.catalyst_item then
        who:add_item_with_id(ItypeId.new(loc_config.catalyst_item), 1)
        gapi.add_msg(locale.gettext("Your Labs Catalyst is returned."))
      end
      return 0
    end
  else
    -- Use ground-level origin for legacy same-world searches (sky islands are at z > 0).
    search_origin = TripointAbsOmt.new(home_omt.x, home_omt.y, loc_config.z_level)
  end

  util.debug_log(string.format("Searching for %s terrain in range %d-%d at z=%d from (%d, %d, %d)",
    loc_config.terrain_type, config.min_distance, config.max_distance, loc_config.z_level,
    search_origin.x, search_origin.y, search_origin.z))

  local dest_omt = find_raid_destination(search_origin, selected_location, loc_config, config)

  if dest_omt then
    util.debug_log(string.format("Found raid location at (%d, %d, %d)", dest_omt.x, dest_omt.y, dest_omt.z))
    util.debug_log(string.format("Found %s at z=%d (searched z=%d)", loc_config.terrain_type, dest_omt.z, loc_config.z_level))
  else
    gapi.add_msg("WARNING: Could not find suitable terrain. Aborting warp.")
    util.debug_log("ERROR: Terrain search failed!")
    local returned_home = not dimension_travel_available()
    if dimension_travel_available() then
      returned_home = return_to_home(storage)
      if returned_home then teleport.cleanup_raid_dimension(storage) end
    end
    if returned_home then restore_island_animals(storage) end
    -- Refund catalyst if we consumed one
    if loc_config.catalyst_item then
      who:add_item_with_id(ItypeId.new(loc_config.catalyst_item), 1)
      gapi.add_msg("Your Labs Catalyst is returned.")
    end
    return 0
  end

  -- Two-stage teleport to prevent map revelation from z=10 in legacy same-world mode.
  if not dimension_travel_available() then
    local intermediate_omt = TripointAbsOmt.new(home_omt.x, home_omt.y, 0)
    util.debug_log("Intermediate teleport to z=0 to prevent map revelation")
    gapi.place_player_overmap_at(intermediate_omt)
  end

  -- Determine spawn filter based on location type
  local spawn_filter = nil
  if selected_location == "roof" then
    spawn_filter = roof_filter
  end

  -- Now teleport to actual destination
  teleport_to_omt(dest_omt, nil, spawn_filter)

  -- Store raid configuration only after all fallible destination work has
  -- succeeded, so cancellation/failure cannot poison the next reward.
  storage.current_raid_type = selected_raid
  storage.current_raid_pulse_multiplier = config.pulse_multiplier
  storage.current_mission_min = config.mission_min
  storage.current_mission_max = config.mission_max
  storage.current_exit_min = config.exit_min
  storage.current_exit_max = config.exit_max

  -- Apply warpcloak landing protection (invisibility + feather fall + bonuses)
  apply_landing_protection(storage)

  -- Reveal overmap if scouting is unlocked
  local scouting_level = storage.scouting_unlocked or 0
  if scouting_level > 0 then
    local reveal_radius = scouting_level == 1 and 1 or 2  -- 3x3 or 5x5
    for dx = -reveal_radius, reveal_radius do
      for dy = -reveal_radius, reveal_radius do
        local reveal_pos = TripointAbsOmt.new(dest_omt.x + dx, dest_omt.y + dy, dest_omt.z)
        overmapbuffer.set_seen(reveal_pos, true)
      end
    end
    local area_size = (reveal_radius * 2 + 1)
    gapi.add_msg(string.format(locale.gettext("Your scouting reveals a %dx%d area around the landing zone."), area_size, area_size))
  end

  -- Set away status
  storage.is_away_from_home = true
  storage.warp_pulse_count = 0
  storage.raids_total = (storage.raids_total or 0) + 1

  -- Create missions
  missions.create_extraction_mission(dest_omt, storage)

  -- Bonus missions: tier determines how many missions per expedition
  local bonus_tier = storage.bonus_missions_tier or 0
  for i = 1, bonus_tier do
    missions.create_bonus_mission(dest_omt, storage)
  end

  -- Slaughter missions (kill X of species) require upgrade
  if storage.slaughter_unlocked then
    missions.create_slaughter_mission(dest_omt, storage)
  end

  -- Start warp sickness (reset counters for new expedition)
  -- The global hook is already running and will start accumulating time
  warp_sickness.start(storage)

  gapi.add_msg(string.format(locale.gettext("You arrive at the %s!"), loc_config.name:lower()))
  gapi.add_msg(locale.gettext("Find the red room exit portal to return home before warp sickness kills you."))

  return 1
end

-- Use return obelisk - return home
function teleport.use_return_obelisk(who, item, pos, storage, missions, warp_sickness)
  if not storage.is_away_from_home then
    gapi.add_msg(locale.gettext("You are already home!"))
    return 0
  end

  if not storage.home_location then
    gapi.add_msg(locale.gettext("ERROR: Home location not set!"))
    return 0
  end

  local confirm_ui = UiList.new()
  confirm_ui:title(locale.gettext("Return home?"))
  confirm_ui:add(1, locale.gettext("Yes, return home"))
  confirm_ui:add(2, locale.gettext("No, stay"))
  local confirm = confirm_ui:query()

  if confirm == 1 then
    -- Check return behavior setting
    -- 0 = whole_room (always), 1 = whole_room_cost (needs vortex token), 2 = self_only (never)
    local return_behavior = storage.difficulty_return_behavior or 1
    local items_stored = 0
    local vortex_item
    local vortex_id = ItypeId.new("skyisland_vortex_token")

    if return_behavior == 0 then
      -- Whole Room: Always teleport room contents
      items_stored = store_red_room_items(pos)
    elseif return_behavior == 1 then
      -- Whole Room for Cost.  Do not consume the token until the destination
      -- transition succeeds; a failed travel must be fully retryable.
      if who:has_item_with_id(vortex_id, false) then
        vortex_item = who:get_item_with_id(vortex_id, false)
        items_stored = store_red_room_items(pos)
      else
        gapi.add_msg(locale.gettext("Without a Vortex Token, only items you carry will return with you."))
      end
    else
      -- Self Only: Never teleport room contents
      gapi.add_msg(locale.gettext("Only items you carry will return with you."))
    end

    if not return_to_home(storage) then
      restore_stored_items_at_source()
      return 0
    end

    if vortex_item then
      if vortex_item:is_stackable() and vortex_item.charges > 1 then
        vortex_item:mod_charges(-1)
      else
        who:remove_item(vortex_item)
      end
      gapi.add_msg(locale.gettext("The Vortex Token crumbles as it pulls the room's contents into the warp!"))
    end

    -- Retrieve serialized room items at home, including items staged before a
    -- save/reload where the local count is no longer available.
    if items_stored > 0 or has_staged_room_items() then
      local player = gapi.get_avatar()
      retrieve_stored_items_at_home(player:get_pos_ms())
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
    gapi.add_msg(string.format(locale.gettext("You've returned home safely! Earned %d material tokens."), material_tokens))

    -- Clear away status and increment wins
    storage.is_away_from_home = false
    storage.warp_pulse_count = 0
    local old_raids_won = storage.raids_won or 0
    storage.raids_won = old_raids_won + 1

    -- Stop warp sickness (remove all effects)
    warp_sickness.stop(storage)

    -- Spawn any warped animals
    teleport.spawn_warped_animals(storage)

    -- Restore island animals that were saved before departure
    restore_island_animals(storage)

    -- Check for progress gate rank-ups (automatic at 10 and 20 wins)
    if old_raids_won < 10 and storage.raids_won >= 10 then
      gapi.add_msg(locale.gettext("=== RANK UP ==="))
      gapi.add_msg(locale.gettext("You have survived 10 expeditions and achieved Adept rank!"))
      gapi.add_msg(locale.gettext("New features and recipes may now be available."))
    elseif old_raids_won < 20 and storage.raids_won >= 20 then
      gapi.add_msg(locale.gettext("=== RANK UP ==="))
      gapi.add_msg(locale.gettext("You have survived 20 expeditions and achieved Master rank!"))
      gapi.add_msg(locale.gettext("New features and recipes may now be available."))
    end

    gapi.add_msg(string.format(locale.gettext(
      "Stats: %d/%d raids completed successfully"),
      storage.raids_won,
      storage.raids_total
    ))

    if not has_staged_room_items() then
      teleport.cleanup_raid_dimension(storage)
    end
    return 1
  else
    gapi.add_msg(locale.gettext("Cancelled."))
    return 0
  end
end

-- Return home successfully (used by return obelisk and skyward beacon)
-- Does NOT prompt for confirmation - caller should handle that
function teleport.return_home_success(storage, missions, warp_sickness, defer_cleanup)
  if not storage.home_location then
    gapi.add_msg(locale.gettext("ERROR: Home location not set!"))
    return false
  end
  if not storage.is_away_from_home then
    return false
  end

  if not return_to_home(storage) then
    return false
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
  gapi.add_msg(string.format(locale.gettext("You've returned home safely! Earned %d material tokens."), material_tokens))

  -- Clear away status and increment wins
  storage.is_away_from_home = false
  storage.warp_pulse_count = 0
  local old_raids_won = storage.raids_won or 0
  storage.raids_won = old_raids_won + 1

  -- Stop warp sickness (remove all effects)
  warp_sickness.stop(storage)

  -- Spawn any warped animals
  teleport.spawn_warped_animals(storage)

  -- Restore island animals that were saved before departure
  restore_island_animals(storage)

  -- Check for progress gate rank-ups (automatic at 10 and 20 wins)
  if old_raids_won < 10 and storage.raids_won >= 10 then
    gapi.add_msg(locale.gettext("=== RANK UP ==="))
    gapi.add_msg(locale.gettext("You have survived 10 expeditions and achieved Adept rank!"))
    gapi.add_msg(locale.gettext("New features and recipes may now be available."))
  elseif old_raids_won < 20 and storage.raids_won >= 20 then
    gapi.add_msg(locale.gettext("=== RANK UP ==="))
    gapi.add_msg(locale.gettext("You have survived 20 expeditions and achieved Master rank!"))
    gapi.add_msg(locale.gettext("New features and recipes may now be available."))
  end

  gapi.add_msg(string.format(locale.gettext(
    "Stats: %d/%d raids completed successfully"),
    storage.raids_won,
    storage.raids_total
  ))

  if not defer_cleanup then
    teleport.cleanup_raid_dimension(storage)
  end
  return true
end

-- Helper: Count stackable items by ID
local function count_item_charges(player, item_id)
  local total = 0
  local all_items = player:all_items(false)
  for _, item in ipairs(all_items) do
    if item:get_type():str() == item_id then
      if item:is_stackable() then
        total = total + item.charges
      else
        total = total + 1
      end
    end
  end
  return total
end

-- Resurrection handler - teleport player home after death
function teleport.resurrect_at_home(storage, missions, warp_sickness)
  if not storage.home_location then
    return false  -- No home to resurrect at
  end
  if not storage.is_away_from_home then
    return false
  end

  util.debug_log("Sky Islands: Resurrecting at home")

  local player = gapi.get_avatar()
  if not player then return false end

  -- Travel first.  If the engine rejects the destination, retain the player's
  -- inventory and raid state so a later retry is safe.
  if not return_to_home(storage) then
    return false
  end

  -- Check for token bag and preserve tokens before dropping items
  for item in pairs(items_preserved_on_death) do
    items_preserved_on_death[item] = count_item_charges(player, item)
  end

  -- DROP ALL ITEMS before teleporting - this is the death penalty!
  -- Items are dropped at the death location (lost forever)
  player:drop_all_items()
  gapi.add_msg(locale.gettext("Your belongings scatter as reality tears you away..."))

  -- Clear any warped animals - they're lost on death
  if storage.warped_animals and #storage.warped_animals > 0 then
    local lost_count = #storage.warped_animals
    storage.warped_animals = {}
    gapi.add_msg(string.format(locale.gettext("%d warped animal%s lost in the void..."),
      lost_count, lost_count > 1 and "s were" or " was"))
  end

  local home_abs_ms = TripointAbsMs.new(
    storage.home_location.x,
    storage.home_location.y,
    storage.home_location.z
  )
  local local_pos = gapi.get_map():abs_to_bub(home_abs_ms)

  -- Fail all raid missions on death
  missions.fail_all_raid_missions(player)

  -- Mark raid as failed
  storage.is_away_from_home = false
  storage.warp_pulse_count = 0
  storage.raids_lost = (storage.raids_lost or 0) + 1

  -- Stop warp sickness (remove all effects before applying resurrection sickness)
  warp_sickness.stop(storage)

  -- Apply resurrection sickness
  warp_sickness.apply_resurrection_sickness()

  gapi.add_msg(locale.gettext("You respawn at home, naked and wounded!"))
  util.debug_log(string.format("Resurrected at home abs_ms: %d, %d, %d", home_abs_ms.x, home_abs_ms.y, home_abs_ms.z))
  util.debug_log(string.format("local pos: %d, %d, %d", local_pos.x, local_pos.y, local_pos.z))

  -- Restore preserved items
  local player_pos = player:get_pos_ms()
  for item, count in pairs(items_preserved_on_death) do
    if count > 0 then
      util.debug_log(local_pos)
      local item_id = ItypeId.new(item)
      local items = gapi.create_item(item_id, count)
      gapi.get_map():add_item(player_pos, items)
    end
    items_preserved_on_death[item] = 0
  end

  teleport.cleanup_raid_dimension(storage)
  return true
end

return teleport
