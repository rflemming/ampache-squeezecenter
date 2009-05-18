package Plugins::Ampache::Plugin;

use strict;

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);

use Slim::Formats::RemoteMetadata;
use Slim::Formats::XML;

use Plugins::Ampache::Ampache;
use Plugins::Ampache::Browse;
use Plugins::Ampache::Settings;

use base qw(Slim::Plugin::OPMLBased);

my $prefs = preferences('plugin.ampache');

my $log = Slim::Utils::Log->addLogCategory({
  'category'     => 'plugin.ampache',
  'defaultLevel' => 'DEBUG',
});

# Store an Ampache::Ampache instance for easy access
my $ampache;

# Login to the server, if it fails log a message.  It will also be
# displayed via feed()
sub authenticate {
  my $version = $prefs->get('plugin_ampache_version');
  my $key = $prefs->get('plugin_ampache_key');
  if ($version eq "3.4") {
    $version = 340001;
  } elsif ($version eq "3.5") {
    $version = 350001;
    # 3.5 uses the user's password rather than a key
    $key = $prefs->get('plugin_ampache_password');
  }

  $log->debug('Authenticating...');
  my $ampache = Plugins::Ampache::Ampache->new();
  $ampache->connect(
    $prefs->get('plugin_ampache_server'),
    $key,
    $prefs->get('plugin_ampache_username'),
    $version,
  );

  if ($ampache->{error_code}) {
    $log->info("Login failed ($ampache->{error_code}): $ampache->{error}");
  } else {
    $log->debug("Logged in with token: $ampache->{auth}");
  }

  return $ampache;
}

sub initPlugin {
  my $class = shift;

  Plugins::Ampache::Settings->new;

  Slim::Player::ProtocolHandlers->registerIconHandler(
      qr{/play/index\.php\?(.+)},
      sub { return $class->_pluginDataFor('icon'); }
  );

  $class->SUPER::initPlugin(
      tag            => 'ampache',
      menu           => 'music_services',
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
        'MY_MUSIC',
        'PLUGIN_AMPACHE',
        $menu,
    );

    $class->initCLI(
        tag  => 'ampache_my_music',
        menu => 'my_music',
    );
  }
}

sub feed {
  my $class = shift;

  # Login if we haven't yet done so
  if (! $ampache) {
    $ampache = authenticate();
  }

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
        'name' => 'Albums',
        'type' => 'opml',
        'url' => \&Plugins::Ampache::Browse::getAlbums,
        'passthrough' => [$ampache, \&Plugins::Ampache::Ampache::getAlbums],
      },
      {
        'name' => 'Artists',
        'type' => 'opml',
        'url' => \&Plugins::Ampache::Browse::getArtists,
        'passthrough' => [$ampache, \&Plugins::Ampache::Ampache::getArtists],
      },
      {
        'name' => 'Playlists',
        'type' => 'opml',
        'url' => \&Plugins::Ampache::Browse::getPlaylists,
        'passthrough' => [$ampache], # No function since there is only
                                     # one way to fetch Playlist objects.
      },
    );

    # 3.5 has tags, 3.4 only genres
    if (int($ampache->{version}) >= 350001) {
      push @items, {
        'name' => 'Tags',
        'type' => 'opml',
        'url' => \&Plugins::Ampache::Browse::getTags,
        'passthrough' => [$ampache], # No function due to sub-menu
      };
    } else {
      push @items, {
        'name' => 'Genres',
        'type' => 'opml',
        'url' => \&Plugins::Ampache::Browse::getGenres,
        'passthrough' => [$ampache], # Same as tags
      };
    }
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
  return 'MUSIC_SERVICES';
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

