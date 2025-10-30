package SimpleTeleHunter;

use strict;
use warnings;
use Plugins;
use Settings;
use Globals qw($char %config $net %timeout %monsters_old %monsters $field $accountID);
use Log qw(message error warning debug);
use Utils;
use AI;
use Time::HiRes qw(time);

# Plugin Information
# Version: v4.5.1 (Bug Fix Release)
# Previous: v4.5.0 (Instant Teleport Edition)

Plugins::register('SimpleTeleHunter', 'Smart teleport hunting with instant teleport support', \&on_unload);

my $hooks = Plugins::addHooks(
    ['postloadfiles', \&on_postloadfiles],
    ['Network::Receive::map_loaded', \&on_map_loaded],
    ['AI_pre', \&on_ai_pre],
);

my %state = (
    enabled => 0,
    just_teleported => 0,
    last_teleport_time => 0,
    instant_check_done => 0,
    config => {},
);

sub on_unload {
    Plugins::delHook($hooks);
    message "[SimpleTeleHunter] Plugin unloading.\n", 'success';
}

sub on_postloadfiles {
    load_smart_config();
}

sub on_map_loaded {
    my (undef, $args) = @_;
    
    # Reset instant check flag when map loads after teleport
    if ($state{just_teleported}) {
        $state{instant_check_done} = 0;
        debug "[SimpleTeleHunter] Map loaded after teleport - reset instant_check_done\n", 'SimpleTeleHunter';
    }
}

sub on_ai_pre {
    return unless $state{enabled};
    return unless $field && $field->isReady();
    return unless $char && $char->{pos_to};
    
    # Check if we should perform instant teleport check
    if ($state{just_teleported} && !$state{instant_check_done}) {
        check_instant_teleport();
    }
    
    # Regular teleport check
    my $reason = should_teleport();
    if ($reason) {
        perform_teleport($reason);
    }
}

# Fix 1: Clean Config Parsing - Strip comments from config values
sub load_smart_config {
    my $prefix = 'simpleTeleHunter_';
    %{$state{config}} = ();
    
    foreach my $key (keys %config) {
        if ($key =~ /^$prefix/) {
            my $short_key = $key;
            $short_key =~ s/^$prefix//;
            
            # Strip inline comments (only # after whitespace)
            my $value = $config{$key};
            $value =~ s/\s+#.*$//;  # Remove # and everything after it (only if # is preceded by whitespace)
            $value =~ s/^\s+|\s+$//g;  # Trim whitespace
            
            $state{config}{$short_key} = $value;
        }
    }
    
    # Check if plugin should be enabled
    $state{enabled} = $state{config}{enabled} || 0;
    
    if ($state{enabled}) {
        message "[SimpleTeleHunter v4.5.1] Loaded configuration:\n", 'success';
        foreach my $key (sort keys %{$state{config}}) {
            message "  $key = $state{config}{$key}\n", 'success';
        }
    }
}

# Fix 3: Fix Instant Teleport Logic with proper timing
sub check_instant_teleport {
    my $grace_period = $state{config}{instantGracePeriod} || 0.5;
    my $instant_radius = $state{config}{instantRadius} || 7;
    
    my $time_since_teleport = time - $state{last_teleport_time};
    
    # Wait for grace period before checking
    if ($time_since_teleport < $grace_period) {
        return;
    }
    
    # Mark check as done
    $state{instant_check_done} = 1;
    
    # Fix 2: Count only our monsters using new function
    my $our_monsters = count_our_monsters($instant_radius);
    
    debug "[SimpleTeleHunter] Instant check after ${time_since_teleport}s grace: found $our_monsters relevant monsters\n", 'SimpleTeleHunter';
    
    if ($our_monsters == 0) {
        message "[SimpleTeleHunter] Instant teleport: No relevant monsters nearby!\n", 'info';
        perform_teleport('instant_empty');
    } else {
        message "[SimpleTeleHunter] Found $our_monsters relevant monsters - staying to hunt\n", 'info';
        $state{just_teleported} = 0;  # Clear flag, we're staying
    }
}

