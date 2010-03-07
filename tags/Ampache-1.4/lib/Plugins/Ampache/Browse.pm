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

my $log   = logger('plugin.ampache');

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
    if ($log->is_debug) {
      $log->debug('Found ' . ($#albums + 1) . ' album(s)');
    }
    return $callback->(\@albums);
  } else {
    my $error = string('NO').' '.string('LCALBUMS').' '.string('FOUND');
    return $callback->(&Plugins::Ampache::Plugin::Error($error));
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
    if ($log->is_debug) {
      $log->debug('Found ' . ($#artists + 1) . ' artist(s)');
    }
    return $callback->(\@artists);
  } else {
    my $error = string('NO').' '.string('LCARTISTS').' '.string('FOUND');
    return $callback->(&Plugins::Ampache::Plugin::Error($error));
  }
}

# Tags and genre are essentially the same for now aside from how they
# are called.  So we can process both with the same function so long
# as we use the appropriate function for fetching results from the
# server
sub getGenresTags {
  my $client = shift;
  my $callback = shift;
  my ($ampache, $filter) = @_;

  my @items;

  # Function mappings defining the difference between genres and tags
  my %funcs;
  if ($ampache->{version} == 340001) {
    %funcs = (
      items   => \&Ampache::getGenres,
      albums  => \&Ampache::getAlbumsByGenre,
      artists => \&Ampache::getArtistsByGenre,
      songs   => \&Ampache::getSongsByGenre,
    );
  } elsif ($ampache->{version} >= 350001) {
    %funcs = (
      items   => \&Ampache::getTags,
      albums  => \&Ampache::getAlbumsByTag,
      artists => \&Ampache::getArtistsByTag,
      songs   => \&Ampache::getSongsByTag,
    );
  }

  my $function = $funcs{items};

  foreach my $item ($ampache->$function($filter)) {
    push @items, {
        'title' => $item->{name},
        'type' => 'opml',
        'items' => [
          {
            'name' => string('ALBUMS'),
            'type' => 'opml',
            'url' => \&getAlbums,
            'passthrough' => [
                $ampache,
                $funcs{albums}, $item->{id}
            ],
          },
          {
            'name' => string('ARTISTS'),
            'type' => 'opml',
            'url' => \&getArtists,
            'passthrough' => [
                $ampache,
                $funcs{artists}, $item->{id}
            ],
          },
          {
            'name' => string('SONGS'),
            'type' => 'playlist',
            'url' => \&getSongs,
            'passthrough' => [
                $ampache,
                $funcs{songs}, $item->{id}
            ],
          },
        ],
    };
  }

  if (@items) {
    if ($log->is_debug) {
      $log->debug('Found ' . ($#items + 1) . ' genre/tag(s)');
    }
    return $callback->(\@items);
  } else {
    my $error = string('NO').' '.string('LCGENRES').'/'.
        string('LCTAGS').' '.string('FOUND');
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
    if ($log->is_debug) {
      $log->debug('Found ' . ($#playlists + 1) . ' playlist(s)');
    }
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
    if ($log->is_debug) {
      $log->debug('Found ' . ($#songs + 1) . ' song(s)');
    }
    return $callback->(\@songs);
  } else {
    my $error = string('NO').' '.string('LCSONGS').' '.string('FOUND');
    return $callback->(&Plugins::Ampache::Plugin::Error($error));
  }
}

1;
