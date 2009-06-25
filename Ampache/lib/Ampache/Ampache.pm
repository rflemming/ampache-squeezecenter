package Ampache;

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
#
# PERL module for interacting with an Ampache server.  You can find more
# information about the XML API here: http://ampache.org/wiki/dev:xmlapi
# This module doesn't implement all of the functionality provided by the
# API, only the amount necessary to support the SqueezeCenter plugin.
#
#  $ampache = new Ampache();
#  $ampache->connect(
#    'http://www.example.com/server/xml.server.php',
#    'Pa$$w0rd',
#    'username',
#    35001,
#  );
#  foreach my $artist ($ampache->getArtists()) {
#    print "Artist: $artist->{name};
#  }

use strict;
use warnings;

use CGI;
use Digest::MD5 'md5_hex';
use Digest::SHA::PurePerl 'sha256_hex';
use LWP::Simple;
use XML::Simple;

# This is defined in the Ampache API
use constant LIMIT => 5000;

my $debug = 0;

# Write debugging messages to STDERR
sub _debug {
  my $msg = shift;
  if ($debug) {
    print STDERR "DEBUG: $msg\n";
  }
}

# Send a query to the server using the supplied action and hash of
# parameters, parse the resulting XML and return an array of hashes.
sub _getResponse {
  my $self = shift;

  my $action = shift;
  my $param= shift;

  die "No action specified\n" if (! $action);

  # If we are passed a reference process it as a hash of parameters,
  # otherwise assume it is a filter string by default
  my %params = ();
  if ($param) {
    if (ref($param)) {
      %params = %{$param};
    } else {
      $params{'filter'} = $param;
    }
  }

  # Add the action to the parameters
  $params{'action'} = $action;
  # Add the auth token to the parameters if it exists
  $params{'auth'} = $self->{auth} if ($self->{auth});

  # Formulate the query string for all defines options
  my $query = join('&',
      map {"$_=$params{$_}" if defined($params{$_})} keys %params);

  # Make the full URL be combining the URL and the query string
  my $url = $self->{url} . "?$query";

  # Grab the URL
  _debug("Getting: $url");
  my $content = get $url;
  die "Couldn't get $url\n" if (! $content);

  # Parse the response and make sure all major types are being returned
  # as an array
  my $reply = $self->{xml}->XMLin($content,
      forcearray => [
          'artist', 'album', 'playlist', 'genre', 'song', 'tag', 'video'],
  );

  # Handle the error case first in case we need to reconnect
  if ($reply->{error}) {
    $self->{error_code} = $reply->{error}->{code};
    $self->{error} = $reply->{error}->{content};
    _debug("Error($self->{error_code}): $self->{error}");

    # If we receive a session expired message and are configured to
    # reconnect, do so and try the query again
    if ($self->{error} eq 'Session Expired' && $self->{reconnect}) {
      _debug('Session timed out, reconnecting...');
      $self->connect();
      return $self->_getResponse($action, $param);
    } else {
      return;
    }
  } else {
    # Unset the error attributes
    $self->{error_code} = undef;
    $self->{error} = undef;

    # If only a single type of object exists in the reply return an array
    # of that object, otherwise return the reply as is.
    my @keys = keys %{$reply};
    my $num_keys = $#keys + 1;

    # No results
    if ($num_keys == 0) {
      return;
    # A single list of results
    } elsif ($num_keys == 1) {
      my $type = $keys[0];
      # Return objects of that type as an array
      my @xml = @{$reply->{$type}};
      my $num_items = $#xml + 1;
      # Have we reached the Ampache limit
      if ($num_items == LIMIT) {
        if ($self->{nolimit}) {
          # Increase the offset and get the next batch of results
          $self->{offset}++;
          # Update the offset in our query
          $params{'offset'} = $self->{offset} * LIMIT;
          # Remove 'action' since it'll be redudant otherwise
          delete $params{'action'};
          # Merge in the next batch of results
          @xml = (@xml, $self->_getResponse($action, \%params));
          # Increase the number of items
          $num_items = $#xml + 1;
          # Reset the offset now that we are done
          $self->{offset} = 0;
        } else {
          _debug("Reached limit of " . LIMIT . " items. " .
                 "Not all results may have been return");
        }
      }
      # Only log the number of results after all have been fetched
      if ($self->{offset} == 0) {
        _debug("Reply contains $num_items of type $type");
      }
      return @xml;
    # Mutliple types of results should only occur during authentication
    } else {
      return $reply;
    }
  }
}

sub new {
  my $self = {};

  # Store these in case we need to reconnect
  $self->{url} = undef;
  $self->{key} = undef;
  $self->{user} = undef;
  $self->{version} = 340001;

  # By default reconnect after a session times out
  $self->{reconnect} = 1;
  # By default override the default limit to return all results
  $self->{nolimit} = 1;
  # Used to track recursive queries that exceed LIMIT
  $self->{offset} = 0;

  # Use these to keep track of any errors which might occur
  $self->{error_code} = undef;
  $self->{error} = undef;

  # Initialize this here to avoid doing multiple times
  $self->{xml} = new XML::Simple (KeyAttr=>[]);

  bless($self);
  return $self;
}

