-- Sky Islands BN Port - Heart of the Island
-- Interactive menu system for services, upgrades, and information

local heart = {}

-- Rank thresholds
local RANK_THRESHOLDS = {
  { min = 0, max = 9, name = "Novice" },
  { min = 10, max = 19, name = "Adept" },
  { min = 20, max = 999, name = "Master" }
}

-- Construction costs
local CONSTRUCTION_COSTS = {
  basement = 50,
  bigroom1 = 75,
  bigroom2 = 100,
  bigroom3 = 150,
  bigroom4 = 200
}

-- Upgrade info (for display purposes - actual unlocking is via crafting)
local UPGRADE_INFO = {
  stability = {
    { level = 1, name = "Stability I", effect = "+2 bonus grace pulses", item = "Warped Tincture" },
    { level = 2, name = "Stability II", effect = "+4 total bonus grace pulses", item = "Warped Elixir" },
    { level = 3, name = "Stability III", effect = "+6 total bonus grace pulses (MAX)", item = "Warped Panacea" }
  },
  scouting = {
    { level = 1, name = "Scouting I", effect = "Reveal 3x3 area on landing", item = "Scouting Lens" },
    { level = 2, name = "Scouting II", effect = "Reveal 5x5 area on landing (MAX)", item = "Scouting Scope" }
  },
  exits = {
    { level = 1, name = "Multiple Exits", effect = "2 return obelisks per expedition", item = "Escape Charm" }
  },
  raidlength = {
    { level = 1, name = "Large Expeditions", effect = "2x grace period, 125 token reward", item = "Warped Hourglass" },
    { level = 2, name = "Extended Expeditions", effect = "3x grace period, 200 token reward (MAX)", item = "Warped Sundial" }
  }
}

-- Helper: Count items by ID in player inventory
local function count_items(player, item_id)
  local total = 0
  local all_items = player:all_items(false)

  for _, item in ipairs(all_items) do
    if item:get_type():str() == item_id then
      -- For stackable items, count charges; otherwise count as 1
      if item:is_stackable() then
        total = total + item.charges
      else
        total = total + 1
      end
    end
  end

  return total
end

-- Helper: Remove items by ID from player inventory
local function remove_items(player, item_id, count)
  local remaining = count
  local all_items = player:all_items(false)

  for _, item in ipairs(all_items) do
    if remaining <= 0 then break end

    if item:get_type():str() == item_id then
      if item:is_stackable() then
        local charges_to_remove = math.min(item.charges, remaining)
        item:mod_charges(-charges_to_remove)
        remaining = remaining - charges_to_remove

        -- Remove the item if it has no charges left
        if item.charges <= 0 then
          player:inv_remove_item(item)
        end
      else
        player:inv_remove_item(item)
        remaining = remaining - 1
      end
    end
  end

  return remaining == 0  -- Return true if all items were removed
end

-- Helper: Get current rank based on successful raids
local function get_rank(raids_won)
  for i, rank in ipairs(RANK_THRESHOLDS) do
    if raids_won >= rank.min and raids_won <= rank.max then
      return i - 1, rank.name  -- Return 0, 1, or 2
    end
  end
  return 0, "Novice"
end

-- Helper: Heal player (costs warp shards after rank 0)
local function heal_player(player, rank, storage)
  if rank > 0 then
    -- Cost: 4 warp shards
    local shard_count = count_items(player, "skyisland_warp_shard")
    if shard_count < 4 then
      gapi.add_msg("You need 4 warp shards to heal yourself.")
      return false
    end
    -- Remove shards
    remove_items(player, "skyisland_warp_shard", 4)
  end

  -- Full heal
  player:set_all_parts_hp_to_max()
  player:clear_effects()
  gapi.add_msg("You feel refreshed and restored!")

  return true
end

-- Main menu
local function show_main_menu(player, storage)
  local ui = UiList.new()
  ui:title(locale.gettext("Heart of the Island"))
  ui:add(1, locale.gettext("Construction"))
  ui:add(2, locale.gettext("Upgrades"))
  ui:add(3, locale.gettext("Services"))
  ui:add(4, locale.gettext("Information"))
  ui:add(5, locale.gettext("Rank-Up Challenges"))
  ui:add(6, locale.gettext("Close"))

  local choice = ui:query()

  if choice == 1 then
    return "construction"
  elseif choice == 2 then
    return "upgrades"
  elseif choice == 3 then
    return "services"
  elseif choice == 4 then
    return "information"
  elseif choice == 5 then
    return "rankup"
  else
    return "close"
  end
end

