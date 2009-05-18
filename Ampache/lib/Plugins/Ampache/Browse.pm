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

# We have one function for each type of object returned.  Since there
# are multiple ways to get an Artist, Album, or Song reference the
# function used is passed as one of the 'passthrough' arguments.

sub getAlbums {
  my $client = shift;
  my $callback = shift;
  my ($ampache, $function, $filter) = @_;

  my @albums;

  foreach my $album ($ampache->$function($filter)) {
    push @albums, {
      'name' => $album->{name},
      'type' => 'playlist',
      'url' => \&getSongs,
      'image' => $album->{art},
      'passthrough' => [
          $ampache,
          \&Plugins::Ampache::Ampache::getSongsByAlbum, $album->{id}
      ],
    };
  }

  if (@albums) {
    $log->debug('Found ' . ($#albums + 1) . ' album(s)');
    return $callback->(\@albums);
  } else {
    return $callback->(&Plugins::Ampache::Plugin::Error('No albums found'));
  }
}

sub getArtists {
  my $client = shift;
  my $callback = shift;
  my ($ampache, $function, $filter) = @_;

  my @artists;

  foreach my $artist ($ampache->$function($filter)) {
    push @artists, {
      'name' => $artist->{name},
      'type' => 'opml',
      'url' => \&getAlbums,
      'passthrough' => [
          $ampache,
          \&Plugins::Ampache::Ampache::getAlbumsByArtist, $artist->{id}
      ],
    };
  }

  if (@artists) {
    $log->debug('Found ' . ($#artists + 1) . ' artist(s)');
    return $callback->(\@artists);
  } else {
    return $callback->(&Plugins::Ampache::Plugin::Error('No artists found'));
  }
}

sub getGenres {
  my $client = shift;
  my $callback = shift;
  my ($ampache, $filter) = @_;

  my @genres;

  foreach my $genre ($ampache->getGenres($filter)) {
    # Since there are multiple ways to browse by Genre return a
    # sub-menu first.
    push @genres, {
        'title' => $genre->{name},
        'type' => 'opml',
        'items' => [
          {
            'name' => 'Albums By Genre',
            'type' => 'opml',
            'url' => \&getAlbums,
            'passthrough' => [
                $ampache,
                \&Plugins::Ampache::Ampache::getAlbumsByGenre, $genre->{id}
            ],
          },
          {
            'name' => 'Artists By Genre',
            'type' => 'opml',
            'url' => \&getArtists,
            'passthrough' => [
                $ampache,
                \&Plugins::Ampache::Ampache::getArtistsByGenre, $genre->{id}
            ],
          },
          {
            'name' => 'Songs By Genre',
            'type' => 'playlist',
            'url' => \&getSongs,
            'passthrough' => [
                $ampache,
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
    return $callback->(&Plugins::Ampache::Plugin::Error('No genres found'));
  }
}

sub getTags {
  my $client = shift;
  my $callback = shift;
  my ($ampache, $filter) = @_;

  my @tags;

  foreach my $tag ($ampache->getTags($filter)) {
    # Tags work the same was as Genres
    push @tags, {
        'title' => $tag->{name},
        'type' => 'opml',
        'items' => [
          {
            'name' => 'Albums By Tag',
            'type' => 'opml',
            'url' => \&getAlbums,
            'passthrough' => [
                $ampache,
                \&Plugins::Ampache::Ampache::getAlbumsByTag, $tag->{id}
            ],
          },
          {
            'name' => 'Artists By Tag',
            'type' => 'opml',
            'url' => \&getArtists,
            'passthrough' => [
                $ampache,
                \&Plugins::Ampache::Ampache::getArtistsByTag, $tag->{id}
            ],
          },
          {
            'name' => 'Songs By Tag',
            'type' => 'playlist',
            'url' => \&getSongs,
            'passthrough' => [
                $ampache,
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
    return $callback->(&Plugins::Ampache::Plugin::Error('No tags found'));
  }
}

sub getPlaylists {
  my $client = shift;
  my $callback = shift;
  my ($ampache, $filter) = @_;

  my @playlists;

  foreach my $playlist ($ampache->getPlaylists($filter)) {
    push @playlists, {
      'name' => $playlist->{name},
      'type' => 'playlist',
      'url' => \&getSongs,
      'passthrough' => [
          $ampache,
          \&Plugins::Ampache::Ampache::getSongsByPlaylist, $playlist->{id}
      ],
    };
  }

  if (@playlists) {
    $log->debug('Found ' . ($#playlists + 1) . ' playlist(s)');
    return $callback->(\@playlists);
  } else {
    return $callback->(&Plugins::Ampache::Plugin::Error('No playlists found'));
  }
}

sub getSongs {
  my $client = shift;
  my $callback = shift;
  my ($ampache, $method, $filter) = @_;

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
    return $callback->(&Plugins::Ampache::Plugin::Error('No songs found'));
  }
}

1;
