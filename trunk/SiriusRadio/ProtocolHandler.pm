package Plugins::SiriusRadio::ProtocolHandler;

# $Id$

# SlimServer Copyright (c) 2001-2004 Vidur Apparao, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use base qw(Slim::Player::Protocols::MMS);

#use Scalar::Util qw(blessed);
use Slim::Music::Info;
use Slim::Player::Playlist;
#use Slim::Formats::Parse;
use Slim::Player::Source;
use Slim::Utils::Log;
use Slim::Utils::Misc;
#use Slim::Utils::Strings qw (string);

my $log = logger('plugin.siriusradio');


sub audioScrobblerSource { 'R' }

sub getFormatForURL { 'wma' }

sub isAudioURL { 1 }

sub isRemote { 1 }

# Support transcoding
sub new {
	my $class = shift;
	my $args  = shift;

	my $url    = $args->{'song'}->{'streamUrl'};
	
	return unless $url;
	
	$args->{'url'} = $url;

	return $class->SUPER::new($args);
}


sub getNextTrack {
	my ($class, $song, $successCb, $errorCb) = @_;
	
	my ($channelId) = $song->currentTrack()->url =~ m{^siriusradio://(\d+)};
	my $client = $song->master();
	my $channelRef = Plugins::SiriusRadio::Plugin::channelLookup($channelId);
	Plugins::SiriusRadio::Plugin::getHashKey($client, $channelRef, 'callback', $successCb, $song);
}

sub parseMetadata {
	my ( $class, $client, $song, $metadata ) = @_;
	
	# If we have ASF_Command_Media, process it here, otherwise let parent handle it
	my $guid;
	map { $guid .= $_ } unpack( 'H*', substr $metadata, 0, 16 );
	
	if ( $guid ne '59dacfc059e611d0a3ac00a0c90348f6' ) { # ASF_Command_Media
		return $class->SUPER::parseMetadata( $client, $song, $metadata );
	}
		
	# Format of the metadata stream is:
	# TITLE <title>|ARTIST <artist>\0
	
	# WMA text is in UTF-16, if we can't decode it, just wait for more data
	# Cut off first 24 bytes (16 bytes GUID and 8 bytes object_size)
	$metadata = eval { Encode::decode('UTF-16LE', substr( $metadata, 24 ) ) } || return;
	
	#$log->debug( "ASF_Command_Media: $metadata" );
	
	my ($artist, $title);
	
	if ( $metadata =~ /TITLE\s+([^|]+)/ ) {
		$title = $1;
	}
	
	if ( $metadata =~ /ARTIST\s([^\0]+)/ ) {
		$artist = $1;
	}
	
	if ( $artist || $title ) {
		if ( $artist && $artist ne $title ) {
			$title = "$artist - $title";
		}
		
		Slim::Music::Info::setDelayedTitle( $song->master(),  $song->currentTrack()->url, $title );
	}
	
	return;
}

sub canDirectStreamSong {
	my ( $class, $client, $song ) = @_;
	
	return $class->SUPER::canDirectStream($client, $song->{'streamUrl'}, $class->getFormatForURL());
}

sub parseDirectHeaders {
	my $class   = shift;
	my $client  = shift || return;
	my $url     = shift;
	my @headers = @_;
	
	my $contentType = 'wma';

	# title, bitrate, metaint, redir, type, length, body
#	return (undef, $bitrate, 0, undef, $contentType, undef, undef);
	return (undef, undef, 0, undef, $contentType, undef, undef);

}

# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url ) = @_;
	my ($artist, $title);
	# Return artist and title if the metadata looks like Artist - Title
	if ( my $currentTitle = Slim::Music::Info::getCurrentTitle( $client, $url ) ) {
		my @dashes = $currentTitle =~ /( - )/g;
		if ( scalar @dashes == 1 ) {
			($artist, $title) = split / - /, $currentTitle;
		}
		else {
			$title = $currentTitle;
		}
	}
	
	my $logo;	
	if ($url =~ /siriusradio:\/\/(\d+)/) {
		#Would be nice to add some logic to check if a file actually exists and default to Sirius logo if not...
		$logo = 'plugins/SiriusRadio/html/images/'.$1.'.gif';
 	}
	
	return {
		artist  => $artist,
		title   => $title,
		cover   => $logo,
#		bitrate => $bitrate . 'k CBR',
		type    => 'WMA (Sirius)',
	};
}

sub getIcon {
	my ( $class, $url, $client ) = @_;

	return 'plugins/SiriusRadio/html/images/sirius5.png';
}

sub stopStreaming {
	my ( $song, $string ) = @_;
	
	my $client     = $song->master();
	
	# Change the stream title to the error message
	#Slim::Music::Info::setCurrentTitle( $song->currentTrack()->url, $client->string($string) );
	
	$client->update();
	
	# Kill all timers
	#Slim::Utils::Timers::killTimers( $song, \&pollStatus );
	#Slim::Utils::Timers::killTimers( $song, \&checkActivity );
	
	$client->execute( [ 'stop' ] );
}

1;