-- Services menu
local function show_services_menu(player, storage)
  local raids_won = storage.raids_won or 0
  local rank_num, rank_name = get_rank(raids_won)

  local ui = UiList.new()
  ui:title(locale.gettext("Services"))

  if rank_num == 0 then
    ui:add(1, locale.gettext("Heal me (Free)"))
  else
    ui:add(1, locale.gettext("Heal me (4 Warp Shards)"))
  end

  ui:add(2, locale.gettext("View expedition statistics"))
  ui:add(3, locale.gettext("Back"))

  local choice = ui:query()

  if choice == 1 then
    heal_player(player, rank_num, storage)
    return "services"
  elseif choice == 2 then
    local raids_total = storage.raids_total or 0
    local raids_won = storage.raids_won or 0
    local raids_lost = storage.raids_lost or 0
    local success_rate = raids_total > 0 and math.floor((raids_won / raids_total) * 100) or 0

    gapi.add_msg(string.format(
      "=== Expedition Statistics ===\n" ..
      "Current Rank: %s (%d)\n" ..
      "Total Expeditions: %d\n" ..
      "Successful Returns: %d\n" ..
      "Failed Expeditions: %d\n" ..
      "Success Rate: %d%%",
      rank_name, rank_num, raids_total, raids_won, raids_lost, success_rate
    ))
    return "services"
  else
    return "main"
  end
end

-- Helper: Get next available upgrade for a category
local function get_next_upgrade(category, current_level)
  local upgrades_list = UPGRADE_INFO[category]
  if not upgrades_list then return nil end

  for _, upgrade in ipairs(upgrades_list) do
    if upgrade.level == current_level + 1 then
      return upgrade
    end
  end
  return nil  -- All unlocked
end

-- Upgrades menu - info display only, actual unlocking via crafting
local function show_upgrades_menu(player, storage)
  local stability = storage.stability_unlocked or 0
  local scouting = storage.scouting_unlocked or 0
  local exits = storage.multiple_exits_unlocked or 0
  local raidlength = storage.longer_raids_unlocked or 0

  local ui = UiList.new()
  ui:title(locale.gettext("Upgrades (Craft items near Heart to unlock)"))

  local menu_index = 1

  -- Stability status
  local stab_next = get_next_upgrade("stability", stability)
  if stab_next then
    ui:add(menu_index, locale.gettext(string.format("Stability: Level %d - Next: %s (craft %s)", stability, stab_next.name, stab_next.item)))
  else
    ui:add(menu_index, locale.gettext(string.format("Stability: MAX (+%d pulses)", stability * 2)))
  end
  menu_index = menu_index + 1

  -- Scouting status
  local scout_next = get_next_upgrade("scouting", scouting)
  if scout_next then
    ui:add(menu_index, locale.gettext(string.format("Scouting: Level %d - Next: %s (craft %s)", scouting, scout_next.name, scout_next.item)))
  else
    ui:add(menu_index, locale.gettext("Scouting: MAX (5x5 reveal)"))
  end
  menu_index = menu_index + 1

  -- Multiple Exits status
  local exit_next = get_next_upgrade("exits", exits)
  if exit_next then
    ui:add(menu_index, locale.gettext(string.format("Exits: Not unlocked - craft %s", exit_next.item)))
  else
    ui:add(menu_index, locale.gettext("Exits: Unlocked (2 per expedition)"))
  end
  menu_index = menu_index + 1

  -- Raid Length status
  local raid_next = get_next_upgrade("raidlength", raidlength)
  if raid_next then
    ui:add(menu_index, locale.gettext(string.format("Expedition Length: Level %d - Next: %s (craft %s)", raidlength, raid_next.name, raid_next.item)))
  else
    ui:add(menu_index, locale.gettext("Expedition Length: MAX (Extended available)"))
  end
  menu_index = menu_index + 1

  ui:add(menu_index, locale.gettext("How do upgrades work?"))
  menu_index = menu_index + 1

  ui:add(menu_index, locale.gettext("Back"))

  local choice = ui:query()

  if choice == menu_index - 1 then
    -- "How do upgrades work?"
    gapi.add_msg(
      "=== How Upgrades Work ===\n" ..
      "To unlock upgrades, you must CRAFT special artifacts near the Heart of the Island.\n\n" ..
      "1. Gather the required items during expeditions\n" ..
      "2. Return home safely with your loot\n" ..
      "3. Open the crafting menu (& key) near the Heart\n" ..
      "4. Craft the upgrade artifact (e.g., 'Warped Tincture')\n" ..
      "5. Activate the crafted item to unlock the upgrade\n\n" ..
      "Each upgrade requires different scavenged items. Check the crafting menu for requirements."
    )
    return "upgrades"
  elseif choice == menu_index then
    return "main"
  else
    -- Clicking on an upgrade status shows details
    local details = nil
    if choice == 1 then
      local next_up = get_next_upgrade("stability", stability)
      if next_up then
        details = string.format("%s: %s\nCraft: %s", next_up.name, next_up.effect, next_up.item)
      else
        details = "Stability is at maximum level (+6 bonus grace pulses)."
      end
    elseif choice == 2 then
      local next_up = get_next_upgrade("scouting", scouting)
      if next_up then
        details = string.format("%s: %s\nCraft: %s", next_up.name, next_up.effect, next_up.item)
      else
        details = "Scouting is at maximum level (5x5 area revealed on landing)."
      end
    elseif choice == 3 then
      local next_up = get_next_upgrade("exits", exits)
      if next_up then
        details = string.format("%s: %s\nCraft: %s", next_up.name, next_up.effect, next_up.item)
      else
        details = "Multiple Exits is unlocked (2 return obelisks per expedition)."
      end
    elseif choice == 4 then
      local next_up = get_next_upgrade("raidlength", raidlength)
      if next_up then
        details = string.format("%s: %s\nCraft: %s", next_up.name, next_up.effect, next_up.item)
      else
        details = "Expedition Length is at maximum (Extended Expeditions available)."
      end
    end
    if details then
      gapi.add_msg(details)
    end
    return "upgrades"
  end
