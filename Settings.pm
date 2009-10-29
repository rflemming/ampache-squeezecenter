package Plugins::SiriusRadio::Settings;

# SlimServer Copyright (C) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.siriusradio');

sub name {
        return 'PLUGIN_SIRIUSRADIO';
}

sub page {
        return 'plugins/SiriusRadio/settings/basic.html';
}

sub handler {
	my ($class, $client, $params) = @_;

	my @prefs = qw(
		plugin_siriusradio_username
		plugin_siriusradio_password
		plugin_siriusradio_location
		plugin_siriusradio_bitrate
		plugin_siriusradio_titlesource
		plugin_siriusradio_presets
	);

	for my $pref (@prefs) {
		if ($params->{'saveSettings'}) {
			if ($pref eq 'plugin_siriusradio_password' && $params->{$pref} ne '') {
				$params->{$pref} = pack('u', $params->{$pref});

				chomp($params->{$pref});
				$prefs->set($pref, $params->{$pref});
			}
			elsif ($pref eq 'plugin_siriusradio_presets') {
				# Remove empties.
				my @presets = grep { $_ ne '' } @{$params->{'plugin_siriusradio_presets'}};
				$prefs->set('plugin_siriusradio_presets', \@presets);
			}			
			elsif ($pref ne 'plugin_siriusradio_password') {
				$prefs->set($pref, $params->{$pref});
			}
		}

		# Do we want to display the password?
		if ($pref eq 'plugin_siriusradio_password') {
			next;
		}

		$params->{'prefs'}->{$pref} = $prefs->get($pref);
	}

	if ($params->{'saveSettings'}) {
		Plugins::SiriusRadio::Plugin::setCookies();
	}
	
	return $class->SUPER::handler($client, $params);
}

1;

__END__
