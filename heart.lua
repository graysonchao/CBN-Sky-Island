-- Sky Islands BN Port - Heart of the Island
-- Interactive menu system for services, upgrades, and information

local heart = {}

-- Rank thresholds
local RANK_THRESHOLDS = {
  { min = 0, max = 9, name = "Novice" },
  { min = 10, max = 19, name = "Adept" },
  { min = 20, max = 999, name = "Master" }
}

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
    local has_shards = player:has_item("skyisland_warp_shard", 4)
    if not has_shards then
      gapi.add_msg("You need 4 warp shards to heal yourself.")
      return false
    end
    -- Remove shards
    player:use_item("skyisland_warp_shard", 4)
  end

  -- Full heal
  -- player
  player:set_all_parts_hp_to_max()
  player:clear_effects()
  gapi.add_msg("You feel refreshed and restored!")

  return true
end

-- Main menu
local function show_main_menu(player, storage)
  local ui = UiList.new()
  ui:title(locale.gettext("Heart of the Island"))
  ui:add(1, locale.gettext("Services"))
  ui:add(2, locale.gettext("Information"))
  ui:add(3, locale.gettext("Rank-Up Challenges"))
  ui:add(4, locale.gettext("Close"))

  local choice = ui:query()

  if choice == 1 then
    return "services"
  elseif choice == 2 then
    return "information"
  elseif choice == 3 then
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

-- Main entry point
function heart.use_heart(who, item, pos, storage)
  local player = gapi.get_avatar()
  if not player then return 0 end

  -- Menu loop
  local current_menu = "main"
  while current_menu ~= "close" do
    if current_menu == "main" then
      current_menu = show_main_menu(player, storage)
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