end

-- Rank-up challenges menu
local function show_rankup_menu(player, storage)
  local raids_won = storage.raids_won or 0
  local rank_num, rank_name = get_rank(raids_won)

  local ui = UiList.new()
  ui:title(locale.gettext("Rank-Up Challenges"))
  ui:add(1, locale.gettext("Explain rank-up system"))
  ui:add(2, locale.gettext("View my current rank"))

  if rank_num >= 1 and rank_num < 2 then
    ui:add(3, locale.gettext("Rank 1 Challenge: Proof of Determination"))
  end

  if rank_num >= 2 then
    ui:add(4, locale.gettext("Rank 2 Challenge: Proof of Mastery"))
  end

  ui:add(5, locale.gettext("Back"))

  local choice = ui:query()

  if choice == 1 then
    gapi.add_msg(
      "Beyond automatic rank progression, you can prove your mastery by completing rank-up " ..
      "challenges. These require crafting special items near the Heart that demonstrate you " ..
      "have gathered the tools and skills needed to survive. Completing these challenges " ..
      "unlocks new recipes and capabilities."
    )
    return "rankup"
  elseif choice == 2 then
    gapi.add_msg(string.format(
      "Current Rank: %s (%d)\nSuccessful Expeditions: %d\n\n" ..
      "Rank 1 unlocks at 10 successful raids\nRank 2 unlocks at 20 successful raids",
      rank_name, rank_num, raids_won
    ))
    return "rankup"
  elseif choice == 3 and rank_num >= 1 then
    gapi.add_msg(
      "=== Proof of Determination ===\n" ..
      "Requirements:\n" ..
      "- 2 warp shards\n" ..
      "- HAMMER quality 2\n" ..
      "- SAW_W quality 2\n" ..
      "- WRENCH quality 2\n" ..
      "- Must be crafted near the Heart\n\n" ..
      "Completing this proves you have mastered basic survival and tool-making."
    )
    return "rankup"
  elseif choice == 4 and rank_num >= 2 then
    gapi.add_msg(
      "=== Proof of Mastery ===\n" ..
      "Requirements:\n" ..
      "- 4 warp shards\n" ..
      "- BUTCHER quality 16\n" ..
      "- CUT_FINE quality 2\n" ..
      "- PRY quality 2\n" ..
      "- Must be crafted near the Heart\n\n" ..
      "Completing this proves you have achieved ultimate mastery of survival."
    )
    return "rankup"
  else
    return "main"
  end
end

