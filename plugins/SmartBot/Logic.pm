package SmartBot::Logic;

use strict;
use warnings;
use Time::HiRes qw(time);
use Globals qw($char $field %config %timeout @monstersID %monsters @itemsID %items $net);
use Utils qw(distance timeOut);
use AI;
use Skill;
use Misc qw(canUseTeleport);
use Log qw(message debug);
use Network;
use SmartBot::Core;

# State variables
our %STATE = (
    last_x => 0,
    last_y => 0,
    tele_count => 0,
    last_teleport_time => 0,
    last_teleport_check_time => 0,
    map_loaded_time => 0,
    last_monster_seen_time => 0,
    last_item_seen_time => 0,
    gathering_item => 0,
    gather_start_time => 0,
);

##
# SmartBot::Logic::process()
#
# Main processing loop called by AI_pre hook.
sub process {
    return unless $char && $net->getState == Network::IN_GAME;
    return unless $field;
    
    # Detect teleport and update zone
    detect_teleport();
    
    # Track gathering state for smart teleport
    smart_gather_items();
    
    # Smart teleport
    process_teleport() if $config{smartbot_smartTeleport};
}

##
# SmartBot::Logic::detect_teleport()
#
# Detects teleport by checking if player moved more than 20 cells.
# Auto-updates zone center to new position.
sub detect_teleport {
    return unless $char;
    
    my $current_x = $char->{pos_to}{x};
    my $current_y = $char->{pos_to}{y};
    
    # Initialize on first run
    if ($STATE{last_x} == 0 && $STATE{last_y} == 0) {
        $STATE{last_x} = $current_x;
        $STATE{last_y} = $current_y;
        
        # Set initial zone if autoEnable is on
        if ($config{smartbot_autoEnable}) {
            my $radius = $config{smartbot_radius} || 15;
            SmartBot::Core::set_zone($current_x, $current_y, $radius);
            debug "[SmartBot] Initial zone set at ($current_x, $current_y) radius=$radius\n";
        }
        return;
    }
    
    # Calculate distance from last position
    my $dist = distance(
        { x => $STATE{last_x}, y => $STATE{last_y} },
        { x => $current_x, y => $current_y }
    );
    
    # Detect teleport (moved more than 20 cells instantly)
    if ($dist > 20) {
        $STATE{tele_count}++;
        $STATE{last_teleport_time} = time;
        
        # Auto-update zone to new position
        my $zone_info = SmartBot::Core::get_zone_info();
        if ($zone_info->{enabled}) {
            my $radius = $zone_info->{radius};
            SmartBot::Core::set_zone($current_x, $current_y, $radius);
            debug "[SmartBot] Teleport #$STATE{tele_count} detected! Zone updated to ($current_x, $current_y) radius=$radius\n";
        }
    }
    
    # Update last position
    $STATE{last_x} = $current_x;
    $STATE{last_y} = $current_y;
}

##
# SmartBot::Logic::smart_gather_items()
#
# Handles smart gathering logic - the actual gathering is done by OpenKore's built-in AI.
# This function mainly tracks the gathering state and cancels if monsters appear.
sub smart_gather_items {
    return unless $char;
    
    my $current_time = time;
    
    # Check if currently gathering (AI has items_gather or items_take)
    if (AI::is('items_gather', 'items_take')) {
        $STATE{gathering_item} = 1;
        $STATE{gather_start_time} = $current_time unless $STATE{gather_start_time};
        
        # Cancel gathering if monster detected in zone
        if (has_monsters_in_zone()) {
            debug "[SmartBot] Monster detected! Canceling gather.\n";
            cancel_gathering();
            # Clear the AI queue
            AI::clear('items_gather', 'items_take');
            return;
        }
    } else {
        # Not gathering anymore, reset state
        if ($STATE{gathering_item}) {
            $STATE{gathering_item} = 0;
            $STATE{gather_start_time} = 0;
        }
    }
}

##
# SmartBot::Logic::cancel_gathering()
#
# Cancels the current gathering operation.
sub cancel_gathering {
    $STATE{gathering_item} = 0;
    $STATE{gather_start_time} = 0;
}

##
# SmartBot::Logic::has_monsters_in_zone()
# Returns: 1 if monsters found in zone, 0 otherwise
#
# Checks if there are any monsters within the zone.
sub has_monsters_in_zone {
    return 0 unless $char;
    
    foreach my $monster_id (@monstersID) {
        next unless $monster_id;
        my $monster = $monsters{$monster_id};
        next unless $monster;
        
        my $monster_x = $monster->{pos_to}{x};
        my $monster_y = $monster->{pos_to}{y};
        
        if (SmartBot::Core::is_in_zone($monster_x, $monster_y)) {
            $STATE{last_monster_seen_time} = time;
            return 1;
        }
    }
    
    return 0;
}

##
# SmartBot::Logic::has_items_in_zone()
# Returns: 1 if items found in zone, 0 otherwise
#
# Checks if there are any items within the zone.
sub has_items_in_zone {
    return 0 unless $char;
    
    foreach my $item_id (@itemsID) {
        next unless $item_id;
        my $item = $items{$item_id};
        next unless $item;
        
        my $item_x = $item->{pos}{x};
        my $item_y = $item->{pos}{y};
        
        if (SmartBot::Core::is_in_zone($item_x, $item_y)) {
            $STATE{last_item_seen_time} = time;
            return 1;
        }
    }
    
    return 0;
}

##
# SmartBot::Logic::process_teleport()
#
# Handles smart teleport logic:
# - Don't teleport while gathering
# - Don't teleport if monsters or items in zone
# - Teleport after delay if zone is empty
sub process_teleport {
    return unless $char;
    return if $STATE{gathering_item};  # Don't teleport while gathering
    
    my $current_time = time;
    my $teleport_delay = $config{smartbot_teleportDelay} || 2;
    
    # Check if there are monsters or items in zone
    my $has_monsters = has_monsters_in_zone();
    my $has_items = has_items_in_zone();
    
    # Reset timer if monsters or items found
    if ($has_monsters || $has_items) {
        $STATE{last_teleport_check_time} = $current_time;
        return;
    }
    
    # Initialize timer if not set
    if ($STATE{last_teleport_check_time} == 0) {
        $STATE{last_teleport_check_time} = $current_time;
        return;
    }
    
    # Check if delay has passed
    my $time_since_check = $current_time - $STATE{last_teleport_check_time};
    if ($time_since_check >= $teleport_delay) {
        # Teleport if possible
        if (canUseTeleport(1)) {
            debug "[SmartBot] No monsters/items for ${teleport_delay}s, teleporting...\n";
            AI::ai_useTeleport(1);
            $STATE{last_teleport_check_time} = $current_time;
        }
    }
}

##
# SmartBot::Logic::check_monster_target($args)
# $args: Hook arguments from getBestTarget hook
# Returns: Modified $args with return=1 to skip this monster
#
# Hook for checking if monster should be attacked (zone filter).
sub check_monster_target {
    my (undef, $args) = @_;
    return unless $args;
    
    my $zone_info = SmartBot::Core::get_zone_info();
    return unless $zone_info->{enabled};
    
    # Get monster from target
    my $monster = $args->{target};
    return unless $monster;
    
    # Check if monster is in zone
    my $monster_x = $monster->{pos_to}{x};
    my $monster_y = $monster->{pos_to}{y};
    
    unless (SmartBot::Core::is_in_zone($monster_x, $monster_y)) {
        # Monster outside zone, skip attack
        $args->{return} = 1;
    }
}

1;