sub connect {
  my $self = shift;
  my ($url, $key, $user, $version, $reconnect, $nolimit) = @_;

  # Unset the auth attribute in case this is a re-auth request
  $self->{auth} = undef;

  $self->{url} = $url if ($url);
  $self->{key} = $key if ($key);
  $self->{user} = $user if ($user);
  $self->{version} = $version if ($version);
  $self->{reconnect} = $reconnect if ($reconnect);
  $self->{nolimit} = $nolimit if ($nolimit);

  # Do some error checking on the supplied values
  if (! $self->{url} || ! $self->{key}) {
    die "No URL or key specified during connect\n";
  }

  if ($self->{url} !~ m#\Ahttps?://.*/server/xml\.server\.php\z#) {
    die "URL does not appear to be valid\n";
  }

  my $time = time();

  # The key is hashed differently in 3.4 and 3.5
  my $hash_func;
  if ($self->{version} == 340001) {
    $hash_func = \&md5_hex;
  } elsif ($self->{version} >= 350001) {
    $hash_func = \&sha256_hex;
    # This allows the user to use either a plain text key as in 3.4 or
    # an already hashed key which is only deceptively more secure.
    if ($self->{key} !~ m#\A[0-9A-Fa-f]{64}\z#) {
      $self->{key} = sha256_hex($self->{key});
    }
  }
  my $passphrase = $hash_func->($time . $self->{key});

  _debug("Connecting...");
  _debug("  url=$self->{url}");
  _debug("  key=$self->{key}");
  _debug("  version=$self->{version}");
  _debug("  user=$self->{user}") if ($self->{user});
  _debug("  time=$time");

  my %params = (
      'auth' => $passphrase,
      'timestamp' => $time,
  );
  $params{'user'} = $self->{user} if ($self->{user});
  $params{'version'} = $self->{version} if ($self->{version});

  my $reply = $self->_getResponse('handshake', \%params);

  if ($reply) {
    $self->{error_code} = undef;
    $self->{error} = undef;

    # Take the reply values and add them as instance attributes
    foreach my $key (keys %$reply) {
      $self->{$key} = $reply->{$key};
    }

    _debug("Authenticated: $self->{auth}");
  }
}

# Return error code and message as an array
sub error {
  my $self = shift;

  if ($self->{error_code} && $self->{error}) {
    return ($self->{error_code}, $self->{error});
  }
}

sub getArtists {
  my $self = shift;

  return $self->_getResponse('artists', shift);
}

sub getArtistsByGenre {
  my $self = shift;

  return $self->_getResponse('genre_artists', shift);
}

sub getArtistsByTag {
  my $self = shift;

  return $self->_getResponse('tag_artists', shift);
}

sub getAlbums {
  my $self = shift;

  return $self->_getResponse('albums', shift);
}

sub getAlbumsByArtist {
  my $self = shift;

  return $self->_getResponse('artist_albums', shift);
}

sub getAlbumsByGenre {
  my $self = shift;

  return $self->_getResponse('genre_albums', shift);
}

sub getAlbumsByTag {
  my $self = shift;

  return $self->_getResponse('tag_albums', shift);
}

sub getSong {
  my $self = shift;

  return ($self->_getResponse('song', shift))[0];
}

sub getSongByURL {
  my $self = shift;

  # The url must be encoded so that when it becomes part of the GET
  # request it can be properly parsed by the server
  return ($self->_getResponse('url_to_song', {'url' => CGI::escape(shift)}))[0];
}

sub getSongs {
  my $self = shift;

  return $self->_getResponse('songs', shift);
}

sub getSongsByAlbum {
  my $self = shift;

  return $self->_getResponse('album_songs', shift);
}

sub getSongsByArtist {
  my $self = shift;

  return $self->_getResponse('artist_songs', shift);
}

sub getSongsByGenre {
  my $self = shift;

  return $self->_getResponse('genre_songs', shift);
}

sub getSongsByTag {
  my $self = shift;

  return $self->_getResponse('tag_songs', shift);
}

sub getSongsByPlaylist {
  my $self = shift;

  return $self->_getResponse('playlist_songs', shift);
}

sub getSongsBySearch {
  my $self = shift;

  return $self->_getResponse('search_songs', shift);
}

sub getGenre {
  my $self = shift;

  return ($self->_getResponse('genre', shift))[0];
}

sub getGenres {
  my $self = shift;

  return $self->_getResponse('genres', shift);
}

sub getTag {
  my $self = shift;

  return ($self->_getResponse('tag', shift))[0];
}

sub getTags {
  my $self = shift;

  return $self->_getResponse('tags', shift);
}

sub getPlaylist {
  my $self = shift;

  return ($self->_getResponse('playlist', shift))[0];
}

sub getPlaylists {
  my $self = shift;

  return $self->_getResponse('playlists', shift);
}

1;
