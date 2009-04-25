package Plugins::Ampache::Browse;

use strict;
use warnings;

use Plugins::Ampache::Ampache;
use Slim::Utils::Log;

use base qw(Slim::Plugin::Base);

my $log = Slim::Utils::Log->addLogCategory({
  'category'     => 'plugin.ampache',
  'defaultLevel' => 'DEBUG',
});

my $ampache;

sub getTopLevelMenu {
  $ampache = shift;

  my @items;
  # If there was a login error we'll catch it here, otherwise return the
  # main menu
  if ($ampache->error()) {
    @items = (&Error());
  } else {
    @items = (
      {
        'name' => 'Albums',
        'type' => 'opml',
        'url' => \&getAlbums,
        'passthrough' => [\&Plugins::Ampache::Ampache::getAlbums],
      },
      {
        'name' => 'Artists',
        'type' => 'opml',
        'url' => \&getArtists,
        'passthrough' => [\&Plugins::Ampache::Ampache::getArtists],
      },
      {
        'name' => 'Genres',
        'type' => 'opml',
        'url' => \&getGenres,
      },
      {
        'name' => 'Playlists',
        'type' => 'opml',
        'url' => \&getPlaylists,
      },
    );

    if (int($ampache->{version}) >= 350001) {
      push @items, {
        'name' => 'Tags',
        'type' => 'opml',
        'url' => \&getTags,
      };
    }
  }

  my $feed = {
    'title' => 'Ampache',
    'type' => 'opml',
    'nocache' => 1,
    'items' => \@items,
  };

  return $feed;
}

sub getAlbums {
  my $client = shift;
  my $callback = shift;
  my ($function, $filter) = @_;

  my @albums;

  foreach my $album ($ampache->$function($filter)) {
    push @albums, {
      'name' => $album->{name},
      'type' => 'playlist',
      'url' => \&getSongs,
      'image' => $album->{art},
      'passthrough' => [
          \&Plugins::Ampache::Ampache::getSongsByAlbum, $album->{id}
      ],
    };
  }

  if (@albums) {
    $log->debug('Found ' . ($#albums + 1) . ' album(s)');
    return $callback->(\@albums);
  } else {
    return $callback->(&Error('No albums found'));
  }
}

sub getArtists {
  my $client = shift;
  my $callback = shift;
  my ($function, $filter) = @_;

  my @artists;

  foreach my $artist ($ampache->$function($filter)) {
    push @artists, {
      'name' => $artist->{name},
      'type' => 'opml',
      'url' => \&getAlbums,
      'passthrough' => [
          \&Plugins::Ampache::Ampache::getAlbumsByArtist, $artist->{id}
      ],
    };
  }

  if (@artists) {
    $log->debug('Found ' . ($#artists + 1) . ' artist(s)');
    return $callback->(\@artists);
  } else {
    return $callback->(&Error('No artists found'));
  }
}

sub getGenres {
  my $client = shift;
  my $callback = shift;
  my $filter = shift;

  my @genres;

  foreach my $genre ($ampache->getGenres($filter)) {
    push @genres, {
        'title' => $genre->{name},
        'type' => 'opml',
        'items' => [
          {
            'name' => 'Albums By Genre',
            'type' => 'opml',
            'url' => \&getAlbums,
            'passthrough' => [
                \&Plugins::Ampache::Ampache::getAlbumsByGenre, $genre->{id}
            ],
          },
          {
            'name' => 'Artists By Genre',
            'type' => 'opml',
            'url' => \&getArtists,
            'passthrough' => [
                \&Plugins::Ampache::Ampache::getArtistsByGenre, $genre->{id}
            ],
          },
          {
            'name' => 'Songs By Genre',
            'type' => 'playlist',
            'url' => \&getSongs,
            'passthrough' => [
                \&Plugins::Ampache::Ampache::getSongsByGenre, $genre->{id}
            ],
          },
        ],
    };
  }

  if (@genres) {
    $log->debug('Found ' . ($#genres + 1) . ' genre(s)');
    return $callback->(\@genres);
  } else {
    return $callback->(&Error('No genres found'));
  }
}

sub getTags {
  my $client = shift;
  my $callback = shift;
  my $filter = shift;

  my @tags;

  foreach my $tag ($ampache->getTags($filter)) {
    push @tags, {
        'title' => $tag->{name},
        'type' => 'opml',
        'items' => [
          {
            'name' => 'Albums By Tag',
            'type' => 'opml',
            'url' => \&getAlbums,
            'passthrough' => [
                \&Plugins::Ampache::Ampache::getAlbumsByTag, $tag->{id}
            ],
          },
          {
            'name' => 'Artists By Tag',
            'type' => 'opml',
            'url' => \&getArtists,
            'passthrough' => [
                \&Plugins::Ampache::Ampache::getArtistsByTag, $tag->{id}
            ],
          },
          {
            'name' => 'Songs By Tag',
            'type' => 'playlist',
            'url' => \&getSongs,
            'passthrough' => [
                \&Plugins::Ampache::Ampache::getSongsByTag, $tag->{id}
            ],
          },
        ],
    };
  }

  if (@tags) {
    $log->debug('Found ' . ($#tags + 1) . ' tag(s)');
    return $callback->(\@tags);
  } else {
    return $callback->(&Error('No tags found'));
  }
}

sub getPlaylists {
  my $client = shift;
  my $callback = shift;
  my $filter = shift;

  my @playlists;

  foreach my $playlist ($ampache->getPlaylists($filter)) {
    push @playlists, {
      'name' => $playlist->{name},
      'type' => 'playlist',
      'url' => \&getSongs,
      'passthrough' => [
          \&Plugins::Ampache::Ampache::getSongsByPlaylist, $playlist->{id}
      ],
    };
  }

  if (@playlists) {
    $log->debug('Found ' . ($#playlists + 1) . ' playlist(s)');
    return $callback->(\@playlists);
  } else {
    return $callback->(&Error('No playlists found'));
  }
}

sub getSongs {
  my $client = shift;
  my $callback = shift;
  my ($method, $filter) = @_;

  my @songs;

  foreach my $song($ampache->$method($filter)) {
    push @songs, {
      'name' => $song->{title},
      'type' => 'audio',
      'duration' => $song->{time},
      'mime' => 'audio/mpeg',
      'url' => $song->{url},
      };
  }

  if (@songs) {
    $log->debug('Found ' . ($#songs + 1) . ' song(s)');
    return $callback->(\@songs);
  } else {
    return $callback->(&Error('No songs found'));
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

1;
