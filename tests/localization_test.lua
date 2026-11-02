-- Run from the mod root: lua tests/localization_test.lua .
-- Executes real mod functions with mocked BN APIs and a marker translator.
-- This checks translation routing and side effects, not in-game integration.
local root = (arg and arg[1]) or "."
local total = 0
local failures = 0

local function equal(actual, expected)
  assert(actual == expected, string.format("expected %q, got %q", tostring(expected), tostring(actual)))
end

local function contains(text, fragment)
  assert(text:find(fragment, 1, true), string.format("missing %q in %q", fragment, text))
end

local function setup()
  local state = { language = "T", messages = {}, dialogs = {}, menus = {}, choices = {},
    added = {}, removed = {}, charges = 2, intensity = 1, hooks = {}, modules = {} }
  local env = setmetatable({}, { __index = _G })
  local function tr(text) return state.language .. "[" .. text .. "]" end
  env.locale = { gettext = tr }
  env.Color = setmetatable({}, { __index = function(_, key) return key end })
  local function position(x, y, z) return { x = x, y = y, z = z } end
  env.TripointBubMs = { new = position }
  env.TripointAbsOmt = { new = position }
  env.TripointOmtMs = { new = position }
  for _, name in ipairs({ "EffectTypeId", "ItypeId" }) do
    env[name] = { new = function(value) return value end }
  end
  for _, name in ipairs({ "TerId", "FurnId" }) do
    env[name] = { new = function(value) return { int_id = function() return value end } end }
  end
  env.OtMatchType = { TYPE = 1, EXACT = 2, PREFIX = 3 }
  env.TimeDuration = { from_hours = function(n) return n end,
    from_minutes = function(n) return n end, from_seconds = function(n) return n end }
  state.player = {
    get_pos_ms = function() return position(0, 0, 0) end,
    has_effect = function() return true end,
    get_effect_int = function() return state.intensity end,
    add_effect = function(_, id) state.effect = id end,
    has_item_with_id = function() return true end,
    get_item_with_id = function()
      return { charges = 2, is_stackable = function() return true end,
        mod_charges = function(_, delta) state.charges = state.charges + delta end }
    end,
    remove_item = function(_, item) state.removed[#state.removed + 1] = item end,
    add_item_with_id = function(_, id, count) state.added[#state.added + 1] = { id, count } end,
  }
  local map = {
    get_furn_at = function() return state.adjacent or "none" end,
    get_ter_at = function() return state.adjacent or "none" end,
    bub_to_abs = function() return { x = 0, y = 0, z = 0,
      to_omt = function() return position(0, 0, 0) end } end,
  }
  env.gapi = {
    get_avatar = function() return state.player end,
    get_map = function() return map end,
    get_monster_at = function() return nil end,
    add_msg = function(text) state.messages[#state.messages + 1] = text end,
    add_on_every_x_hook = function(_, callback) state.hooks[#state.hooks + 1] = callback end,
  }
  env.QueryPopup = { new = function()
    return { message = function(_, text) state.dialogs[#state.dialogs + 1] = text end,
      message_color = function() end, allow_any_key = function() end, query = function() end }
  end }
  env.UiList = { new = function()
    local menu = { entries = {} }
    function menu:title(text) self.heading = text end
    function menu:add(_, text) self.entries[#self.entries + 1] = text end
    function menu:query() return table.remove(state.choices, 1) or -1 end
    state.menus[#state.menus + 1] = menu
    return menu
  end }
  env.OmtFindParams = { new = function()
    return { add_type = function() end, set_search_range = function() end,
      set_search_layers = function() end }
  end }
  env.overmapbuffer = { find_random = function() return nil end }
  env.game = { current_mod = "sky_test", mod_runtime = { sky_test = {} },
    mod_storage = { sky_test = {} } }
  state.modules.util = { debug_log = function() end }
  env.require = function(name)
    if state.modules[name] then return state.modules[name] end
    local module = assert(loadfile(root .. "/" .. name .. ".lua", "t", env))()
    state.modules[name] = module
    return module
  end
  state.env, state.tr = env, tr
  state.load = function(name) return env.require(name) end
  return state
end

local function test(name, fn)
  total = total + 1
  local ok, message = pcall(fn)
  if ok then print("PASS: " .. name)
  else failures = failures + 1; print("FAIL: " .. name .. ": " .. tostring(message)) end
end

test("status labels translate at display time, including fallback", function()
  local s = setup()
  local warp = s.load("warp_sickness")
  local names = { [0] = "Stable", "Warp Sickness", "Warp Nausea", "Warp Debilitation",
    "Warp Necrosis", "Warp Disintegration", "CRITICAL" }
  equal(warp.get_status_info({}).status_name, s.tr("Stable"))
  for intensity = 0, 6 do
    s.intensity = intensity
    equal(warp.get_status_info({ warp_pulse_count = 9 }).status_name, s.tr(names[intensity]))
  end
  s.intensity = 99
  equal(warp.get_status_info({ warp_pulse_count = 9 }).status_name, s.tr("CRITICAL"))
  s.language = "SECOND"
  s.intensity = 1
  equal(warp.get_status_info({ warp_pulse_count = 9 }).status_name, s.tr("Warp Sickness"))
end)

test("mild warp pulse translates templates and keeps counters", function()
  local s = setup()
  local warp = s.load("warp_sickness")
  local storage = { is_away_from_home = true, warp_pulse_count = 8, warp_pulse_accumulated = 14 }
  warp.register_global_hook(storage)
  equal(s.hooks[1](), true)
  equal(storage.warp_pulse_count, 9)
  equal(storage.warp_pulse_accumulated, 0)
  equal(s.effect, "skyisland_warpsickness")
  equal(s.messages[1], string.format(s.tr("<color_yellow>[Warp Pulse] %s (%d/6). -%d stats. %d pulses to disintegration.</color>"), s.tr("Warp Sickness"), 1, 2, 5))
  for _, text in ipairs({ "=== WARP PULSE ===\n\n", "The warp begins to affect you.\n",
    "[Press any key to continue]" }) do contains(s.dialogs[1], s.tr(text)) end
  contains(s.dialogs[1], "T[STATUS: T[Warp Sickness] (Intensity 1/6)")
  contains(s.dialogs[1], "T[Stats: -2 to all")
  contains(s.dialogs[1], "T[Pulses until disintegration: 5")
end)

test("all six copyplates translate names without changing item IDs", function()
  local cases = {
    { "imprint_autodoc", "Autodoc", "f_autodoc", "skyisland_autodoc_active" },
    { "imprint_autodoc_couch", "Autodoc Couch", "f_autodoc_couch", "skyisland_autodoc_couch_active" },
    { "imprint_nanofab_body", "Nanofabricator", "t_nanofab_body", "skyisland_nanofab_body_active" },
    { "imprint_nanofab_panel", "Nanofabricator Control Panel", "t_nanofab", "skyisland_nanofab_panel_active" },
    { "imprint_cvd_body", "CVD Machine", "t_cvdbody", "skyisland_cvd_body_active" },
    { "imprint_cvd_panel", "CVD Control Panel", "t_cvdmachine", "skyisland_cvd_panel_active" },
  }
  for _, case in ipairs(cases) do
    local s = setup()
    local iuse = s.load("iuse")
    equal(iuse[case[1]](), 0)
    contains(s.messages[1], s.tr(case[2]))
    equal(#s.added, 0)
    s.adjacent = case[3]
    equal(iuse[case[1]](), 1)
    contains(s.messages[#s.messages], s.tr(case[2]))
    equal(s.added[1][1], case[4])
    equal(s.added[1][2], 1)
    equal(#s.removed, 1)
  end
end)

test("warp focus translates shard message and preserves cost", function()
  local s = setup()
  for _, name in ipairs({ "missions", "warp_sickness", "heart", "upgrades", "iuse" }) do s.modules[name] = {} end
  s.modules.teleport = { return_home_success = function() s.returned_home = true end }
  local storage = s.env.game.mod_storage.sky_test
  storage.is_away_from_home = true
  storage.difficulty_emergency_return = 1
  s.load("main")
  equal(s.env.game.mod_runtime.sky_test.use_warp_focus(), 0)
  equal(s.messages[1], s.tr("A warp shard crumbles to dust as the focus activates!"))
  equal(s.charges, 1)
  equal(s.returned_home, true)
end)

test("failed lab warp translates failure/refund and returns catalyst", function()
  local s = setup()
  local teleport = s.load("teleport")
  s.choices = { 1, 2 } -- short raid, then labs (the other locations are locked)
  local storage = { home_location = { x = 0, y = 0, z = 0 }, labs_unlocked = true }
  equal(teleport.use_warp_obelisk(s.player, nil, nil, storage, {}, {}), 0)
  equal(s.messages[#s.messages - 1], s.tr("WARNING: Could not find suitable terrain. Aborting warp."))
  equal(s.messages[#s.messages], s.tr("Your Labs Catalyst is returned."))
  equal(s.added[1][1], "skyisland_labs_catalyst")
  equal(s.added[1][2], 1)
end)

test("difficulty menu translates unknown stored setting", function()
  local s = setup()
  local heart = s.load("heart")
  s.choices = { 4, 4, 7 } -- difficulty, back, close
  heart.use_heart(s.player, nil, nil, { difficulty_pulse_interval = "removed_setting" })
  equal(s.menus[2].entries[1], string.format(s.tr("Warp Pulse Timing: %s"), s.tr("Unknown")))
end)

assert(failures == 0, string.format("%d/%d localization tests failed", failures, total))
print(string.format("All %d localization tests passed (mocked BN APIs).", total))
