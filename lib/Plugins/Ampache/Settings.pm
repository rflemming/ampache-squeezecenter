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

use Slim::Utils::Log;
use Slim::Utils::Prefs;

use base qw(Slim::Web::Settings);

my $prefs = preferences('plugin.ampache');
my $log   = logger('plugin.ampache');

# Migrate flat preferences to list/hash based structure
$prefs->migrate(1, sub {
  push my @accounts, {
    'version' => $prefs->get('plugin_ampache_version'),
    'server' => $prefs->get('plugin_ampache_server'),
    'username' => $prefs->get('plugin_ampache_username') || '',
    'password' => $prefs->get('plugin_ampache_password') || '',
    'key' => $prefs->get('plugin_ampache_key') || '',
  };

  if (@accounts) {
    $prefs->set('accounts', \@accounts);

    # Clean out the old preferences
    $prefs->remove('plugin_ampache_version');
    $prefs->remove('plugin_ampache_server');
    $prefs->remove('plugin_ampache_username');
    $prefs->remove('plugin_ampache_password');
    $prefs->remove('plugin_ampache_key');
    
    if ($log->is_debug) {
      $log->debug('Preferences migrated');
    }
  }

  1;
});

# Reload the plugin in the event any of the preferences have changed
$prefs->setChange(
  sub {
    my $newval = $_[1];

    if ($newval) {
      if ($log->is_debug) {
        $log->debug('Reloading plugin after config change');
      }
      Plugins::Ampache::Plugin->initPlugin();
    }

    for my $c (Slim::Player::Client::clients()) {
      Slim::Buttons::Home::updateMenu($c);
    }
  }, 'accounts',
);

sub name {
  return 'PLUGIN_AMPACHE';
}

sub page {
  return 'plugins/Ampache/settings/basic.html';
}

sub handler {
  my ($class, $client, $params) = @_;

  if ($params->{saveSettings}) {
    push my @accounts, {
      version => $params->{pref_version},
      server => $params->{pref_server},
      username => $params->{pref_username} || '',
      password => $params->{pref_password} || '',
      key => $params->{pref_key} || '',
    };
    $prefs->set('accounts', \@accounts);
  }

  # Only support a single account for the time being
  $params->{prefs} = @{$prefs->get('accounts')}[0];

  return $class->SUPER::handler($client, $params);
}

1;
