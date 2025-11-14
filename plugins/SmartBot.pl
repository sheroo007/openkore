package SmartBot;

use strict;
use warnings;
use Plugins;
use Globals qw($char $field %config $net);
use Log qw(message error debug);
use Commands;
use SmartBot::Core;
use SmartBot::Logic;

Plugins::register('SmartBot', 'SmartBot v7.1.1 - Auto Zone Update + Smart Gather', \&on_unload);

my $hooks;
my $commands_handle;

# Initialize plugin
sub on_load {
    $hooks = Plugins::addHooks(
        ['AI_pre', \&on_ai_pre],
        ['packet/map_loaded', \&on_map_loaded],
        ['getBestTarget', \&SmartBot::Logic::check_monster_target],
    );
    
    # Register commands
    $commands_handle = Commands::register(
        ['sbzone', 'SmartBot zone control', \&cmd_sbzone],
        ['sbstatus', 'Show SmartBot status', \&cmd_sbstatus],
        ['sbgather', 'Cancel gathering', \&cmd_sbgather],
    );
    
    message "[SmartBot] Plugin loaded (v7.1.1)\n", 'success';
}

sub on_unload {
    Plugins::delHook($hooks) if $hooks;
    Commands::unregister($commands_handle) if $commands_handle;
    message "[SmartBot] Plugin unloaded\n", 'success';
}

##
# on_ai_pre()
#
# Called on every AI cycle.
sub on_ai_pre {
    return unless $char;
    return unless $net->getState == Network::IN_GAME;
    
    SmartBot::Logic::process();
}

##
# on_map_loaded()
#
# Called when map is loaded.
sub on_map_loaded {
    debug "[SmartBot] Map loaded\n";
    $SmartBot::Logic::STATE{map_loaded_time} = time;
}

##
# cmd_sbzone($command, $args)
# $command: Command name
# $args: Command arguments
#
# Command handler for 'sbzone'.
# Usage:
#   sbzone - Show zone info
#   sbzone <x> <y> <radius> - Set zone
#   sbzone on - Enable zone
#   sbzone off - Disable zone
sub cmd_sbzone {
    my (undef, $args) = @_;
    
    if (!$args || $args eq '') {
        # Show zone info
        my $zone_info = SmartBot::Core::get_zone_info();
        message "=== SmartBot Zone Info ===\n", 'list';
        message sprintf("Status: %s\n", $zone_info->{enabled} ? 'Enabled' : 'Disabled'), 'list';
        message sprintf("Center: (%d, %d)\n", $zone_info->{center_x}, $zone_info->{center_y}), 'list';
        message sprintf("Radius: %d\n", $zone_info->{radius}), 'list';
        
        if ($char && $char->{pos_to}) {
            my $char_x = $char->{pos_to}{x};
            my $char_y = $char->{pos_to}{y};
            if (defined $char_x && defined $char_y) {
                my $in_zone = SmartBot::Core::is_in_zone($char_x, $char_y) ? 'Yes' : 'No';
                message sprintf("Your position: (%d, %d) - In zone: %s\n", $char_x, $char_y, $in_zone), 'list';
            }
        }
    }
    elsif ($args eq 'on') {
        SmartBot::Core::enable_zone();
        message "[SmartBot] Zone enabled\n", 'success';
    }
    elsif ($args eq 'off') {
        SmartBot::Core::disable_zone();
        message "[SmartBot] Zone disabled\n", 'success';
    }
    elsif ($args =~ /^(\d+)\s+(\d+)\s+(\d+)$/) {
        my ($x, $y, $radius) = ($1, $2, $3);
        if ($radius == 0) {
            error "[SmartBot] Radius must be greater than 0\n";
            return;
        }
        SmartBot::Core::set_zone($x, $y, $radius);
        message "[SmartBot] Zone set to ($x, $y) with radius $radius\n", 'success';
    }
    else {
        error "Usage: sbzone [<x> <y> <radius>|on|off]\n";
    }
}

##
# cmd_sbstatus($command, $args)
# $command: Command name
# $args: Command arguments
#
# Command handler for 'sbstatus'.
# Shows current SmartBot status.
sub cmd_sbstatus {
    message "=== SmartBot Status ===\n", 'list';
    
    # Zone info
    my $zone_info = SmartBot::Core::get_zone_info();
    message sprintf("Zone: %s at (%d, %d) r=%d\n",
        $zone_info->{enabled} ? 'Enabled' : 'Disabled',
        $zone_info->{center_x},
        $zone_info->{center_y},
        $zone_info->{radius}
    ), 'list';
    
    # State info
    message sprintf("Teleport count: %d\n", $SmartBot::Logic::STATE{tele_count}), 'list';
    message sprintf("Last position: (%d, %d)\n", 
        $SmartBot::Logic::STATE{last_x}, 
        $SmartBot::Logic::STATE{last_y}
    ), 'list';
    
    # Gathering info
    if ($SmartBot::Logic::STATE{gathering_item}) {
        message "Gathering: Active\n", 'list';
    } else {
        message "Gathering: Idle\n", 'list';
    }
    
    # Config
    message sprintf("Config: radius=%d, autoEnable=%d, smartTeleport=%d, pickupRadius=%d\n",
        $config{smartbot_radius} || 15,
        $config{smartbot_autoEnable} || 0,
        $config{smartbot_smartTeleport} || 0,
        $config{smartbot_pickupRadius} || 10
    ), 'list';
}

##
# cmd_sbgather($command, $args)
# $command: Command name
# $args: Command arguments
#
# Command handler for 'sbgather'.
# Cancels current gathering operation.
sub cmd_sbgather {
    my (undef, $args) = @_;
    
    if ($args eq 'cancel') {
        SmartBot::Logic::cancel_gathering();
        AI::clear('items_gather', 'items_take');
        message "[SmartBot] Gathering cancelled\n", 'success';
    } else {
        if ($SmartBot::Logic::STATE{gathering_item}) {
            message "[SmartBot] Currently gathering items\n", 'info';
        } else {
            message "[SmartBot] Not currently gathering\n", 'info';
        }
    }
}

# Auto-load plugin
on_load();

return 1;