# Fix 2: Implement Proper Monster Counting
# Only counts monsters we're fighting or clean monsters
sub count_our_monsters {
    my ($radius) = @_;
    $radius ||= 7;
    
    return 0 unless $char && $char->{pos_to};
    
    my $count = 0;
    my @counted_monsters = ();
    my @ignored_monsters = ();
    
    foreach my $monster (@{$monsters_old->getItems()}) {
        next if $monster->{dead};
        next unless $monster->{pos_to};
        
        my $distance = Utils::distance($char->{pos_to}, $monster->{pos_to});
        next if $distance > $radius;
        
        my $name = $monster->name();
        
        # Check if we damaged this monster
        my $we_damaged = ($monster->{dmgFromYou} || 0) > 0;
        
        # Check if someone else damaged this monster
        my $others_damaged = 0;
        if ($monster->{dmgFromPlayer} && ref($monster->{dmgFromPlayer}) eq 'HASH') {
            # Ensure $accountID is defined before comparison
            my $our_id = $accountID || '';
            foreach my $player_id (keys %{$monster->{dmgFromPlayer}}) {
                if ($player_id ne $our_id) {
                    $others_damaged = 1;
                    last;
                }
            }
        }
        
        # Count this monster if:
        # 1. We damaged it
        # 2. OR it's a clean monster (no one attacked yet)
        if ($we_damaged || !$others_damaged) {
            $count++;
            my $reason = $we_damaged ? "we damaged it" : "clean monster";
            push @counted_monsters, "$name (${distance}m): $reason";
        } else {
            push @ignored_monsters, "$name (${distance}m): others damaged";
        }
    }
    
    # Fix 4: Add Better Debugging
    if (@counted_monsters) {
        debug "[SimpleTeleHunter] Counted $count monsters:\n", 'SimpleTeleHunter';
        foreach my $msg (@counted_monsters) {
            debug "  + $msg\n", 'SimpleTeleHunter';
        }
    }
    
    if (@ignored_monsters) {
        debug "[SimpleTeleHunter] Ignored monsters being fought by others:\n", 'SimpleTeleHunter';
        foreach my $msg (@ignored_monsters) {
            debug "  - $msg\n", 'SimpleTeleHunter';
        }
    }
    
    return $count;
}

sub should_teleport {
    my $idle_time = $state{config}{idleTime} || 5;
    my $check_radius = $state{config}{checkRadius} || 10;
    
    # Don't check if we just teleported and haven't done instant check yet
    return if $state{just_teleported} && !$state{instant_check_done};
    
    # Check if character is idle
    return unless AI::isIdle() || AI::is('route', 'sitAuto', 'follow');
    
    # Simple idle time check
    if ($timeout{ai_teleport_idle}{time} && time - $timeout{ai_teleport_idle}{time} > $idle_time) {
        my $our_monsters = count_our_monsters($check_radius);
        
        if ($our_monsters == 0) {
            return 'idle_no_monsters';
        }
    }
    
    return;
}

sub perform_teleport {
    my ($reason) = @_;
    
    message "[SimpleTeleHunter] Teleporting: $reason\n", 'teleport';
    
    # Use teleport skill or item
    my $teleport_spell = $state{config}{teleportSpell} || 'Teleport';
    
    # Set teleport state
    $state{just_teleported} = 1;
    $state{last_teleport_time} = time;
    $state{instant_check_done} = 0;
    
    # Reset timeout
    $timeout{ai_teleport_idle}{time} = time;
    
    # Trigger teleport
    if ($state{config}{testMode}) {
        debug "[SimpleTeleHunter] TEST MODE: Would teleport using: $teleport_spell\n", 'SimpleTeleHunter';
    } else {
        # Actual teleport implementation
        require Commands;
        Commands::run("teleport");
        debug "[SimpleTeleHunter] Teleporting using: $teleport_spell\n", 'SimpleTeleHunter';
    }
}

1;

__END__

=head1 NAME

SimpleTeleHunter - Smart teleport hunting with instant teleport support

=head1 VERSION

Version 4.5.1 (Bug Fix Release)

=head1 DESCRIPTION

A plugin that manages teleport-based hunting with smart monster counting and instant teleport support.

=head2 FIXES IN v4.5.1

=over 4

=item * Fix 1: Clean config parsing - strips inline comments from config values

=item * Fix 2: Proper monster counting - only counts monsters we're fighting or clean monsters

=item * Fix 3: Fixed instant teleport logic with proper flag reset and timing

=item * Fix 4: Better debugging with detailed monster ownership information

=back

=head2 CONFIGURATION

Add these settings to your config.txt:

  simpleTeleHunter_enabled 1
  simpleTeleHunter_idleTime 5
  simpleTeleHunter_instantRadius 7
  simpleTeleHunter_instantGracePeriod 0.5
  simpleTeleHunter_checkRadius 10
  simpleTeleHunter_teleportSpell Teleport

=head2 MONSTER COUNTING LOGIC

The plugin counts only relevant monsters:

=over 4

=item * Monsters we have damaged (dmgFromYou > 0)

=item * Clean monsters that no one has attacked yet

=item * EXCLUDES monsters being fought by other players

=back

=head2 INSTANT TELEPORT

After teleporting, the plugin waits for a grace period (default 0.5s) then checks:

=over 4

=item * If no relevant monsters nearby -> instant teleport again

=item * If relevant monsters found -> stay and hunt

=back

=head1 AUTHOR

SimpleTeleHunter Plugin

=cut
