-- Run only in a disposable BN world with CBN_Sky_Island enabled.
-- Require tests.native_death from this mod in the Lua console, then call
-- setup(), failed(), arm(), verify().
local checks = {}
local snapshot = {}
local token_id = "skyisland_vortex_token"
local shard_id = "skyisland_warp_shard"
local function storage() return game.mod_storage["CBN_Sky_Island"] end
local function tokens(player, id)
  local total = 0
  for _, item in ipairs(player:all_items(false)) do
    if item:get_type():str() == id then total = total + item.charges end
  end
  return total
end
local function tagged(player, key, value)
  for _, item in ipairs(player:all_items(false)) do
    if item:get_var_str(key, "") == value then return item end
  end
end
function checks.setup()
  local player = gapi.get_avatar()
  local state = storage()
  assert(not state.is_away_from_home)
  assert(gapi.get_current_dimension_id() == state.home_dimension_id)
  local home = TripointAbsMs.new(state.home_location.x, state.home_location.y, state.home_location.z)
  gapi.place_player_overmap_at(home:to_omt())
  gapi.place_player_local_at(gapi.get_map():abs_to_bub(home))
  player:clear_effects()
  player:set_all_parts_hp_to_max()
  player:set_pain(0)
  player:drop_all_items()
  snapshot.home = { x=home.x, y=home.y, z=home.z }
  snapshot.dimension = state.home_dimension_id
  snapshot.home_vortex, snapshot.home_shards = 0, 0
  for _, item in ipairs(gapi.get_map():get_items_at(player:get_pos_ms()):items()) do
    if item:get_type():str() == token_id then snapshot.home_vortex = snapshot.home_vortex + item.charges end
    if item:get_type():str() == shard_id then snapshot.home_shards = snapshot.home_shards + item.charges end
  end
  snapshot.lost = state.raids_lost
  snapshot.won = state.raids_won
  snapshot.vortex = tokens(player, token_id) + 1000011
  snapshot.shards = tokens(player, shard_id) + 13
  local bag = player:create_item(ItypeId.new("backpack"), -1)
  bag:set_var_str("native_bag", "worn")
  bag:add_item_with_id(ItypeId.new(token_id), 1000011)
  bag:add_item_with_id(ItypeId.new("rock"), -1)
  local deep = player:create_item(ItypeId.new("backpack"), -1)
  deep:set_var_str("native_deep", "inventory")
  deep:add_item_with_id(ItypeId.new("bottle_plastic"), -1)
  for _, item in ipairs(player:all_items(false)) do
    if item:get_type():str() == "bottle_plastic" then
      item:set_var_str("native_nested", "bottle")
      item:add_item_with_id(ItypeId.new(shard_id), 13)
      break
    end
  end
  assert(player:wear(bag, false))
  local knife = player:create_item(ItypeId.new("knife"), -1)
  knife:set_var_str("native_weapon", "original")
  assert(player:wield(knife))
  gapi.place_player_overmap_at(TripointAbsOmt.new(5, 5, 0))
  state.is_away_from_home = true
  state.raids_total = state.raids_total + 1
  local source = player:get_pos_ms()
  snapshot.source = { x=player:abs_pos().x, y=player:abs_pos().y, z=player:abs_pos().z }
  gapi.get_map():create_item_at(source, ItypeId.new("rock"), -1)
  for _, item in ipairs(gapi.get_map():get_items_at(source):items()) do
    item:set_var_str("native_ground", "preexisting")
  end
  print("PASS native death fixture: equipped roots, two-level tokens, preexisting ground")
