# Sky Islands BN Port - Proof of Concept

This is a minimal proof-of-concept demonstrating the core systems of the Sky Islands port to Cataclysm: Bright Nights.

## What's Implemented

### ✅ Core Systems
- **Teleportation System**: Use warp remote to teleport to a random nearby location
- **Return System**: Use return remote to teleport back home
- **Warp Sickness Timer**: Increments every 5 minutes while away, applies escalating penalties
- **State Persistence**: All state (home location, away status, sickness level, raid stats) persists across save/load
- **Death Resurrection**: If you die while away, you respawn at home with minimal HP

### 📊 Tracked Statistics
- Total raids attempted
- Raids completed successfully
- Raids failed (death)

## How to Test

### Installation
1. Copy the `CBN-Sky-Islands` folder to your Cataclysm-BN `data/mods/` directory
2. Enable the mod when creating a new world

### Getting Test Items
Use the debug menu to spawn these items:
- `skyisland_warp_remote` - Initiates warp expedition
- `skyisland_return_remote` - Returns you home

Or use console:
```
item skyisland_warp_remote
item skyisland_return_remote
```

### Testing Workflow

1. **Start Expedition**:
   - Use the warp remote
   - Select "Quick Raid (Test)"
   - You'll be teleported to a random nearby location
   - Warp sickness timer starts (ticks every 5 minutes)

2. **Wait for Sickness**:
   - Every 5 minutes, the sickness counter increments
   - Messages will appear showing sickness progression
   - At counter 7: "You feel slightly disoriented"
   - At counter 12+: Damage starts applying

3. **Return Home**:
   - Use the return remote
   - Confirm return
   - You'll teleport back to your starting location
   - Sickness clears
   - Success stat increments

4. **Test Save/Load**:
   - Start an expedition
   - Save the game
   - Load the save
   - Sickness timer should resume
   - Return remote should still work

5. **Test Death/Resurrection**:
   - Start an expedition
   - Get yourself killed (spawn hostile monsters, etc.)
   - You should respawn at home with 10 HP
   - Raid marked as failed

## Expected Behavior

### Console Log Output
Check debug.log for these messages:
- "Sky Islands PoC preload complete"
- "Sky Islands storage initialized"
- "Warp sickness tick: X" (every 5 minutes while away)
- Save/load state messages

### Statistics Tracking
- After returning: "Stats: X/Y raids completed successfully"
- Persists across save/load

## Known Limitations (PoC Only)

- No actual missions generated
- No monster spawning on arrival
- No loot or rewards
- Teleport destination is just random offset (no proper location selection)
- No difficulty settings
- No UI for checking stats (only shown on return)
- No island base structure (just uses current location as "home")
- Warp sickness only shows messages (no actual effects/traits applied)

## What This Proves

This PoC successfully demonstrates:
1. ✅ **Menu system works** - UiList and QueryPopup functional
2. ✅ **Item use functions work** - Both warp and return remotes functional
3. ✅ **Teleportation works** - gapi.place_player_overmap_at functional
4. ✅ **Timers work** - gapi.add_on_every_x_hook with 5-minute interval functional
5. ✅ **State persistence works** - game.mod_storage saves/loads correctly
6. ✅ **Hook system works** - on_game_load/save/started/character_death all functional
7. ✅ **Death resurrection works** - Can teleport and heal player on death

## Next Steps for Full Port

After testing this PoC, the full port should implement:
- Complete JSON definitions (all items, furniture, monsters, missions from original)
- Static Sky Island mapgen structure
- Full warp sickness system with effects/traits
- Mission generation system
- Difficulty selection menus
- Proper location selection system
- Progression tracking and unlocks
- Healing system
- Island upgrade system
- All 115 EOCs converted to Lua

## Known Issues

### Scenario Selection Bug
When creating a new character with this mod enabled, the scenario selection may default to "Evacuee" instead of "Sky Island Warper". You must manually select "Sky Island Warper" from the scenario list and press Enter to confirm.

This is a BN engine issue that also affects other mods with custom scenarios (e.g., Innawoods). The SCENARIO_BLACKLIST whitelist makes the scenario available but doesn't prevent auto-selection of the default evacuee scenario.

**Workaround**: Manually select "Sky Island Warper" before starting.

**TODO**: Consider submitting a BN engine patch to support forced scenario selection or default scenario overrides.

## Troubleshooting

### Mod doesn't load
- Check that `modinfo.json` is valid JSON
- Check debug.log for Lua errors
- Ensure BN is recent enough to support Lua mods

### Warp remote doesn't work
- Check debug.log for errors
- Verify the iuse function is registered
- Try reloading Lua with `gdebug.reload_lua_code()` (if in debug mode)

### Sickness timer doesn't tick
- Make sure you successfully warped away (is_away_from_home should be true)
- Wait 5+ minutes of game time
- Check debug.log for "Warp sickness tick" messages

### Save/load doesn't restore state
- Check debug.log for save/load messages
- Verify storage.initialized is true after load
- Confirm mod_storage is persisting (check if raids_total survives restart)
