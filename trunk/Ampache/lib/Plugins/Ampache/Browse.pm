package Plugins::Ampache::Browse;

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

use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);

use Ampache::Ampache;

use base qw(Slim::Plugin::Base);

my $log = Slim::Utils::Log->addLogCategory({
  'category'     => 'plugin.ampache',
  'defaultLevel' => 'INFO',
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
          \&Ampache::getSongsByAlbum, $album->{id}
      ],
    };
  }

  if (@albums) {
    $log->debug('Found ' . ($#albums + 1) . ' album(s)');
    return $callback->(\@albums);
  } else {
    my $error = string('NO').' '.string('LCALBUMS').' '.string('FOUND');
    return $callback->(&Ampache::Plugin::Error($error));
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
          \&Ampache::getAlbumsByArtist, $artist->{id}
      ],
    };
  }

  if (@artists) {
    $log->debug('Found ' . ($#artists + 1) . ' artist(s)');
    return $callback->(\@artists);
  } else {
    my $error = string('NO').' '.string('LCARTISTS').' '.string('FOUND');
    return $callback->(&Plugins::Ampache::Plugin::Error($error));
  }
}

sub getGenres {
  my $client = shift;
  my $callback = shift;
  my ($ampache, $filter) = @_;

  my @genres;

  foreach my $genre ($ampache->getGenres($filter)) {
    # Since there are multiple ways to browse by Genre return a
    # sub-menu for each Genre.
    push @genres, {
        'title' => $genre->{name},
        'type' => 'opml',
        'items' => [
          {
            'name' => string('ALBUMS'),
            'type' => 'opml',
            'url' => \&getAlbums,
            'passthrough' => [
                $ampache,
                \&Ampache::getAlbumsByGenre, $genre->{id}
            ],
          },
          {
            'name' => string('ARTISTS'),
            'type' => 'opml',
            'url' => \&getArtists,
            'passthrough' => [
                $ampache,
                \&Ampache::getArtistsByGenre, $genre->{id}
            ],
          },
          {
            'name' => string('SONGS'),
            'type' => 'playlist',
            'url' => \&getSongs,
            'passthrough' => [
                $ampache,
                \&Ampache::getSongsByGenre, $genre->{id}
            ],
          },
        ],
    };
  }

  if (@genres) {
    $log->debug('Found ' . ($#genres + 1) . ' genre(s)');
    return $callback->(\@genres);
  } else {
    my $error = string('NO').' '.string('LCGENRES').' '.string('FOUND');
    return $callback->(&Plugins::Ampache::Plugin::Error($error));
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
            'name' => string('ALBUMS'),
            'type' => 'opml',
            'url' => \&getAlbums,
            'passthrough' => [
                $ampache,
                \&Ampache::getAlbumsByTag, $tag->{id}
            ],
          },
          {
            'name' => string('ARTISTS'),
            'type' => 'opml',
            'url' => \&getArtists,
            'passthrough' => [
                $ampache,
                \&Ampache::getArtistsByTag, $tag->{id}
            ],
          },
          {
            'name' => string('SONGS'),
            'type' => 'playlist',
            'url' => \&getSongs,
            'passthrough' => [
                $ampache,
                \&Ampache::getSongsByTag, $tag->{id}
            ],
          },
        ],
    };
  }

  if (@tags) {
    $log->debug('Found ' . ($#tags + 1) . ' tag(s)');
    return $callback->(\@tags);
  } else {
    my $error = string('NO').' '.string('LCTAGS').' '.string('FOUND');
    return $callback->(&Plugins::Ampache::Plugin::Error($error));
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
          \&Ampache::getSongsByPlaylist, $playlist->{id}
      ],
    };
  }

  if (@playlists) {
    $log->debug('Found ' . ($#playlists + 1) . ' playlist(s)');
    return $callback->(\@playlists);
  } else {
    my $error = string('NO').' '.string('LCPLAYLISTS').' '.string('FOUND');
    return $callback->(&Plugins::Ampache::Plugin::Error($error));
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
    my $error = string('NO').' '.string('LCSONGS').' '.string('FOUND');
    return $callback->(&Plugins::Ampache::Plugin::Error($error));
  }
}

1;