-- Information menu
local function show_information_menu(player, storage)
  local ui = UiList.new()
  ui:title(locale.gettext("Information"))
  ui:add(1, locale.gettext("What is this place?"))
  ui:add(2, locale.gettext("Explain expeditions"))
  ui:add(3, locale.gettext("Explain warp shards and tokens"))
  ui:add(4, locale.gettext("Back"))

  local choice = ui:query()

  if choice == 1 then
    gapi.add_msg(
      "This floating island is your sanctuary. Use the Warp Obelisk to teleport to the " ..
      "surface and begin expeditions. Gather resources, complete missions, and return " ..
      "before warp sickness kills you. If you die, you'll respawn here but lose everything " ..
      "you were carrying."
    )
    return "information"
  elseif choice == 2 then
    gapi.add_msg(
      "Use the Warp Obelisk to begin an expedition. You'll teleport to a random location " ..
      "with three missions: find the exit, kill enemies, and find warp shards. Every 5 minutes, " ..
      "warp sickness advances. After 12 stages, you'll start taking damage. Find the exit " ..
      "(marked with a return obelisk) and return home before it's too late!"
    )
    return "information"
  elseif choice == 3 then
    gapi.add_msg(
      "Warp shards are earned by completing missions and searching for treasure. They're used " ..
      "for healing and upgrades. Material tokens (50 per successful expedition) can be converted " ..
      "into raw resources at infinity nodes. Craft the infinity nodes first, deploy them on your " ..
      "island, then use them to craft resources from tokens."
    )
    return "information"
  else
    return "main"
  end
end

-- Helper: Run a construction mission
local function run_construction_mission(player, mission_id)
  local mission_type = MissionTypeIdRaw.new(mission_id)
  local player_id = player:getID()
  local new_mission = Mission.reserve_new(mission_type, player_id)

  if new_mission then
    new_mission:assign(player)
    new_mission:wrap_up()
    return true
  else
    gapi.add_msg("ERROR: Failed to create construction mission")
    return false
  end
end

