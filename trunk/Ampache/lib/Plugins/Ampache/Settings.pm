package Plugins::Ampache::Settings;

# Copyright 2009 Robert Flemming (flemming@spiralout.net)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;

use Slim::Utils::Prefs;

use base qw(Slim::Web::Settings);

my $prefs = preferences('plugin.ampache');

sub name {
  return 'PLUGIN_AMPACHE';
}

sub page {
  return 'plugins/Ampache/settings/basic.html';
}

sub handler {
  my ($class, $client, $params) = @_;

  my @prefs = qw(
    plugin_ampache_server
    plugin_ampache_username
    plugin_ampache_key
    plugin_ampache_version
    plugin_ampache_password
  );

  for my $pref (@prefs) {
    if ($params->{'saveSettings'}) {
      $prefs->set($pref, $params->{$pref});
    }

    $params->{'prefs'}->{$pref} = $prefs->get($pref);
  }

  return $class->SUPER::handler($client, $params);
}

1;