end
function checks.failed(placement_failure)
  local player = gapi.get_avatar()
  local current = storage()
  assert(current.is_away_from_home and current.home_dimension_id == "")
  local source = player:abs_pos()
  snapshot.source = { x=source.x, y=source.y, z=source.z }
  snapshot.home = current.home_location
  snapshot.dimension = current.home_dimension_id
  snapshot.lost, snapshot.won = current.raids_lost, current.raids_won
  snapshot.vortex, snapshot.shards = tokens(player, token_id), tokens(player, shard_id)
  snapshot.home_vortex, snapshot.home_shards = 0, 0
  local home = TripointAbsMs.new(snapshot.home.x, snapshot.home.y, snapshot.home.z)
  gapi.place_player_overmap_at(home:to_omt())
  for _, item in ipairs(gapi.get_map():get_items_at(gapi.get_map():abs_to_bub(home)):items()) do
    if item:get_type():str() == token_id then snapshot.home_vortex = snapshot.home_vortex + item.charges end
    if item:get_type():str() == shard_id then snapshot.home_shards = snapshot.home_shards + item.charges end
  end
  gapi.place_player_overmap_at(source:to_omt())
  gapi.place_player_local_at(gapi.get_map():abs_to_bub(source))
  local original = gapi
  local state = storage()
  local home_dimension = state.home_dimension_id
  state.home_dimension_id = "native_failure_target"
  local calls = 0
  gapi = setmetatable({ place_player_dimension_at=function() calls=calls+1; return false end }, { __index=original })
  local ok, result = pcall(function()
    return require("teleport").resurrect_at_home(storage(), require("missions"), require("warp_sickness"))
  end)
  gapi = original
  state.home_dimension_id = home_dimension
  assert(ok, result)
  assert(calls == (placement_failure and 0 or 1) and not result)
  local player = gapi.get_avatar()
  assert(storage().is_away_from_home and storage().raids_lost == snapshot.lost)
  assert(player:is_wielding(assert(tagged(player, "native_weapon", "original"))))
  local worn = false
  for _, item in ipairs(player:get_worn_items()) do
    if item:get_var_str("native_bag", "") == "worn" then worn = true end
  end
  assert(worn)
  assert(not tagged(player, "native_ground", "preexisting"))
  assert(tokens(player, token_id) == snapshot.vortex)
  assert(tokens(player, shard_id) == snapshot.shards)
  print("PASS native failed death travel: exact equipment, token totals, ground untouched")
end
function checks.map_failed()
  local original = gapi
  gapi = setmetatable({ get_map=function()
    local real = original.get_map()
    return setmetatable({ add_item=function(_, _, item) return item end }, {
      __index=function(_, key) return function(_, ...) return real[key](real, ...) end end,
    })
  end }, { __index=original })
  local ok, result = pcall(function() checks.failed(true) end)
  gapi = original
  assert(ok, result)
  print("PASS native rejected source placement: equipped roots restored before travel")
end
function checks.arm()
  snapshot.armed = true
  package.loaded.teleport = nil
  gdebug.reload_lua_code()
  gapi.get_avatar():set_all_parts_hp_cur(0)
  print("Armed actual engine death; leave console and advance one turn")
end
function checks.verify()
  local player = gapi.get_avatar()
  local state = storage()
  local home = player:abs_pos()
  assert(snapshot.armed and player:get_part_hp_cur(BodyPartTypeId.new("torso"):int_id()) == 10)
  assert(not state.is_away_from_home and state.raids_lost == snapshot.lost + 1)
  assert(state.raids_won == snapshot.won)
  assert(gapi.get_current_dimension_id() == snapshot.dimension)
  assert(home.x == snapshot.home.x and home.y == snapshot.home.y and home.z == snapshot.home.z)
  assert(not tagged(player, "native_weapon", "original"))
  assert(not tagged(player, "native_bag", "worn"))
  assert(not tagged(player, "native_nested", "bottle"))
  local vortex = tokens(player, token_id)
  local shards = tokens(player, shard_id)
  for _, item in ipairs(gapi.get_map():get_items_at(player:get_pos_ms()):items()) do
    if item:get_type():str() == token_id then vortex = vortex + item.charges end
    if item:get_type():str() == shard_id then shards = shards + item.charges end
  end
  assert(vortex == snapshot.vortex + snapshot.home_vortex and shards == snapshot.shards + snapshot.home_shards)
  local source = TripointAbsMs.new(snapshot.source.x, snapshot.source.y, snapshot.source.z)
  gapi.place_player_overmap_at(source:to_omt())
  local local_source = gapi.get_map():abs_to_bub(source)
  local bag, knife, ground, deep = false, false, false, false
  for _, item in ipairs(gapi.get_map():get_items_at(local_source):items()) do
    bag = bag or item:get_var_str("native_bag", "") == "worn"
    knife = knife or item:get_var_str("native_weapon", "") == "original"
    ground = ground or item:get_var_str("native_ground", "") == "preexisting"
    deep = deep or item:get_var_str("native_deep", "") == "inventory"
    if item:get_var_str("native_bag", "") == "worn" then
      assert(not item:has_item_with_id(ItypeId.new(token_id), false))
    end
  end
  assert(bag and knife and ground and deep)
  print("PASS actual engine death: exact home, million tokens, nested tokens, source belongings")
end
return checks
