"""Run with: python3 -m unittest discover -s tests"""

import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


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
assert(teleport.spawn_warped_animals(storage) == 1)
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
local staged_item = { id = "room_loot" }
local restored_item
local remove_calls = 0
local entered = false
local map = {
  has_items_at = function(_, p) return p.x == 0 and p.y == 0 and p.z == 0 end,
  get_items_at = function() return { items = function() return { staged_item } end } end,
  detach_item_at = function() return staged_item end,
  add_item = function(_, _, item) restored_item = item return nil end,
}
local player = {
  has_item_with_id = function(_, id) return id == "skyisland_vortex_token" end,
  get_item_with_id = function() return { is_stackable = function() return false end } end,
  remove_item = function() remove_calls = remove_calls + 1 end,
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
assert(remove_calls == 0)
assert(storage.is_away_from_home)
''',
        )


if __name__ == "__main__":
    unittest.main()