-- Construction menu
local function show_construction_menu(player, storage)
  local ui = UiList.new()
  ui:title(locale.gettext("Island Construction"))

  local has_basement = storage.skyisland_build_base or false
  local has_bigroom1 = storage.skyisland_build_bigroom1 or false
  local has_bigroom2 = storage.skyisland_build_bigroom2 or false
  local has_bigroom3 = storage.skyisland_build_bigroom3 or false
  local has_bigroom4 = storage.skyisland_build_bigroom4 or false

  local menu_index = 1

  -- Basement
  if not has_basement then
    ui:add(menu_index, locale.gettext(string.format("Build Basement (%d Material Tokens)", CONSTRUCTION_COSTS.basement)))
  else
    ui:add(menu_index, locale.gettext("Basement - Already Built"))
  end
  menu_index = menu_index + 1

  -- Expansion 1 (only available after basement)
  if has_basement then
    if not has_bigroom1 then
      ui:add(menu_index, locale.gettext(string.format("Build Expansion 1 - Corridors (%d Material Tokens)", CONSTRUCTION_COSTS.bigroom1)))
    else
      ui:add(menu_index, locale.gettext("Expansion 1 - Already Built"))
    end
    menu_index = menu_index + 1
  end

  -- Expansion 2 (only available after bigroom1)
  if has_bigroom1 then
    if not has_bigroom2 then
      ui:add(menu_index, locale.gettext(string.format("Build Expansion 2 - Central Room (%d Material Tokens)", CONSTRUCTION_COSTS.bigroom2)))
    else
      ui:add(menu_index, locale.gettext("Expansion 2 - Already Built"))
    end
    menu_index = menu_index + 1
  end

  -- Expansion 3 (only available after bigroom2)
  if has_bigroom2 then
    if not has_bigroom3 then
      ui:add(menu_index, locale.gettext(string.format("Build Expansion 3 - Large Room (%d Material Tokens)", CONSTRUCTION_COSTS.bigroom3)))
    else
      ui:add(menu_index, locale.gettext("Expansion 3 - Already Built"))
    end
    menu_index = menu_index + 1
  end

  -- Expansion 4 (only available after bigroom3)
  if has_bigroom3 then
    if not has_bigroom4 then
      ui:add(menu_index, locale.gettext(string.format("Build Expansion 4 - Maximum Size (%d Material Tokens)", CONSTRUCTION_COSTS.bigroom4)))
    else
      ui:add(menu_index, locale.gettext("Expansion 4 - Already Built"))
    end
    menu_index = menu_index + 1
  end

  ui:add(menu_index, locale.gettext("Back"))

  local choice = ui:query()
  local num_mat_tokens = count_items(player, "skyisland_material_token")

  -- Handle basement
  if choice == 1 and not has_basement then
    if num_mat_tokens < CONSTRUCTION_COSTS.basement then
      gapi.add_msg(string.format("You need %d material tokens to build the basement.", CONSTRUCTION_COSTS.basement))
      return "construction"
    end
    remove_items(player, "skyisland_material_token", CONSTRUCTION_COSTS.basement)
    storage.skyisland_build_base = true
    gapi.add_msg("Construction beginning... The island trembles as new spaces form.")
    if run_construction_mission(player, "MISSION_SKYISLAND_BUILD_BASEMENT") then
      gapi.add_msg("A basement has been carved into the island's depths!")
    end
    return "construction"
  end

  -- Handle expansion 1
  local exp1_index = has_basement and 2 or nil
  if choice == exp1_index and not has_bigroom1 then
    if num_mat_tokens < CONSTRUCTION_COSTS.bigroom1 then
      gapi.add_msg(string.format("You need %d material tokens for this expansion.", CONSTRUCTION_COSTS.bigroom1))
      return "construction"
    end
    remove_items(player, "skyisland_material_token", CONSTRUCTION_COSTS.bigroom1)
    storage.skyisland_build_bigroom1 = true
    gapi.add_msg("Expanding the basement...")
    if run_construction_mission(player, "MISSION_SKYISLAND_BUILD_BIGROOM1") then
      gapi.add_msg("Cross-shaped corridors now extend from the central room! A skylight illuminates from above.")
    end
    return "construction"
  end

  -- Handle expansion 2
  local exp2_index = has_bigroom1 and (has_basement and 3 or nil) or nil
  if choice == exp2_index and not has_bigroom2 then
    if num_mat_tokens < CONSTRUCTION_COSTS.bigroom2 then
      gapi.add_msg(string.format("You need %d material tokens for this expansion.", CONSTRUCTION_COSTS.bigroom2))
      return "construction"
    end
    remove_items(player, "skyisland_material_token", CONSTRUCTION_COSTS.bigroom2)
    storage.skyisland_build_bigroom2 = true
    gapi.add_msg("Widening the corridors...")
    if run_construction_mission(player, "MISSION_SKYISLAND_BUILD_BIGROOM2") then
      gapi.add_msg("The corridors have been widened with additional rooms!")
    end
    return "construction"
  end

  -- Handle expansion 3
  local exp3_index = has_bigroom2 and (has_bigroom1 and (has_basement and 4 or nil) or nil) or nil
  if choice == exp3_index and not has_bigroom3 then
    if num_mat_tokens < CONSTRUCTION_COSTS.bigroom3 then
      gapi.add_msg(string.format("You need %d material tokens for this expansion.", CONSTRUCTION_COSTS.bigroom3))
      return "construction"
    end
    remove_items(player, "skyisland_material_token", CONSTRUCTION_COSTS.bigroom3)
    storage.skyisland_build_bigroom3 = true
    gapi.add_msg("Expanding the central room...")
    if run_construction_mission(player, "MISSION_SKYISLAND_BUILD_BIGROOM3") then
      gapi.add_msg("The central room has been greatly enlarged!")
    end
    return "construction"
  end

  -- Handle expansion 4
  local exp4_index = has_bigroom3 and (has_bigroom2 and (has_bigroom1 and (has_basement and 5 or nil) or nil) or nil) or nil
  if choice == exp4_index and not has_bigroom4 then
    if num_mat_tokens < CONSTRUCTION_COSTS.bigroom4 then
      gapi.add_msg(string.format("You need %d material tokens for this expansion.", CONSTRUCTION_COSTS.bigroom4))
      return "construction"
    end
    remove_items(player, "skyisland_material_token", CONSTRUCTION_COSTS.bigroom4)
    storage.skyisland_build_bigroom4 = true
    gapi.add_msg("Final expansion underway...")
    if run_construction_mission(player, "MISSION_SKYISLAND_BUILD_BIGROOM4") then
      gapi.add_msg("The basement has reached its maximum size! Your sanctuary is complete.")
    end
    return "construction"
  end

  -- Back button is always the last item
  return "main"
end

-- Main entry point
function heart.use_heart(who, item, pos, storage)
  local player = gapi.get_avatar()
  if not player then return 0 end

  -- Menu loop
  local current_menu = "main"
  while current_menu ~= "close" do
    if current_menu == "main" then
      current_menu = show_main_menu(player, storage)
    elseif current_menu == "construction" then
      current_menu = show_construction_menu(player, storage)
    elseif current_menu == "upgrades" then
      current_menu = show_upgrades_menu(player, storage)
    elseif current_menu == "services" then
      current_menu = show_services_menu(player, storage)
    elseif current_menu == "information" then
      current_menu = show_information_menu(player, storage)
    elseif current_menu == "rankup" then
      current_menu = show_rankup_menu(player, storage)
    end
  end

  return 1
end

return heart
