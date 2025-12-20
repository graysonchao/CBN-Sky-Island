-- Sky Islands BN Port - Warp Sickness System
-- Handles warp sickness progression using JSON effects

local warp_sickness = {}

-- Warp sickness timing
local BASE_WARP_SICKNESS_INTERVAL = TimeDuration.from_minutes(15)  -- Normal difficulty
local BASE_GRACE_PERIOD_PULSES = 8  -- 8 pulses × 15 min = 2 hours before sickness starts
local MAX_WARP_SICKNESS_INTENSITY = 6

-- Effect IDs
local EFFECT_WARP_SICKNESS = EffectTypeId.new("skyisland_warpsickness")
local EFFECT_DISINTEGRATION = EffectTypeId.new("skyisland_warpdisintegration")

-- Status names for each intensity level
local STATUS_NAMES = {
  [0] = "Stable",
  [1] = "Warp Sickness",
  [2] = "Warp Nausea",
  [3] = "Warp Debilitation",
  [4] = "Warp Necrosis",
  [5] = "Warp Disintegration",
  [6] = "CRITICAL"
}

-- Get current warp status info for display
function warp_sickness.get_status_info(storage)
  local player = gapi.get_avatar()
  local pulse = storage.warp_pulse_count or 0
  local stability_bonus = storage.stability_unlocked or 0
  local grace_period = BASE_GRACE_PERIOD_PULSES + stability_bonus

  local info = {
    current_pulse = pulse,
    grace_period = grace_period,
    in_grace_period = pulse <= grace_period,
    pulses_remaining = 0,
    current_intensity = 0,
    status_name = "Stable",
    pulses_to_disintegration = 0
  }

  if info.in_grace_period then
    info.pulses_remaining = grace_period - pulse
  else
    -- Get current intensity from effect
    if player and player:has_effect(EFFECT_WARP_SICKNESS) then
      info.current_intensity = player:get_effect_int(EFFECT_WARP_SICKNESS)
    else
      info.current_intensity = pulse - grace_period
    end
    info.status_name = STATUS_NAMES[info.current_intensity] or "CRITICAL"
    info.pulses_to_disintegration = math.max(0, MAX_WARP_SICKNESS_INTENSITY - info.current_intensity)
  end

  return info
end

-- Show warp pulse dialog (blocking popup)
local function show_pulse_dialog(message, color)
  local popup = QueryPopup.new()
  popup:message(message)
  -- Color disabled for now - debugging binding issue
  -- if color then
  --   popup:message_color(color)
  -- end
  popup:allow_any_key(true)
  popup:query()
end

-- Warp sickness timer tick - pulse counter and intensity management
function warp_sickness.tick(storage)
  if not storage.is_away_from_home then
    return false  -- Stop hook when home - prevents stacking hooks on multiple expeditions
  end

  -- Prevent re-entry (can happen if multiple intervals pass during wait/sleep)
  if tick_in_progress then
    gdebug.log_info("Warp pulse tick already in progress, skipping")
    return true  -- Keep timer running but skip this tick
  end
  tick_in_progress = true

  local player = gapi.get_avatar()
  if not player then
    tick_in_progress = false
    return true
  end

  -- Increment pulse counter
  storage.warp_pulse_count = (storage.warp_pulse_count or 0) + 1
  local pulse = storage.warp_pulse_count

  -- Calculate grace period based on stability upgrades
  local stability_bonus = storage.stability_unlocked or 0
  local grace_period = BASE_GRACE_PERIOD_PULSES + stability_bonus
  local pulse_multiplier = storage.current_raid_pulse_multiplier or 1
  local interval_minutes = 15 * pulse_multiplier

  gdebug.log_info(string.format("Warp pulse %d (grace period: %d)", pulse, grace_period))

  -- Grace period: pulses during grace have no effect
  if pulse <= grace_period then
    local remaining = grace_period - pulse
    local time_remaining = remaining * interval_minutes

    if remaining > 3 then
      -- Still plenty of time - green
      show_pulse_dialog(
        string.format("=== WARP PULSE ===\n\n" ..
          "You feel fine.\n\n" ..
          "Safe pulses remaining: %d\n" ..
          "Time until sickness: ~%d minutes\n\n" ..
          "[Press any key to continue]",
          remaining, time_remaining),
        Color.c_green)
    elseif remaining > 0 then
      -- Getting close - yellow warning
      show_pulse_dialog(
        string.format("=== WARP PULSE ===\n\n" ..
          "The warp begins to tug at you...\n\n" ..
          "Safe pulses remaining: %d\n" ..
          "Time until sickness: ~%d minutes\n\n" ..
          "[Press any key to continue]",
          remaining, time_remaining),
        Color.c_yellow)
    else
      -- Last safe pulse
      show_pulse_dialog(
        "=== WARP PULSE ===\n\n" ..
          "WARNING: This is your last safe pulse!\n" ..
          "The next pulse will begin warp sickness.\n\n" ..
          "[Press any key to continue]",
        Color.c_light_red)
    end
    tick_in_progress = false
    return true
  end

  -- Apply or update warp sickness effect
  player:add_effect(EFFECT_WARP_SICKNESS, TimeDuration.from_hours(999))
  local current_intensity = player:get_effect_int(EFFECT_WARP_SICKNESS)
  local status_name = STATUS_NAMES[current_intensity] or "CRITICAL"
  local pulses_to_doom = MAX_WARP_SICKNESS_INTENSITY - current_intensity

  gdebug.log_info(string.format("Warp sickness applied/updated, intensity now: %d", current_intensity))

  -- Apply disintegration at critical intensity
  if current_intensity >= MAX_WARP_SICKNESS_INTENSITY then
    if not player:has_effect(EFFECT_DISINTEGRATION) then
      player:add_effect(EFFECT_DISINTEGRATION, TimeDuration.from_hours(999))
    end
    -- Critical - flashing red
    show_pulse_dialog(
      "=== WARP PULSE ===\n\n" ..
        "!!! WARP DISINTEGRATION !!!\n\n" ..
        "You are being unmade!\n" ..
        "Your body is coming apart at the seams!\n" ..
        "GET TO THE EXIT IMMEDIATELY!\n\n" ..
        "[Press any key to continue]",
      Color.i_red)
  elseif current_intensity >= 4 then
    -- Severe - red
    show_pulse_dialog(
      string.format("=== WARP PULSE ===\n\n" ..
        "STATUS: %s (Intensity %d/6)\n\n" ..
        "Your body is failing!\n" ..
        "Stats: -%d to all\n" ..
        "Pulses until disintegration: %d\n\n" ..
        "You MUST return home soon!\n\n" ..
        "[Press any key to continue]",
        status_name, current_intensity, current_intensity * 2, pulses_to_doom),
      Color.c_red)
  elseif current_intensity >= 2 then
    -- Moderate - light red/orange
    show_pulse_dialog(
      string.format("=== WARP PULSE ===\n\n" ..
        "STATUS: %s (Intensity %d/6)\n\n" ..
        "The warp sickness grows stronger.\n" ..
        "Stats: -%d to all\n" ..
        "Pulses until disintegration: %d\n\n" ..
        "Consider returning home soon.\n\n" ..
        "[Press any key to continue]",
        status_name, current_intensity, current_intensity * 2, pulses_to_doom),
      Color.c_light_red)
  else
    -- Mild - yellow
    show_pulse_dialog(
      string.format("=== WARP PULSE ===\n\n" ..
        "STATUS: %s (Intensity %d/6)\n\n" ..
        "The warp begins to affect you.\n" ..
        "Stats: -%d to all\n" ..
        "Pulses until disintegration: %d\n\n" ..
        "[Press any key to continue]",
        status_name, current_intensity, current_intensity * 2, pulses_to_doom),
      Color.c_yellow)
  end

  tick_in_progress = false
  return true  -- Keep running
