"""Run with: python3 -m unittest discover -s tests"""

import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


TELEPORT_FIXTURE = r'''
package.loaded.util = { debug_log = function() end }
locale = { gettext = function(text) return text end }
OtMatchType = { EXACT = 1, CONTAINS = 2 }
TripointAbsOmt = { new = function(x, y, z) return { x=x, y=y, z=z } end }
TripointAbsMs = { new = function(x, y, z)
  return { x=x, y=y, z=z, to_omt=function(self)
    return TripointAbsOmt.new(math.floor(self.x / 24), math.floor(self.y / 24), self.z)
  end }
end }
TripointBubMs = { new = function(x, y, z) return { x=x, y=y, z=z } end }
TripointRelOmt = { new = function(x, y, z) return { x=x, y=y, z=z } end }
MutationBranchId = { new = function(id) return id end }
EffectTypeId = { new = function(id) return id end }
ItypeId = { new = function(id) return id end }
MonsterTypeId = { new = function(id) return id end }
TimeDuration = { from_seconds = function(value) return value end }
OmtFindParams = { new = function()
  local p = { types = {}, max_results = nil }
  function p:add_type(id, match) table.insert(self.types, { id=id, match=match }) end
  function p:set_search_range(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
  function p:set_search_layers(minimum, maximum) self.z_min, self.z_max = minimum, maximum end
  return p
end }
local state
local function fresh_item(id, charges)
  return {
    id = id, charges = charges or 1, vars = {},
    is_stackable = function(self) return self.charges > 1 end,
    mod_charges = function(self, amount) self.charges = self.charges + amount end,
    get_var_str = function(self, key, default) return self.vars[key] or default end,
    set_var_str = function(self, key, value) self.vars[key] = value end,
    get_type = function(self) return { str=function() return self.id end } end,
    has_item_with_id = function(self, id) return self.contains and self.contains[id] == true end,
  }
end
local avatar_available = true
local current_dim
local player = {
  pos = { x=12, y=12, z=10 }, inventory = {},
  get_pos_ms = function(self) return self.pos end,
  set_pos_ms = function(self, pos) self.pos = pos end,
  set_mutation = function() end, unset_mutation = function() end,
  add_effect = function() end,
  has_item_with_id = function(self, id) return self.inventory[id] ~= nil end,
  get_item_with_id = function(self, id) return self.inventory[id] end,
  remove_item = function(self, item)
    for id, candidate in pairs(self.inventory) do
      if candidate == item then self.inventory[id] = nil; state.removed_items = state.removed_items + 1; return candidate end
    end
    return nil
  end,
  add_item = function(self, item)
    self.inventory[item.id] = item
  end,
  add_item_with_id = function(self, id, count)
    local item = self.inventory[id]
    if not item then item = fresh_item(id, 0); self.inventory[id] = item end
    item.charges = item.charges + count
  end,
  healall = function() end,
  clear_effects = function() end,
  set_all_parts_hp_to_max = function() end,
  get_worn_items = function(self) return self.worn_items or {} end,
  has_weapon = function(self) return self.wielded ~= nil end,
  can_wield = function(_, item) return item.id == "weapon" end,
  wield = function(self, item) self.wielded = item; self.inventory[item.id] = nil; return true end,
  wear = function(self, item) table.insert(self.worn_items, item); self.inventory[item.id] = nil; return true end,
  all_items = function(self)
    local items = {}
    for _, item in pairs(self.inventory) do table.insert(items, item) end
    return items
  end,
  drop_all_items = function(self)
    state.drop_dimension = current_dim
    state.drop_position = self.pos
    local map_here = gapi.get_map()
    for _, item in pairs(self.inventory) do map_here:add_item(self.pos, item) end
    for _, item in ipairs(self.worn_items or {}) do map_here:add_item(self.pos, item) end
    if self.wielded then map_here:add_item(self.pos, self.wielded) end
    self.inventory = {}; self.worn_items = {}; self.wielded = nil
  end,
}
local terrain = { obj = function()
  return { get_movecost = function() return 2 end, has_flag = function() return false end }
end }
local map = {
  bub_to_abs = function(_, pos) return TripointAbsMs.new(pos.x + 48, pos.y + 48, pos.z) end,
  abs_to_bub = function(_, pos) return { x=pos.x, y=pos.y, z=pos.z } end,
  get_ter_at = function() return terrain end,
  get_furn_at = function() return nil end,
  has_items_at = function() return #state.map_items > 0 end,
  get_items_at = function() return { items=function() return state.map_items end } end,
  detach_item_at = function(_, _, item)
    for index, candidate in ipairs(state.map_items) do
      if candidate == item then table.remove(state.map_items, index); return candidate end
    end
  end,
  add_item = function(_, pos, item)
    if item and item.get_var_str and item:get_var_str("skyisland_death_drop", "") ~= "" then
      state.drop_dimension = current_dim; state.drop_position = pos
    end
    table.insert(state.map_items, item)
    return nil
  end,
}
local choice_queue
local random_results
local random_calls
local closest_result
local dimension_calls
local cleanup_calls
local seen_calls
local callbacks
local entered = true
local home_return_fail = false
local dimension_fail = false
local cleanup_result = true
local function choice()
  return table.remove(choice_queue, 1)
end
UiList = { new = function()
  return { title=function() end, add=function() end, text=function() end,
    desc_enabled=function() end, query=function() return choice() end }
end }
overmapbuffer = {
  find_random = function(_, params)
    random_calls = random_calls + 1
    local result = table.remove(random_results, 1)
    state.last_search = params
    return result
  end,
  find_closest = function() return closest_result end,
  set_seen = function() seen_calls = seen_calls + 1 end,
}
gapi = {
  get_current_dimension_id = function() return current_dim end,
  get_avatar = function() if avatar_available then return player end end,
  get_map = function() return map end,
  add_msg = function() end,
  rng = function(minimum) return minimum end,
  add_on_every_x_hook = function(_, callback) table.insert(callbacks, callback) end,
  place_player_dimension_at = function(options)
    table.insert(dimension_calls, options)
    if options.dimension_id == "sky_island_home" and home_return_fail then return false end
    if dimension_fail then return false end
    if entered then current_dim = options.dimension_id end
    return entered
  end,
  place_player_overmap_at = function() end,
  place_player_local_at = function() end,
  delete_dimension = function(id)
    state.deleted = id
    return cleanup_result
  end,
  get_monster_at = function() return nil end,
  place_monster_around = function() return { set_hp=function() end, make_friendly=function() end } end,
  create_item = function(id, count)
    local created = fresh_item(id, count)
    table.insert(state.created_items, { id=id, count=count })
    return created
  end,
}
local missions = {
  create_extraction_mission = function(dest, storage) storage.extraction_created = true end,
  create_bonus_mission = function(_, storage) storage.bonus_created = (storage.bonus_created or 0) + 1 end,
  create_slaughter_mission = function(_, storage) storage.slaughter_created = true end,
  complete_or_fail_missions = function(_, storage) storage.missions_completed = true end,
  fail_all_raid_missions = function(_, storage) if storage then storage.missions_failed = true end end,
}
local sickness = {
  start = function(storage) storage.sickness_started = true end,
  stop = function(storage) storage.sickness_stopped = true end,
  apply_resurrection_sickness = function() end,
}
local function fresh_storage()
  return {
    home_location = { x=60, y=60, z=10 }, home_omt = { x=2, y=2, z=10 },
    home_dimension_id = "sky_island_home", skyisland_storage_version = 2,
    is_away_from_home = false, raid_dimension_serial = 0,
    raids_total = 0, raids_won = 0, raids_lost = 0,
  }
end
function setup_case()
  state = { removed_items = 0, deleted = nil, last_search = nil,
    drop_dimension = nil, drop_position = nil, created_items = {}, map_items = {} }
  player.pos = { x=12, y=12, z=10 }; player.inventory = {}; player.worn_items = {}; player.wielded = nil
  choice_queue = {}; random_results = { { x=100, y=100, z=0 } }
  random_calls = 0; closest_result = nil; dimension_calls = {}; cleanup_calls = 0
  seen_calls = 0; callbacks = {}; current_dim = "sky_island_home"; avatar_available = true
  entered = true; home_return_fail = false; dimension_fail = false; cleanup_result = true
end
teleport = require("teleport")
function run_warp(storage, raid_choice, location_choice)
  choice_queue = { raid_choice, location_choice }
  return teleport.use_warp_obelisk(player, nil, { x=12, y=12, z=10 }, storage, missions, sickness)
end
'''


