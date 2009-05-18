package Plugins::Ampache::Settings;

use strict;
use base qw(Slim::Web::Settings);
use Slim::Utils::Prefs;

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

__END__
