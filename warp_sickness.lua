-- Sky Islands BN Port - Warp Sickness System
-- Handles warp sickness progression using JSON effects

local warp_sickness = {}

-- Warp sickness timing
local WARP_SICKNESS_INTERVAL = TimeDuration.from_minutes(15)  -- Normal difficulty
local GRACE_PERIOD_PULSES = 8  -- 8 pulses × 15 min = 2 hours before sickness starts
local MAX_WARP_SICKNESS_INTENSITY = 6

-- Effect IDs
local EFFECT_WARP_SICKNESS = EffectTypeId.new("skyisland_warpsickness")
local EFFECT_DISINTEGRATION = EffectTypeId.new("skyisland_warpdisintegration")

-- Warp sickness timer tick - pulse counter and intensity management
function warp_sickness.tick(storage)
  if not storage.is_away_from_home then
    return true  -- Keep hook active
  end

  local player = gapi.get_avatar()
  if not player then
    return true
  end

  -- Increment pulse counter
  storage.warp_pulse_count = (storage.warp_pulse_count or 0) + 1
  local pulse = storage.warp_pulse_count

  gdebug.log_info(string.format("Warp pulse %d", pulse))

  -- Grace period: first 8 pulses (2 hours) have no effect
  if pulse <= GRACE_PERIOD_PULSES then
    local remaining = GRACE_PERIOD_PULSES - pulse + 1
    gapi.add_msg(string.format("Warp pulse. You feel fine. Safe for %d more pulses.", remaining))
    return true
  end

  -- Apply or update warp sickness effect
  player:add_effect(EFFECT_WARP_SICKNESS, TimeDuration.from_hours(999), 1)
  gdebug.log_info(string.format("Warp sickness re-applied"))

  local current_intensity = player:get_effect_int(EFFECT_WARP_SICKNESS)
  -- Apply disintegration at critical intensity
  if current_intensity == MAX_WARP_SICKNESS_INTENSITY then
    if not player:has_effect(EFFECT_DISINTEGRATION) then
      player:add_effect(EFFECT_DISINTEGRATION, TimeDuration.from_hours(999))
      gapi.add_msg("You're being unmade!")
    end
  end

  return true  -- Keep running
end

-- Start warp sickness - initialize pulse counter
function warp_sickness.start(storage)
  -- Reset pulse counter for new expedition
  storage.warp_pulse_count = 0
  gdebug.log_info("Warp sickness: initialized with grace period")
end

-- Start warp sickness timer
function warp_sickness.start_timer(storage)
  gapi.add_on_every_x_hook(WARP_SICKNESS_INTERVAL, function()
    return warp_sickness.tick(storage)
  end)
end

-- Stop warp sickness - remove all effects
function warp_sickness.stop()
  local player = gapi.get_avatar()
  if not player then
    return
  end

  -- Remove effects
  player:remove_effect(EFFECT_WARP_SICKNESS)
  player:remove_effect(EFFECT_DISINTEGRATION)

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