def run_fixture(testcase, body):
    result = subprocess.run(
        ["luajit", "-"], cwd=ROOT, text=True, capture_output=True,
        input=TELEPORT_FIXTURE + "\n" + body, check=True,
    )
    return result.stdout


MAIN_CALLER_FIXTURE = r'''
package.loaded.util = { debug_log = function() end }
package.preload["missions"] = function() return {
  complete_or_fail_missions = function() end,
  fail_all_raid_missions = function() end,
} end
package.preload["warp_sickness"] = function() return {
  stop = function() end, start = function() end,
  register_global_hook = function() end,
  get_status_info = function() return { current_pulse=0, grace_period=0 } end,
  apply_resurrection_sickness = function() end,
} end
package.preload["heart"] = function() return {} end
package.preload["upgrades"] = function() return {} end
package.preload["iuse"] = function() return {} end
package.preload["teleport"] = function()
  return {
    return_home_success = function(storage)
      state.return_calls = state.return_calls + 1
      if not state.return_ok then return false end
      storage.is_away_from_home = false
      storage.raids_won = (storage.raids_won or 0) + 1
      return true
    end,
    resurrect_at_home = function(storage)
      state.resurrection_calls = state.resurrection_calls + 1
      return state.return_ok
    end,
    cleanup_raid_dimension = function(storage)
      state.cleanup_calls = state.cleanup_calls + 1
      state.cleanup_saw_shard = player.inventory.skyisland_warp_shard ~= nil
      state.cleanup_saw_beacon = player.inventory.skyisland_skyward_beacon ~= nil
      state.cleanup_saw_mote = player.inventory.skyisland_homeward_mote ~= nil
      state.cleanup_saw_wins = storage.raids_won
      storage.current_raid_dimension_id = nil
      return true
    end,
  }
end
locale = { gettext = function(text) return text end }
ItypeId = { new = function(id) return id end }
TripointBubMs = { new = function(x, y, z) return { x=x, y=y, z=z } end }
local function item(id) return { id=id, charges=1, is_stackable=function() return false end } end
player = {
  inventory = {},
  get_pos_ms = function() return { x=1, y=1, z=0 } end,
  has_item_with_id = function(self, id) return self.inventory[id] ~= nil end,
  get_item_with_id = function(self, id) return self.inventory[id] end,
  remove_item = function(self, value)
    for id, candidate in pairs(self.inventory) do if candidate == value then self.inventory[id] = nil end end
    state.removed = state.removed + 1
  end,
  set_all_parts_hp_to_max = function() end, clear_effects = function() end,
}
state = {}
gapi = {
  get_avatar = function() return player end,
  get_monster_at = function() return nil end,
  add_msg = function() end,
}
game = { current_mod="sky", mod_runtime={ sky={} }, mod_storage={ sky={} }, hooks={ on_game_started={}, on_game_load={}, on_game_save={}, on_character_death={} } }
function setup_main_case()
  state.return_ok = true; state.return_calls = 0; state.cleanup_calls = 0
  state.removed = 0; state.resurrection_calls = 0
  state.cleanup_saw_shard = nil; state.cleanup_saw_beacon = nil
  state.cleanup_saw_mote = nil; state.cleanup_saw_wins = nil
  player.inventory = {}
  local storage = game.mod_storage.sky
  storage.is_away_from_home = true; storage.home_location = { x=1, y=1, z=0 }
  storage.current_raid_dimension_id = "sky_island_raid_000001"; storage.raids_won = 4
  storage.difficulty_emergency_return = 1
  return game.mod_runtime.sky, storage
end
local mod = require("main")
'''


