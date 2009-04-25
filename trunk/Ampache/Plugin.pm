package Plugins::Ampache::Plugin;

use strict;

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Formats::RemoteMetadata;
use Slim::Formats::XML;

use Plugins::Ampache::Settings;
use Plugins::Ampache::Ampache;
use Plugins::Ampache::Browse;

use base qw(Slim::Plugin::OPMLBased);

my $prefs = preferences('plugin.ampache');

my $log = Slim::Utils::Log->addLogCategory({
  'category'     => 'plugin.ampache',
  'defaultLevel' => 'DEBUG',
});

my $ampache;

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

  $ampache = authenticate();

  Slim::Player::ProtocolHandlers->registerIconHandler(
      qr{/play/index\.php\?song=\d+},
      sub { return $class->_pluginDataFor('icon'); }
  );

  $class->SUPER::initPlugin(
      feed           => Plugins::Ampache::Browse::getTopLevelMenu($ampache),
      tag            => 'ampache',
      menu           => 'music_services',
      weight         => 50,
  );

  Slim::Formats::RemoteMetadata->registerProvider(
    match => qr{/play/index\.php\?song=\d+},
    func   => \&metaProvider,
  );

  if ( main::SLIM_SERVICE ) {
    my $menu = {
      useMode => sub { $class->setMode(@_) },
      header  => 'PLUGIN_AMPACHE',
    };

    Slim::Buttons::Home::addSubMenu(
        'MY_MUSIC',
        'PLUGIN_AMPACHE',
        $menu,
    );

    $class->initCLI(
        feed => Plugins::Ampache::Browse::getTopLevelMenu($ampache),
        tag  => 'ampache_my_music',
        menu => 'my_music',
    );
  }
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
      type     => 'PLUGIN_AMPACHE',
    };
  }
}

1;
