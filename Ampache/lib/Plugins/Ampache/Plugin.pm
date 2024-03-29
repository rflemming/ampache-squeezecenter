package Plugins::Ampache::Plugin;

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
use warnings;

use Slim::Formats::RemoteMetadata;
use Slim::Formats::XML;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

use Ampache::Ampache;
use Plugins::Ampache::Browse;
use Plugins::Ampache::Settings;

use base qw(Slim::Plugin::OPMLBased);

my $prefs = preferences('plugin.ampache');

my $log = Slim::Utils::Log->addLogCategory({
  'category'     => 'plugin.ampache',
  'defaultLevel' => 'INFO',
  'description'  => getDisplayName(),
});

# Store an Ampache::Ampache instance for easy access
my $ampache;

# Login to the server, if it fails log a message.  It will also be
# displayed via feed()
sub authenticate {
  my $params = shift;
  my $ampache = Ampache->new();
  # Turn on module level debugging if plugin debugging is enabled
  $ampache->debug($log->is_debug);

  # Since version is mandatory we can use that to determine whether or
  # not the plugin has been configured.
  my $version = $params->{version};
  if ($version) {
    my $key = $params->{key};
    if ($version eq "3.4") {
      $version = 340001;
    } elsif ($version eq "3.5") {
      $version = 350001;
      # 3.5 uses the user's password rather than a key
      $key = $params->{password};
    }

    $log->debug('Authenticating...');
    $ampache->connect(
      $params->{server} . '/server/xml.server.php',
      $key,
      $params->{username},
      $version,
    );

    if ($ampache->{auth}) {
      $log->debug("Logged in with token: $ampache->{auth}");
    } elsif ($ampache->{error_code}) {
      $log->info("Login failed ($ampache->{error_code}): $ampache->{error}");
    } else {
      $ampache->{error_code} = "400";
      $ampache->{error} = "Unknown authentication error";
    }
  } else {
    $ampache->{error_code} = "400";
    $ampache->{error} = "No servers configured";
  }

  return $ampache;
}

sub initPlugin {
  my $class = shift;

  Plugins::Ampache::Settings->new;

  # Even though we can theoretically support multiple accounts, we only
  # use the first one right now
  my $account = @{$prefs->get('accounts')}[0] || {};
  $ampache = authenticate($account);

  Slim::Player::ProtocolHandlers->registerIconHandler(
      qr{/play/index\.php\?(.+)},
      sub { return $class->_pluginDataFor('icon'); }
  );

  $class->SUPER::initPlugin(
      tag            => 'ampache',
      menu           => 'radios',
      weight         => 50,
  );

  Slim::Formats::RemoteMetadata->registerProvider(
    match => qr{/play/index\.php\?(.+)},
    func   => \&metaProvider,
  );

  if ( main::SLIM_SERVICE ) {
    my $menu = {
      useMode => sub { $class->setMode(@_) },
      header  => string('PLUGIN_AMPACHE'),
    };

    Slim::Buttons::Home::addSubMenu(
        'RADIO',
        'PLUGIN_AMPACHE',
        $menu,
    );

    $class->initCLI(
        tag  => 'ampache_radio',
        menu => 'radios',
    );
  }
}

sub feed {
  my $class = shift;

  my @items;
  # If there was a login error we'll catch it here, otherwise return the
  # main menu
  if ($ampache->error()) {
    @items = (&Error());
  } else {
    # This could probably be refactored in a less ugly way.  The 'url'
    # is the function which generates the OPML itself for the object
    # type being returned.  'passthrough' takes an Ampache::Ampache
    # instance and the function which fetches the raw data from the
    # server.
    @items = (
      {
        'name' => string('ALBUMS'),
        'type' => 'opml',
        'url' => \&Plugins::Ampache::Browse::getAlbums,
        'passthrough' => [$ampache, \&Ampache::getAlbums],
      },
      {
        'name' => string('ARTISTS'),
        'type' => 'opml',
        'url' => \&Plugins::Ampache::Browse::getArtists,
        'passthrough' => [$ampache, \&Ampache::getArtists],
      },
      {
        'name' => string('PLAYLISTS'),
        'type' => 'opml',
        'url' => \&Plugins::Ampache::Browse::getPlaylists,
        'passthrough' => [$ampache], # No function since there is only
                                     # one way to fetch Playlist objects.
      },
    );

    # 3.4 has genres, 3.5 tags
    my $name;
    if ($ampache->{version} == 340001) {
        $name = string('GENRES');
    } elsif ($ampache->{version} >= 350001) {
        $name = string('TAGS');
    }
    push @items, {
      'name' => $name,
      'type' => 'opml',
      'url' => \&Plugins::Ampache::Browse::getGenresTags,
      'passthrough' => [$ampache], # No function due to sub-menu
    };
  }

  $log->debug('Items: ' . ($#items + 1));

  # Dance around button mode stuff.  I don't really understand it, but
  # it works so woohoo.
  my $caller = (caller(1))[3];
  if ($caller =~ /setMode/) {
    return sub { $_[1]->(\@items) };
  } else {
    return { title => string('PLUGIN_AMPACHE'), items => \@items };
  }
}

sub Error {
  my $error = shift;

  # First use the internal Ampache message, then the user specified one
  # so that we can catch all errors with a single test while browsing.
  if ($ampache->error()) {
    my @error = $ampache->error();
    $error = "$error[0] - $error[1]";
  } elsif (! $error) {
    $error = "Unknown error";
  }

  # Log the error and return it is a feed item.  Clicking it won't do
  # much, but it's the only way to return the error
  $log->info($error);

  return {'name' => $error};
}

sub getDisplayName {
  return 'PLUGIN_AMPACHE';
}

sub playerMenu () {
  return 'RADIO';
}

sub metaProvider {
  my ( $client, $url ) = @_;
  my $icon = __PACKAGE__->_pluginDataFor('icon');
  my $song = ($ampache->getSongByURL($url))[0];

  if ( $song ) {
    # Metadata for currently playing song
    return {
      artist   => $song->{artist}->[0]->{content},
      album    => $song->{album}->[0]->{content},
      tracknum => $song->{track},
      title    => $song->{title},
      cover    => $song->{art},
      icon     => $icon,
      type     => string('PLUGIN_AMPACHE'),
    };
  }
}

1;