def run_main_fixture(body):
    result = subprocess.run(
        ["luajit", "-"], cwd=ROOT, text=True, capture_output=True,
        input=MAIN_CALLER_FIXTURE + "\n" + body, check=True,
    )
    return result.stdout


class HomeDimensionTest(unittest.TestCase):
    def test_dimension_lifecycle_and_special_footprint(self):
        result = subprocess.run(
            ["luajit", "-"], cwd=ROOT, text=True, capture_output=True, check=True,
            input=r'''
package.loaded.util = { debug_log = function() end }
locale = { gettext = function(text) return text end }
OtMatchType = { EXACT = 1, CONTAINS = 2 }
TripointAbsOmt = { new = function(x, y, z) return { x=x, y=y, z=z } end }
TripointAbsMs = { new = function(x, y, z)
  return {
    x=x, y=y, z=z,
    to_omt=function(self) return { x=math.floor(self.x / 24), y=math.floor(self.y / 24), z=self.z } end,
  }
end }
local current = ""
local calls = 0
local entered = true
local last
local position = { x=2, y=2, z=10 }
local absolute = { x=60, y=60, z=10, to_omt=function() return position end }
gapi = {
  get_current_dimension_id = function() return current end,
  get_avatar = function() return { get_pos_ms=function() return {} end } end,
  get_map = function() return { bub_to_abs=function() return absolute end } end,
  add_msg = function() end,
  place_player_dimension_at = function(options)
    calls = calls + 1
    last = options
    if entered then current = options.dimension_id end
    return entered
  end,
}
local teleport = require("teleport")
local storage = {}
assert(teleport.ensure_home_dimension(storage))
assert(calls == 1 and storage.home_dimension_id == "sky_island_home")
assert(storage.home_omt.x == position.x and storage.skyisland_storage_version == 2)
assert(last.world_type == "pocket_dimension")
assert(last.pregen_special_id == "Sky Island Pocket")
assert(last.target_omt.x == last.pregen_special_omt.x)
assert(last.target_omt.y == last.pregen_special_omt.y)
assert(last.target_omt.z == last.pregen_special_omt.z)
print(last.pregen_special_id)
for _, p in ipairs({last.target_omt, last.bounds_min_omt, last.bounds_max_omt}) do
  print(p.x, p.y, p.z)
end
assert(teleport.ensure_home_dimension(storage) and calls == 1)
current = "raid"
storage.home_omt = { x=0, y=0, z=10 }
assert(teleport.ensure_home_dimension(storage) and calls == 2)
assert(last.target_ms.x == absolute.x and last.target_ms.y == absolute.y and last.target_ms.z == absolute.z)
assert(last.pregen_special_id == nil and last.bounds_min_omt == nil)
current = ""
entered = false
local failed = {}
assert(not teleport.ensure_home_dimension(failed))
assert(next(failed) == nil and current == "")
gapi.place_player_dimension_at = nil
assert(not teleport.ensure_home_dimension({}))

-- Legacy overworld state keeps its home dimension and unrelated progression data.
local legacy = {
  home_location = { x = -17, y = 23, z = 10 },
  home_omt = { x = -1, y = 0, z = 10 },
  is_away_from_home = true,
  islandrank = 4,
  warped_animals = { { type_id = "mon_dog", hp = 50 } },
}
teleport.migrate_legacy_storage(legacy)
assert(legacy.home_dimension_id == "")
assert(legacy.skyisland_storage_version == 2)
assert(legacy.islandrank == 4 and #legacy.warped_animals == 1)

-- A failed return is transactional and uses exact map-square coordinates.
gapi.place_player_dimension_at = function(options)
  last = options
  return entered
end
local return_player = {
  add_item_with_id = function() end,
  get_pos_ms = function() return {} end,
}
gapi.get_avatar = function() return return_player end
local return_storage = {
  home_location = { x = 61, y = 62, z = 10 },
  home_omt = { x = 2, y = 2, z = 10 },
  home_dimension_id = "sky_island_home",
  is_away_from_home = true,
  raided = true,
  raids_won = 0,
  raids_total = 1,
}
local missions = { complete_or_fail_missions = function() end }
local sickness = { stop = function() end }
ItypeId = { new = function(id) return id end }
entered = false
assert(not teleport.return_home_success(return_storage, missions, sickness))
assert(return_storage.is_away_from_home and return_storage.raids_won == 0)
assert(last.target_ms.x == 61 and last.target_ms.y == 62 and last.target_ms.z == 10)
entered = true
assert(teleport.return_home_success(return_storage, missions, sickness))
assert(not return_storage.is_away_from_home and return_storage.raids_won == 1)

-- Same-dimension legacy return explicitly repositions because the engine
-- intentionally returns true without moving in that case.
local local_target
local overmap_target
local same_storage = {
  home_location = { x = -17, y = 23, z = 10 },
  home_dimension_id = "",
  is_away_from_home = true,
  raids_won = 0,
  raids_total = 1,
}
current = ""
gapi.get_map = function() return { abs_to_bub = function(_, p) return p end } end
gapi.place_player_overmap_at = function(target) overmap_target = target end
gapi.place_player_local_at = function(target) local_target = target end
assert(teleport.return_home_success(same_storage, missions, sickness))
assert(overmap_target.x == -1 and overmap_target.y == 0 and overmap_target.z == 10)
assert(local_target.x == -17 and local_target.y == 23 and local_target.z == 10)

local cleanup_storage = {}
assert(teleport.cleanup_raid_dimension(cleanup_storage))

cleanup_storage.current_raid_dimension_id = "sky_island_raid_000001"
local deleted_dimension
local stored_dimension_during_delete = true
gapi.delete_dimension = function(dimension_id)
  deleted_dimension = dimension_id
  stored_dimension_during_delete = cleanup_storage.current_raid_dimension_id
  return true
end
assert(teleport.cleanup_raid_dimension(cleanup_storage))
assert(deleted_dimension == "sky_island_raid_000001")
assert(stored_dimension_during_delete == nil)
assert(cleanup_storage.current_raid_dimension_id == nil)

cleanup_storage.current_raid_dimension_id = "sky_island_raid_000002"
gapi.delete_dimension = function()
  assert(cleanup_storage.current_raid_dimension_id == nil)
  return false
end
assert(not teleport.cleanup_raid_dimension(cleanup_storage))
assert(cleanup_storage.current_raid_dimension_id == "sky_island_raid_000002")

gapi.delete_dimension = nil
assert(not teleport.cleanup_raid_dimension(cleanup_storage))
assert(cleanup_storage.current_raid_dimension_id == "sky_island_raid_000002")
''',
        )
        special_id, *points = result.stdout.strip().splitlines()
        anchor, minimum, maximum = [tuple(map(int, p.split())) for p in points]
        specials = {s["id"]: s for s in json.loads((ROOT / "overmap_special.json").read_text())}
        original = specials["Sky Island"]
        pocket = specials[special_id]
        self.assertEqual(pocket["copy-from"], original["id"])
        self.assertEqual(pocket["occurrences"], [0, 0])
        self.assertEqual(original["occurrences"], [100, 100])
        self.assertEqual(maximum[2], 10)  # No opaque boundary above the surface.
        self.assertEqual(len(pocket["overmaps"]), 18)
        for old, new in zip(original["overmaps"], pocket["overmaps"]):
            self.assertEqual(old["overmap"], new["overmap"])
            self.assertEqual(old["point"], [*new["point"][:2], new["point"][2] + 10])
            placed = tuple(a + b for a, b in zip(anchor, new["point"]))
            for value, low, high in zip(placed, minimum, maximum):
                self.assertLessEqual(low, value)
                self.assertLessEqual(value, high)
            self.assertTrue(0 <= placed[0] < 180 and 0 <= placed[1] < 180)
            self.assertIn(placed[2], (9, 10))

    def test_animal_delivery_is_persistent_and_retryable(self):
        subprocess.run(
            ["luajit", "-"], cwd=ROOT, text=True, capture_output=True, check=True,
            input=r'''
package.loaded.util = { debug_log = function() end }
locale = { gettext = function(text) return text end }
OtMatchType = { EXACT = 1, CONTAINS = 2 }
TimeDuration = { from_seconds = function(seconds) return seconds end }
MonsterTypeId = { new = function(id) return id end }
local callbacks = {}
local spawn_attempts = 0
local player = { get_pos_ms = function() return { x=4, y=5, z=6 } end }
local spawned = { set_hp = function() end, make_friendly = function() end }
gapi = {
  add_on_every_x_hook = function(_, callback) table.insert(callbacks, callback) end,
  get_avatar = function() return player end,
  place_monster_around = function()
    spawn_attempts = spawn_attempts + 1
    if spawn_attempts == 1 then return nil end
    return spawned
  end,
  add_msg = function() end,
}
local teleport = require("teleport")
local legacy_island = {
  is_away_from_home = false,
  island_animals = { { type_id = "mon_dog", hp = 50 } },
}
teleport.restore_pending_animals(legacy_island)
assert(legacy_island.island_animals == nil and #callbacks == 0)
local storage = { is_away_from_home = false, warped_animals = {
  { type_id = "mon_cow", hp = 80 },
} }
assert(teleport.spawn_warped_animals(storage) == 1)
assert(#storage.warped_animals == 1)
assert(#callbacks == 1)
storage.is_away_from_home = true
assert(callbacks[1]() == false)
-- A callback that fires after a new raid starts does not strand the animal in
-- the raid dimension; it remains persisted for a later retry.
assert(#storage.warped_animals == 1)
storage.is_away_from_home = false
assert(teleport.spawn_warped_animals(storage) == 1)
assert(#callbacks == 2)
assert(callbacks[2]() == false)
-- A failed delayed spawn remains persisted for a later save/reload retry.
assert(#storage.warped_animals == 1)
-- Simulate a save/reload: the persistent storage table survives while the
-- module-local scheduling flag is recreated.
package.loaded.teleport = nil
local reloaded = require("teleport")
assert(reloaded.spawn_warped_animals(storage) == 1)
assert(#callbacks == 3)
assert(callbacks[3]() == false)
assert(#storage.warped_animals == 0)
-- Calling the delivery entry point again cannot duplicate an already delivered animal.
assert(teleport.spawn_warped_animals(storage) == 0)
''',
        )

    def test_failed_room_return_restores_items_and_vortex(self):
        subprocess.run(
            ["luajit", "-"], cwd=ROOT, text=True, capture_output=True, check=True,
            input=r'''
package.loaded.util = { debug_log = function() end }
locale = { gettext = function(text) return text end }
OtMatchType = { EXACT = 1, CONTAINS = 2 }
TripointAbsOmt = { new = function(x, y, z) return { x=x, y=y, z=z } end }
TripointAbsMs = { new = function(x, y, z) return { x=x, y=y, z=z } end }
TripointBubMs = { new = function(x, y, z) return { x=x, y=y, z=z } end }
ItypeId = { new = function(id) return id end }
UiList = {
  new = function()
    return {
      title = function() end,
      add = function() end,
      query = function() return 1 end,
    }
  end,
}
local staged_item = {
  id = "room_loot", vars = {},
  get_var_str = function(self, key, default) return self.vars[key] or default end,
  set_var_str = function(self, key, value) self.vars[key] = value end,
}
local restored_item
local remove_calls = 0
local entered = false
local map = {
  has_items_at = function(_, p) return p.x == 0 and p.y == 0 and p.z == 0 end,
  get_items_at = function() return { items = function() return { staged_item } end } end,
  detach_item_at = function() return staged_item end,
  add_item = function(_, _, item) restored_item = item return nil end,
}
local player = { inventory = {},
  has_item_with_id = function(_, id) return id == "skyisland_vortex_token" end,
  get_item_with_id = function() return { is_stackable = function() return false end } end,
  add_item = function(self, item) self.inventory.room_loot = item end,
  all_items = function(self) local result = {}; for _, item in pairs(self.inventory) do table.insert(result, item) end; return result end,
  remove_item = function(self, item) remove_calls = remove_calls + 1; self.inventory.room_loot = nil; return item end,
}
gapi = {
  get_map = function() return map end,
  get_avatar = function() return player end,
  place_player_dimension_at = function() return entered end,
  get_current_dimension_id = function() return "sky_island_raid_000001" end,
  add_msg = function() end,
}
game = {}
local teleport = require("teleport")
local storage = {
  is_away_from_home = true,
  home_location = { x = 61, y = 62, z = 10 },
  home_dimension_id = "sky_island_home",
  difficulty_return_behavior = 1,
  current_raid_dimension_id = "sky_island_raid_000001",
}
assert(teleport.use_return_obelisk(player, nil, { x=0, y=0, z=0 }, storage, {}, { stop = function() end }) == 0)
assert(restored_item == staged_item)
assert(staged_item:get_var_str("skyisland_room_transfer", "") == "")
assert(remove_calls == 1)
assert(storage.is_away_from_home)
''',
        )

    def test_warp_entry_short_field_creates_raid(self):
        run_fixture(self, r'''
setup_case()
local storage = fresh_storage()
assert(run_warp(storage, 1, 1) == 1)
assert(storage.is_away_from_home and storage.raids_total == 1)
assert(storage.current_raid_type == "short")
assert(storage.current_raid_dimension_id == "sky_island_raid_000001")
assert(dimension_calls[1].world_type == "default")
assert(state.last_search.z_min == 0 and storage.extraction_created)
''')

    def test_warp_entry_medium_and_long_require_unlocks(self):
        run_fixture(self, r'''
setup_case()
local medium = fresh_storage(); medium.longer_raids_unlocked = 1
assert(run_warp(medium, 2, 1) == 1)
assert(medium.current_raid_type == "medium" and medium.current_raid_pulse_multiplier == 2)
setup_case()
local long_raid = fresh_storage(); long_raid.longer_raids_unlocked = 2
assert(run_warp(long_raid, 3, 1) == 1)
assert(long_raid.current_raid_type == "long" and long_raid.current_raid_pulse_multiplier == 3)
''')

    def test_warp_entry_each_unlocked_location_and_labs_catalyst(self):
        run_fixture(self, r'''
local cases = {
  { key="field", choice=1, z=0 },
  { key="basement", choice=2, z=-1, unlock="basements_unlocked" },
  { key="roof", choice=3, z=1, unlock="roofs_unlocked" },
  { key="labs", choice=4, z=-2, unlock="labs_unlocked", catalyst=true },
}
for _, case in ipairs(cases) do
  setup_case()
  local storage = fresh_storage()
  if case.unlock then storage[case.unlock] = true end
  if case.key == "roof" or case.key == "labs" then storage.basements_unlocked = true end
  if case.key == "labs" then storage.roofs_unlocked = true end
  if case.catalyst then player.inventory.skyisland_labs_catalyst = fresh_item("skyisland_labs_catalyst") end
  assert(run_warp(storage, 1, case.choice) == 1)
  assert(storage.is_away_from_home and state.last_search.z_min == case.z)
end
''')

    def test_warp_location_locked_and_missing_catalyst_cancel(self):
        run_fixture(self, r'''
setup_case()
local locked = fresh_storage()
-- Without unlocks, menu index 2 is Cancel, not Basement.
assert(run_warp(locked, 1, 2) == 0)
assert(#dimension_calls == 0 and not locked.is_away_from_home)
setup_case()
local missing = fresh_storage(); missing.labs_unlocked = true
missing.basements_unlocked = true; missing.roofs_unlocked = true
-- Labs has no selectable option when its catalyst is absent.
assert(run_warp(missing, 1, 4) == 0)
assert(#dimension_calls == 0 and not missing.is_away_from_home)
''')

    def test_warp_both_menus_cancel_without_state_mutation(self):
        run_fixture(self, r'''
setup_case()
local raid_cancel = fresh_storage()
assert(run_warp(raid_cancel, 2, 1) == 0)
assert(#dimension_calls == 0 and raid_cancel.current_raid_type == nil)
setup_case()
local location_cancel = fresh_storage()
assert(run_warp(location_cancel, 1, 2) == 0)
assert(#dimension_calls == 0 and location_cancel.current_raid_type == nil)
''')

    def test_warp_failed_dimension_creation_refunds_labs_catalyst(self):
        run_fixture(self, r'''
setup_case()
dimension_fail = true
local storage = fresh_storage(); storage.labs_unlocked = true
player.inventory.skyisland_labs_catalyst = fresh_item("skyisland_labs_catalyst")
assert(run_warp(storage, 1, 4) == 0)
assert(player.inventory.skyisland_labs_catalyst ~= nil)
assert(storage.raid_dimension_serial == 0 and storage.current_raid_dimension_id == nil)
''')

    def test_warp_search_fallback_succeeds_and_abort_cleans(self):
        run_fixture(self, r'''
setup_case()
random_results = {}; closest_result = { x=200, y=200, z=0 }
local fallback = fresh_storage()
assert(run_warp(fallback, 1, 1) == 1)
assert(random_calls == 9 and fallback.is_away_from_home)
setup_case()
random_results = {}; closest_result = nil
local abort = fresh_storage(); abort.labs_unlocked = true
abort.basements_unlocked = true; abort.roofs_unlocked = true
player.inventory.skyisland_labs_catalyst = fresh_item("skyisland_labs_catalyst")
assert(run_warp(abort, 1, 4) == 0)
assert(not abort.is_away_from_home and abort.current_raid_dimension_id == nil)
assert(player.inventory.skyisland_labs_catalyst ~= nil)
assert(state.deleted == "sky_island_raid_000001")
''')

    def test_warp_failed_search_and_failed_home_recovery_retains_raid(self):
        run_fixture(self, r'''
setup_case()
random_results = {}; closest_result = nil; home_return_fail = true
local storage = fresh_storage(); storage.labs_unlocked = true
storage.basements_unlocked = true; storage.roofs_unlocked = true
player.inventory.skyisland_labs_catalyst = fresh_item("skyisland_labs_catalyst")
assert(run_warp(storage, 1, 4) == 0)
assert(not storage.is_away_from_home)
assert(storage.current_raid_dimension_id == "sky_island_raid_000001")
assert(state.deleted == nil and player.inventory.skyisland_labs_catalyst ~= nil)
''')

    def test_two_successful_raids_allocate_unique_dimensions(self):
        run_fixture(self, r'''
setup_case()
local storage = fresh_storage()
assert(run_warp(storage, 1, 1) == 1)
assert(storage.current_raid_dimension_id == "sky_island_raid_000001")
assert(teleport.return_home_success(storage, missions, sickness) == true)
assert(storage.current_raid_dimension_id == nil)
random_results = { { x=100, y=100, z=0 } }
assert(run_warp(storage, 1, 1) == 1)
assert(storage.current_raid_dimension_id == "sky_island_raid_000002")
''')

    def test_emergency_callers_consume_before_cleanup_autosave(self):
        run_main_fixture(r'''
local mod, storage = setup_main_case()
player.inventory.skyisland_warp_shard = item("skyisland_warp_shard")
assert(mod.use_warp_focus(player, nil, nil) == 0)
assert(state.return_calls == 1 and state.cleanup_calls == 1)
assert(not state.cleanup_saw_shard and state.cleanup_saw_wins == 5)
setup_main_case(); storage.difficulty_emergency_return = 2
local beacon = item("skyisland_skyward_beacon"); player.inventory.skyisland_skyward_beacon = beacon
assert(mod.use_skyward_beacon(player, beacon, nil) == 0)
assert(state.cleanup_calls == 1 and not state.cleanup_saw_beacon)
setup_main_case(); storage.difficulty_emergency_return = 2
local mote = item("skyisland_homeward_mote"); player.inventory.skyisland_homeward_mote = mote
assert(mod.on_character_death({}) == true)
assert(state.cleanup_calls == 1 and not state.cleanup_saw_mote and state.cleanup_saw_wins == 4)
''')

    def test_emergency_callers_retain_items_when_return_fails(self):
        run_main_fixture(r'''
local mod, storage = setup_main_case()
state.return_ok = false
local shard = item("skyisland_warp_shard"); player.inventory.skyisland_warp_shard = shard
assert(mod.use_warp_focus(player, nil, nil) == 0)
assert(player.inventory.skyisland_warp_shard == shard and state.cleanup_calls == 0)
setup_main_case(); state.return_ok = false; storage.difficulty_emergency_return = 2
local beacon = item("skyisland_skyward_beacon"); player.inventory.skyisland_skyward_beacon = beacon
assert(mod.use_skyward_beacon(player, beacon, nil) == 0)
assert(player.inventory.skyisland_skyward_beacon == beacon and state.cleanup_calls == 0)
setup_main_case(); state.return_ok = false; storage.difficulty_emergency_return = 2
local mote = item("skyisland_homeward_mote"); player.inventory.skyisland_homeward_mote = mote
assert(mod.on_character_death({}) == true)
assert(player.inventory.skyisland_homeward_mote == mote and storage.raids_won == 4 and state.cleanup_calls == 0)
setup_main_case(); state.return_ok = false
assert(mod.on_character_death({}) == true and state.resurrection_calls == 1)
''')

    def test_resurrection_failed_travel_recovers_inventory_and_counters(self):
        run_fixture(self, r'''
setup_case(); current_dim = "sky_island_raid_000001"; home_return_fail = true
local dropped = {}
map.add_item = function(_, _, item)
  table.insert(dropped, item)
  return nil
end
map.get_items_at = function() return { items=function() return dropped end } end
map.detach_item_at = function(_, _, item)
  for index, candidate in ipairs(dropped) do
    if candidate == item then table.remove(dropped, index); return candidate end
  end
end
local storage = fresh_storage(); storage.is_away_from_home=true
storage.current_raid_dimension_id="sky_island_raid_000001"; storage.raids_lost=0
local normal = fresh_item("normal_loot"); player.inventory.normal_loot=normal
local token = fresh_item("skyisland_warp_shard"); player.inventory.skyisland_warp_shard=token
assert(teleport.resurrect_at_home(storage, missions, sickness) == false)
assert(storage.is_away_from_home and storage.raids_lost == 0)
assert(player.inventory.normal_loot == normal and player.inventory.skyisland_warp_shard == token)
assert(storage.death_drop_location == nil and #dropped == 0)
''')

    def test_resurrection_failed_travel_restores_worn_and_wielded_roles(self):
        run_fixture(self, r'''
setup_case(); current_dim = "sky_island_raid_000001"; home_return_fail = true
local dropped = {}
map.add_item = function(_, _, item) table.insert(dropped, item); return nil end
map.get_items_at = function() return { items=function() return dropped end } end
map.detach_item_at = function(_, _, item)
  for index, candidate in ipairs(dropped) do
    if candidate == item then table.remove(dropped, index); return candidate end
  end
end
local worn = fresh_item("worn_coat"); local weapon = fresh_item("weapon")
player.worn_items = { worn }; player.wielded = weapon
local storage = fresh_storage(); storage.is_away_from_home=true
storage.current_raid_dimension_id="sky_island_raid_000001"
assert(teleport.resurrect_at_home(storage, missions, sickness) == false)
assert(player.worn_items[1] == worn and player.wielded == weapon)
assert(player.inventory.worn_coat == nil and player.inventory.weapon == nil)
''')

    def test_resurrection_legacy_same_world_and_home_death_baseline(self):
        run_fixture(self, r'''
setup_case(); current_dim = ""
local legacy = fresh_storage(); legacy.home_dimension_id=""; legacy.is_away_from_home=true
legacy.current_raid_dimension_id="sky_island_raid_000001"
player.inventory.normal_loot=fresh_item("normal_loot")
player.inventory.skyisland_warp_shard=fresh_item("skyisland_warp_shard")
assert(teleport.resurrect_at_home(legacy, missions, sickness) == true)
assert(state.drop_dimension == "" and player.inventory.normal_loot == nil)
assert(player.inventory.skyisland_warp_shard ~= nil)
setup_case()
local home = fresh_storage(); home.is_away_from_home=false
local home_item=fresh_item("home_loot"); player.inventory.home_loot=home_item
assert(teleport.resurrect_at_home(home, missions, sickness) == true)
assert(player.inventory.home_loot == nil and home.raids_lost == 1)
''')

    def test_return_reward_once_and_failed_return_is_retryable(self):
        run_fixture(self, r'''
setup_case()
local storage = fresh_storage(); storage.is_away_from_home = true
storage.current_raid_dimension_id = "sky_island_raid_000001"; storage.current_raid_type = "short"
storage.raids_total = 1; player.inventory.skyisland_vortex_token = fresh_item("skyisland_vortex_token")
choice_queue = { 1 }
assert(teleport.use_return_obelisk(player, nil, { x=12, y=12, z=10 }, storage, missions, sickness) == 1)
assert(storage.raids_won == 1 and not storage.is_away_from_home)
assert(player.inventory.skyisland_material_token ~= nil and player.inventory.skyisland_material_token.charges == 50)
assert(teleport.use_return_obelisk(player, nil, { x=12, y=12, z=10 }, storage, missions, sickness) == 0)
assert(player.inventory.skyisland_material_token.charges == 50)
setup_case(); entered = true; home_return_fail = true; current_dim = "sky_island_raid_000001"
local failed = fresh_storage(); failed.is_away_from_home = true; failed.current_raid_dimension_id = "sky_island_raid_000001"
failed.raids_total = 1; failed.current_raid_type = "short"
choice_queue = { 1 }
assert(teleport.use_return_obelisk(player, nil, { x=12, y=12, z=10 }, failed, missions, sickness) == 0)
assert(failed.is_away_from_home and failed.raids_won == 0 and player.inventory.skyisland_material_token == nil)
''')

    def test_legacy_return_uses_exact_saved_home_ms(self):
        run_fixture(self, r'''
setup_case(); current_dim = "sky_island_raid_000001"
local storage = fresh_storage()
storage.home_dimension_id = ""; storage.home_location = { x=-17, y=23, z=10 }
storage.home_omt = { x=-1, y=0, z=10 }; storage.is_away_from_home = true
assert(teleport.return_home_success(storage, missions, sickness) == true)
assert(dimension_calls[1].dimension_id == "")
assert(dimension_calls[1].target_ms.x == -17 and dimension_calls[1].target_ms.y == 23)
''')

    def test_legacy_and_branch_v2_migration_preserves_progress_inventory_missions(self):
        run_fixture(self, r'''
setup_case()
local legacy = {
  home_location = { x=-17, y=23, z=10 }, home_omt = { x=-1, y=0, z=10 },
  is_away_from_home = true, islandrank=4, raids_total=17, raids_won=11,
  raids_lost=6, missionswon=8, upgrades={ stability=3 }, inventory={ shards=9 },
}
teleport.migrate_legacy_storage(legacy)
assert(legacy.home_dimension_id == "" and legacy.skyisland_storage_version == 2)
assert(legacy.islandrank == 4 and legacy.raids_total == 17 and legacy.raids_won == 11)
assert(legacy.missionswon == 8 and legacy.upgrades.stability == 3 and legacy.inventory.shards == 9)
local branch = {
  skyisland_storage_version=2, home_dimension_id="sky_island_home",
  home_location={ x=61, y=62, z=10 }, home_omt={ x=2, y=2, z=10 },
  is_away_from_home=true, islandrank=3, raids_total=21, raids_won=19,
  mission_state={ active=3 }, inventory={ tokens=12 }, upgrades={ labs=true },
}
teleport.migrate_legacy_storage(branch)
assert(branch.home_dimension_id == "sky_island_home" and branch.home_location.x == 61)
assert(branch.islandrank == 3 and branch.raids_total == 21 and branch.raids_won == 19)
assert(branch.mission_state.active == 3 and branch.inventory.tokens == 12 and branch.upgrades.labs)
''')

    def test_successful_return_retries_failed_map_add_without_loss(self):
        run_fixture(self, r'''
setup_case()
current_dim = "sky_island_raid_000001"
local room_item = fresh_item("room_loot")
local attempts = 0
map.has_items_at = function(_, p) return p.x == 12 and p.y == 12 and p.z == 10 end
map.get_items_at = function() return { items=function() return { room_item } end } end
map.detach_item_at = function() return room_item end
map.add_item = function(_, _, item)
  attempts = attempts + 1
  if attempts == 1 then return item end
  return nil
end
local storage = fresh_storage(); storage.is_away_from_home=true
storage.current_raid_dimension_id="sky_island_raid_000001"; storage.current_raid_type="short"
player.inventory.skyisland_vortex_token = fresh_item("skyisland_vortex_token")
choice_queue = { 1 }
assert(teleport.use_return_obelisk(player, nil, { x=12,y=12,z=10 }, storage, missions, sickness) == 1)
assert(attempts == 2 and not storage.is_away_from_home)
assert(storage.current_raid_dimension_id == nil and player.inventory.skyisland_vortex_token == nil)
''')

    def test_failed_room_placement_survives_reload_and_retries(self):
        run_fixture(self, r'''
setup_case(); current_dim = "sky_island_raid_000001"
local room_item = fresh_item("room_loot")
map.has_items_at = function(_, p) return p.x == 12 and p.y == 12 and p.z == 10 end
map.get_items_at = function() return { items=function() return { room_item } end } end
map.detach_item_at = function() return room_item end
map.add_item = function(_, _, item) return item end
local storage = fresh_storage(); storage.is_away_from_home=true
storage.current_raid_dimension_id="sky_island_raid_000001"; storage.current_raid_type="short"
player.inventory.skyisland_vortex_token = fresh_item("skyisland_vortex_token")
choice_queue = { 1 }
assert(teleport.use_return_obelisk(player, nil, { x=12,y=12,z=10 }, storage, missions, sickness) == 1)
assert(not storage.is_away_from_home and storage.current_raid_dimension_id == "sky_island_raid_000001")
-- The failed item is now an engine-owned, marker-bearing inventory item.
package.loaded.teleport = nil
local reloaded = require("teleport")
map.add_item = function() return nil end
assert(reloaded.retry_staged_room_items(storage))
assert(storage.current_raid_dimension_id == nil)
for _, item in ipairs(player:all_items(false)) do
  assert(item:get_var_str("skyisland_room_transfer", "") == "")
end
''')

    def test_warped_animal_callback_retries_when_avatar_unavailable(self):
        run_fixture(self, r'''
setup_case()
local storage = fresh_storage(); storage.warped_animals = { { type_id="mon_cow", hp=40 } }
avatar_available = false
assert(teleport.spawn_warped_animals(storage) == 1)
assert(callbacks[1]() == true and #storage.warped_animals == 1)
avatar_available = true
assert(callbacks[1]() == false and #storage.warped_animals == 0)
''')

    def test_cleanup_failure_is_retryable_after_return(self):
        run_fixture(self, r'''
setup_case()
cleanup_result = false
local storage = fresh_storage(); storage.is_away_from_home = true
storage.current_raid_dimension_id = "sky_island_raid_000001"; storage.current_raid_type = "short"
choice_queue = { 1 }
assert(teleport.use_return_obelisk(player, nil, { x=12, y=12, z=10 }, storage, missions, sickness) == 1)
assert(not storage.is_away_from_home and storage.current_raid_dimension_id == "sky_island_raid_000001")
cleanup_result = true
assert(teleport.cleanup_raid_dimension(storage))
assert(storage.current_raid_dimension_id == nil)
''')

    def test_resurrection_drops_raid_belongings_at_source_and_preserves_tokens_once(self):
        run_fixture(self, r'''
setup_case(); current_dim = "sky_island_raid_000001"
local storage = fresh_storage(); storage.is_away_from_home = true
storage.current_raid_dimension_id = "sky_island_raid_000001"; storage.raids_lost = 0
player.inventory.normal_loot = fresh_item("normal_loot")
local token_pouch = fresh_item("token_pouch"); token_pouch.contains = { skyisland_warp_shard=true }
player.inventory.token_pouch = token_pouch
assert(teleport.resurrect_at_home(storage, missions, sickness) == true)
assert(state.drop_dimension == "sky_island_raid_000001")
assert(state.drop_position ~= nil and state.drop_position.x == 12)
assert(#state.created_items == 0)
assert(player.inventory.token_pouch == token_pouch)
assert(player.inventory.normal_loot == nil)
assert(not storage.is_away_from_home and storage.raids_lost == 1)
''')


if __name__ == "__main__":
    unittest.main()