end

-- Start warp sickness - initialize pulse counter
function warp_sickness.start(storage)
  -- Reset pulse counter for new expedition
  storage.warp_pulse_count = 0
  gdebug.log_info("Warp sickness: initialized with grace period")
end

-- Track if timer is already running to prevent duplicates
local timer_running = false
-- Prevent re-entry during popup display
local tick_in_progress = false

-- Start warp sickness timer
function warp_sickness.start_timer(storage)
  -- Prevent duplicate timers
  if timer_running then
    gdebug.log_info("Warp sickness timer already running, skipping duplicate start")
    return
  end
  timer_running = true

  -- Pulse interval is multiplied by raid type (1x short, 2x medium, 3x long)
  local pulse_multiplier = storage.current_raid_pulse_multiplier or 1
  local interval = TimeDuration.from_minutes(15 * pulse_multiplier)
  gdebug.log_info(string.format("Warp sickness timer started: %d minute intervals", 15 * pulse_multiplier))
  gapi.add_on_every_x_hook(interval, function()
    local result = warp_sickness.tick(storage)
    if not result then
      timer_running = false  -- Timer stopped, allow new one
    end
    return result
  end)
end

-- Stop warp sickness - remove all effects
function warp_sickness.stop()
  -- Reset timer flags so a new timer can be started next expedition
  timer_running = false
  tick_in_progress = false

  local player = gapi.get_avatar()
  if not player then
    return
  end

  -- Remove effects
  player:remove_effect(EFFECT_WARP_SICKNESS)
  player:remove_effect(EFFECT_DISINTEGRATION)

  -- Also remove resurrection sickness if present (stops the tick hook)
  local res_sick_effect = EffectTypeId.new("skyisland_resurrection_sickness")
  player:remove_effect(res_sick_effect)

  gdebug.log_info("Warp sickness stopped and cleared")
end

-- Resurrection sickness tick - forcibly stabilize the player
function warp_sickness.resurrection_tick()
  local player = gapi.get_avatar()
  if not player then return true end

  -- Check if player has resurrection sickness effect
  local res_sick_effect = EffectTypeId.new("skyisland_resurrection_sickness")
  if player:has_effect(res_sick_effect) then
    -- Get remaining duration before clearing
    local remaining_dur = player:get_effect_dur(res_sick_effect)

    -- Clear ALL effects (including broken limbs, poison, etc.)
    player:clear_effects()

    -- Forcibly heal all parts to 10 HP
    player:set_all_parts_hp_cur(10)

    -- Set pain to 10 if it's greater than 10
    if player:get_pain() > 10 then
      player:set_pain(10)
    end

    -- Re-apply resurrection sickness with remaining duration
    player:add_effect(res_sick_effect, remaining_dur)

    return true  -- Keep running while effect is active
  else
    return false  -- Stop running when effect expires
  end
end

-- Apply resurrection sickness after death
function warp_sickness.apply_resurrection_sickness()
  local player = gapi.get_avatar()
  if not player then return end

  -- Set HP immediately
  player:set_all_parts_hp_cur(10)

  -- Set pain to 10 for resurrection penalty
  player:set_pain(10)

  -- Apply resurrection sickness effect to stabilize over 10 seconds
  local res_sick_effect = EffectTypeId.new("skyisland_resurrection_sickness")
  player:add_effect(res_sick_effect, TimeDuration.from_seconds(10))

  -- Start resurrection stabilization tick (runs every second)
  gapi.add_on_every_x_hook(TimeDuration.from_seconds(1), function()
    return warp_sickness.resurrection_tick()
  end)
end

return warp_sickness
