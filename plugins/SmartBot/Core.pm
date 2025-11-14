package SmartBot::Core;

use strict;
use warnings;
use Utils qw(distance);

# Zone state
our %ZONE = (
    enabled => 0,
    center_x => 0,
    center_y => 0,
    radius => 15,
);

##
# SmartBot::Core::set_zone($x, $y, $radius)
# $x: X coordinate of zone center
# $y: Y coordinate of zone center
# $radius: Zone radius
#
# Sets the zone center and radius. Enables the zone.
sub set_zone {
    my ($x, $y, $radius) = @_;
    
    $ZONE{center_x} = $x;
    $ZONE{center_y} = $y;
    $ZONE{radius} = $radius || 15;
    $ZONE{enabled} = 1;
}

##
# SmartBot::Core::is_in_zone($x, $y)
# $x: X coordinate to check
# $y: Y coordinate to check
# Returns: 1 if position is in zone, 0 otherwise
#
# Checks if a position is within the zone radius.
sub is_in_zone {
    my ($x, $y) = @_;
    
    return 1 unless $ZONE{enabled};
    
    my $dist = distance(
        { x => $x, y => $y },
        { x => $ZONE{center_x}, y => $ZONE{center_y} }
    );
    
    return $dist <= $ZONE{radius};
}

##
# SmartBot::Core::get_zone_info()
# Returns: Hash reference with zone information
#
# Returns the current zone configuration.
sub get_zone_info {
    return {
        enabled => $ZONE{enabled},
        center_x => $ZONE{center_x},
        center_y => $ZONE{center_y},
        radius => $ZONE{radius},
    };
}

##
# SmartBot::Core::disable_zone()
#
# Disables the zone filtering.
sub disable_zone {
    $ZONE{enabled} = 0;
}

##
# SmartBot::Core::enable_zone()
#
# Enables the zone filtering.
sub enable_zone {
    $ZONE{enabled} = 1;
}

1;
