# SmartBot v7.1.1 Plugin for OpenKore

## Description

SmartBot is a plugin for OpenKore that provides intelligent zone management and automated gathering features for Ragnarok Online.

## Features

### 1. Auto Zone Update
- Automatically updates zone center when teleporting (movement > 20 cells)
- No need to manually return to zone
- Zone follows the player on each teleport

### 2. Smart Gather (Greed Mode)
- Works with OpenKore's built-in item gathering
- Cancels gathering if monsters appear in zone
- Integrates with `itemsTakeGreed` config for BS_GREED skill

### 3. Smart Teleport
- Automatically teleports when no monsters/items in zone
- Configurable delay before teleporting
- Respects gathering state (won't teleport while gathering)
- Resets timer when monsters or items appear

### 4. Zone Filter
- Filters monsters outside zone (won't attack)
- Zone-based monster targeting
- Prevents chasing monsters outside designated area

## Installation

1. Copy the SmartBot plugin files to your OpenKore plugins directory:
   - `plugins/SmartBot.pl`
   - `plugins/SmartBot/Core.pm`
   - `plugins/SmartBot/Logic.pm`

2. The plugin will auto-load when OpenKore starts

## Configuration (config.txt)

Add these settings to your `config.txt`:

```ini
# Lock to a specific map
lockMap mag_dun02

# Zone Settings
smartbot_radius 15                # Zone radius in cells (default: 15)
smartbot_autoEnable 1             # Auto-enable zone on login (default: 0)

# Smart Teleport
smartbot_smartTeleport 1          # Enable smart teleport (default: 0)
smartbot_teleportDelay 2          # Delay in seconds before teleport (default: 2)

# Greed (for Merchant/Blacksmith class)
itemsTakeGreed 1                  # Use Greed skill to pickup items
itemsGatherAuto 1                 # Auto gather items

# Timeouts
ai_take_giveup_timeout 3          # Timeout for item pickup
```

## Commands

### sbzone
Manage zone settings.

**Usage:**
```
sbzone                    # Show current zone info
sbzone <x> <y> <radius>   # Set zone center and radius
sbzone on                 # Enable zone filtering
sbzone off                # Disable zone filtering
```

**Examples:**
```
sbzone                    # Display: Center (65,187), Radius 15
sbzone 100 150 20         # Set zone at position (100,150) with radius 20
sbzone off                # Disable zone filtering temporarily
sbzone on                 # Re-enable zone filtering
```

### sbstatus
Show SmartBot status and statistics.

**Usage:**
```
sbstatus                  # Display current status
```

**Output includes:**
- Zone status (enabled/disabled, center, radius)
- Teleport count
- Last known position
- Gathering status
- Configuration settings

### sbgather
Manage gathering operations.

**Usage:**
```
sbgather                  # Show gathering status
sbgather cancel           # Cancel current gathering
```

## How It Works

### Zone Update on Teleport

1. **Initial Login**: Zone is set to starting position (e.g., 65,187) with configured radius
2. **Teleport #1**: Plugin detects movement > 20 cells → Zone auto-updates to new position (e.g., 214,27)
3. **Teleport #2**: Zone auto-updates again (e.g., 115,112)
4. **Continuous**: Zone follows player on every teleport

### Monster Filtering

- When zone is enabled, only monsters within zone radius are targetable
- Monsters outside zone are skipped by the targeting system
- Uses OpenKore's `getBestTarget` hook for efficient filtering

### Smart Teleport Logic

1. Check if gathering is active → Don't teleport
2. Check if monsters in zone → Reset timer
3. Check if items in zone → Reset timer
4. If zone is empty for configured delay → Teleport
5. After teleport → Zone updates to new position automatically

### Gathering with Greed

1. OpenKore's built-in AI handles item gathering
2. SmartBot tracks gathering state
3. If monster appears while gathering → Cancel and engage monster
4. If `itemsTakeGreed` is enabled, uses BS_GREED skill automatically

## Technical Details

### State Tracking

The plugin maintains these state variables:
- `last_x`, `last_y`: Last known position for teleport detection
- `tele_count`: Number of teleports detected
- `last_teleport_time`: Timestamp of last teleport
- `last_monster_seen_time`: When monsters were last seen in zone
- `last_item_seen_time`: When items were last seen in zone
- `gathering_item`: Whether currently gathering items

### Zone Detection Algorithm

```perl
distance = sqrt((x1-x2)^2 + (y1-y2)^2)
if distance > 20 then
    teleport_detected = true
    update_zone_center(new_x, new_y, radius)
end
```

### Monster Filter Hook

Uses the `getBestTarget` hook to filter monsters:
```perl
hook: getBestTarget
  if monster not in zone then
    skip this monster (return = 1)
  end
```

## Tested On

- **Map**: mag_dun02 (Nogg Road Dungeon)
- **Class**: Merchant (with BS_GREED skill)
- **Radius**: 10-15 cells
- **Results**: ✅ Zone updates correctly, ✅ No spam messages, ✅ Smooth operation

## Troubleshooting

### Zone not updating on teleport
- Check that `smartbot_autoEnable` is set to 1
- Use `sbstatus` to verify zone is enabled
- Make sure you're moving more than 20 cells when teleporting

### Monster outside zone still being attacked
- Verify zone is enabled: `sbzone`
- Check zone center and radius are correct
- Use `sbzone <x> <y> <radius>` to manually set zone

### Smart teleport not working
- Check `smartbot_smartTeleport` is set to 1
- Verify teleport items are available
- Check `smartbot_teleportDelay` is reasonable (2-5 seconds)

## Version History

### v7.1.1 (Current)
- ✅ Fixed zone update on teleport
- ✅ Removed "return to zone" logic (no longer needed)
- ✅ Removed spam messages for out-of-zone detection
- ✅ Simplified zone update logic
- ✅ Fixed error messages syntax
- ✅ Improved monster filtering with getBestTarget hook
- ✅ Better integration with OpenKore's built-in gathering

## Credits

- OpenKore Development Team
- SmartBot Plugin Development

## License

This plugin is distributed under the same license as OpenKore (GNU GPL v2).
