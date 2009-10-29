package Plugins::SiriusRadio::Plugin;

# SiriusRadio plugin.pm by Greg Brown Feb 2006
#	Copyright (c) 2006 
#	All rights reserved.
#
# FEEDBACK
# Please direct all feedback to GoCubs on the Slim Devices public forums at forums.slimdevices.com
#
#	This program is free software; you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation; either version 2 of the License, or
#	(at your option) any later version.
#
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with this program; if not, write to the Free Software
#	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
#	02111-1307 USA
#
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
#use warnings;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw (string);
use Slim::Networking::SimpleAsyncHTTP;
use Digest::MD5 qw(md5_hex);
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Plugins::SiriusRadio::Settings;
use base qw(Slim::Plugin::Base);
use Slim::Utils::Prefs;

use File::Spec::Functions qw(:ALL);
use Data::Dumper;

use vars qw($VERSION);

my $prefs = preferences('plugin.siriusradio');

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.siriusradio',
#	'defaultLevel' => 'INFO',
	'defaultLevel' => 'WARN',
#	'defaultLevel' => 'DEBUG',
	'description'  => getDisplayName(),
});

$VERSION = substr(q$Revision: 1.5.0b1 $,11);

my $cookie = $prefs->get('plugin_siriusradio_cookie');
my $token = $prefs->get('plugin_siriusradio_token');
my $tokenTime = $prefs->get('plugin_siriusradio_tokenTime');

my $loggedIn = 0;
if ($token ne '') {
	$loggedIn = 1;
}

#Do they even care anymore!?!?
$loggedIn = 1;

my $lastInteraction = 0; #Last time a user had some interaction with the plugin

my $dataRequests = 0; #Number of data requests waiting to be returned for channel info

my %selectedChannel; #Hash that keep track of the selected channel (if any) index
my %nowPlaying; #Hash containing the current URL that is playing
my %nowPlayingRef; #Channel ref number of what is now playing
my %channelNumLoc; #Hash containing the Sirius channel number and its internal array location
my %nowPlayingTime; #Hash of how long a stream has been playing updated with each getTitle refresh

#Message to show at top of web page
my %webMessage;

#Interval to refresh the web client when there's a web message to display
my %webRefresh;

my $errorCount = 0;

#Arrays for storing channel data
my @channels;
my @channelNum;
my @channelName;
my @channelRef;
my @channelDesc;
my @categoryName;
my @categoryRef;
my @genreName;
my @genreRef;
my @streamURL;
my @songName;

my $channelsRef = \@channels;
$channels[0] =\@channelNum;
$channels[1] =\@channelName;
$channels[2] =\@channelRef;
$channels[3] =\@channelDesc;
$channels[4] =\@categoryName;
$channels[5] =\@categoryRef;
$channels[6] =\@genreName;
$channels[7] =\@genreRef;
$channels[8] =\@streamURL; #Is this needed/used anymore???
$channels[9] =\@songName;

#Arrays used to sequentially retrieve channel data
my @CDgetGenre1;
my @CDgetGenre2;

my @CDcategoryName;
my @CDcategoryRef;
my @CDgenreName;
my @CDgenreRef;

my $totalStations = 0; #Total number of stations found

my $cli_next;

our %current = ();

sub getDisplayName {
	return 'PLUGIN_SIRIUSRADIO';
}

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin();
	$log->info("Initializing...");
	
	Plugins::SiriusRadio::Settings->new;

	#Slim::Player::ProtocolHandlers->registerHandler('siriusradio', 'Plugins::SiriusRadio::ProtocolHandler');
	Slim::Player::ProtocolHandlers->registerHandler(
		siriusradio => 'Plugins::SiriusRadio::ProtocolHandler'
	);

	#Make sure there is a data placeholder for presets.  Otherwise for some reason slimserver wont create one on its own.  Already fixed in 6.5?
	my @presets;
	@presets = @{ $prefs->get('plugin_siriusradio_presets') || [] };
	if (scalar(@presets) == 0) {
		$prefs->set('plugin_siriusradio_presets', \@presets);
	}
	
	#Set default location if it's not set
	if ($prefs->get('plugin_siriusradio_location') eq '') {
		$prefs->set('plugin_siriusradio_location', 0);
	}	

	setCookies();
		
	$cli_next=Slim::Control::Request::addDispatch(['radios', '_index', '_quantity' ],[0, 1, 1, \&cliRadiosQuery]);
#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F
	Slim::Control::Request::addDispatch(['siriuspresets'],[1, 1, 0, \&siriusPresetsMenu]);
	Slim::Control::Request::addDispatch(['siriusCommon','_showNum', '_showPlaying', '_showIcon', '_arrayLoc'],[1, 1, 0, \&siriusCommon]);
	Slim::Control::Request::addDispatch(['siriusTopMenu'],[1, 1, 0, \&siriusTopMenu]);
	Slim::Control::Request::addDispatch(['siriusPlayChannel', '_channelNum'],[1, 0, 0, \&playChannel]);
	Slim::Control::Request::addDispatch(['siriusAddPreset', '_channelNum', '_mode'],[1, 0, 0, \&addPreset]);
	Slim::Control::Request::addDispatch(['siriusDetail','_channelNum'],[1, 1, 0, \&siriusDetail]);
	Slim::Control::Request::addDispatch(['siriusGenres'],[1, 1, 0, \&siriusGenres]);
	Slim::Control::Request::addDispatch(['siriusByGenre','_genreID'],[1, 1, 0, \&siriusByGenre]);
	
}

sub setCookies {
	$log->info("Resetting Sirius cookies.");
	
	my $cookie_jar = Slim::Networking::Async::HTTP::cookie_jar();
	$cookie_jar->set_cookie(0, 'pp_coupon_code','200','/','www.sirius.com',undef,1,undef,undef,0,{});
	$cookie_jar->set_cookie(0, 'sirius_campain_code',undef,'/','www.sirius.com',undef,1,undef,undef,0,{});
	$cookie_jar->set_cookie(0, 'sirius_promocode',undef,'/','www.sirius.com',undef,1,undef,undef,0,{});		
	$cookie_jar->set_cookie(0, 'sirius_login_type','subscriber','/','www.sirius.com',undef,1,undef,undef,0,{});		
	
	my $username = $prefs->get('plugin_siriusradio_username');
	$cookie_jar->set_cookie(0, 'sirius_user_name',$username,'/','www.sirius.com',undef,1,undef,undef,0,{});		

	$cookie_jar->set_cookie(0, 'sirius_mp_playertype','0','/','www.sirius.com',undef,1,undef,undef,0,{});		
	$cookie_jar->set_cookie(0, 'sirius_mp_pw',getPassword(),'/','www.sirius.com',undef,1,undef,undef,0,{});		

	if($prefs->get('plugin_siriusradio_bitrate') == 1) { #High bandwidth?
		$cookie_jar->set_cookie(0, 'sirius_mp_bitrate_button_status_cookie','high','/','www.sirius.com',undef,1,undef,undef,0,{});		
		$cookie_jar->set_cookie(0, 'sirius_mp_bitrate_entitlement_cookie','highbandwidth','/','www.sirius.com',undef,1,undef,undef,0,{});
	}

	my $test = $cookie_jar->as_string();
	$log->debug("CACHED COOKIES:$test");	
}

sub siriusPresetsMenu {
	my $request = shift;
	my $client = $request->client();
	
	lastInteractionUpdate($client);

	my @presets = ();
	my @menu = ();
	
	if ($totalStations == 0 && $dataRequests == 0 && $webMessage{$client} ne 'Retrieving channel data...') {
		$webMessage{$client}='Retrieving channel data...';
		$webRefresh{$client} = 2;

		getCategories($client);
	}
	elsif ($webMessage{$client} ne 'Retrieving channel data...') {
		@presets = @{ $prefs->get('plugin_siriusradio_presets') || [] };	
	
		my $i=0;
		while ($i <@presets) {
			push @menu, {
				#'icon-id' => "plugins/SiriusRadio/html/images/$presets[$i]_56x56_p.gif",
				'icon-id' => "plugins/SiriusRadio/html/images/$presets[$i]_56x56_p.gif",
				text => $channels[0][$channelNumLoc{$presets[$i]}].'. '. $channels[1][$channelNumLoc{$presets[$i]}]."\n".$channels[9][$channelNumLoc{$presets[$i]}],
   	      actions  => {
   	        go  => {
   	            player => 0,
   	            cmd    => [ 'siriusDetail', $presets[$i] ],
   	            params => {
   	            	menu => 'nowhere',
   	            },
   	        },
   	        play  => {
   	            player => 0,
   	            cmd    => [ 'siriusPlayChannel', $presets[$i] ],
   	            params => {
   	            	menu => 'nowhere',
   	            }
   	        }           
   	      },
			};
				
			$i++;
		}
	}
	else {
		push @menu, {
			#'icon-id' => "plugins/SiriusRadio/html/images/$presets[$i]_56x56_p.gif",
			text => "Retrieving channel data...\nPlease try again.",
				};	
	}
	
	my $numitems = scalar(@menu);
	
	$request->addResult("base", {window => { titleStyle => 'album' }});	
	$request->addResult("count", $numitems);
	$request->addResult("offset", 0);
	my $cnt = 0;
	for my $eachPreset (@menu[0..$#menu]) {
		$request->setResultLoopHash('item_loop', $cnt, $eachPreset);
		$cnt++;
	}
	
	$request->setStatusDone();
}

sub siriusGenres {
	my $request = shift;
	my $client = $request->client();
	my @menu = ();
	
	lastInteractionUpdate($client);

	if ($totalStations == 0 && $dataRequests == 0 && $webMessage{$client} ne 'Retrieving channel data...') {
		$webMessage{$client}='Retrieving channel data...';
		$webRefresh{$client} = 2;

		getCategories($client);
	}
	elsif ($webMessage{$client} ne 'Retrieving channel data...') {
		my %channelGenreListHash = ();
		my $i=0;
		while ($i <$totalStations) {
			if ($channels[4][$i] eq 'MUSIC') {
				$channelGenreListHash{$channels[6][$i]} = $channels[7][$i];	
			}
					
			$i++;
		}
			
		#Manually add genres
		$channelGenreListHash{'Howard Stern'} = 'specials';
		$channelGenreListHash{'News'} = 'catnews';
		$channelGenreListHash{'Comedy'} = 'comedy';
		$channelGenreListHash{'Sports'} = 'sports';
		$channelGenreListHash{'Family & Health'} = 'catfamilykid';
		$channelGenreListHash{'Talk/Entertainment'} = 'cattalk';
	
		my @sorted = sort keys %channelGenreListHash;

	
		$i=0;
		while ($i <@sorted) {
			push @menu, {
				text => $sorted[$i],
	         actions  => {
	           go  => {
	               player => 0,
	               cmd    => [ 'siriusByGenre', $channelGenreListHash{$sorted[$i]} ],
	               params => {
	               	menu => 'nowhere',
	               },
	           },
	         },
			};
				
			$i++;
		}
	}
	else {
		push @menu, {
			#'icon-id' => "plugins/SiriusRadio/html/images/$presets[$i]_56x56_p.gif",
			text => "Retrieving channel data...\nPlease try again.",
				};	
	}
	
	my $numitems = scalar(@menu);
	
	$request->addResult("count", $numitems);
	$request->addResult("offset", 0);
	my $cnt = 0;
	for my $eachGenreMenu (@menu[0..$#menu]) {
		#$log->debug(Dumper($eachGenreMenu));
		$request->setResultLoopHash('item_loop', $cnt, $eachGenreMenu);
		$cnt++;
	}
	$request->setStatusDone();
}

sub siriusByGenre {
	my $request = shift;
	my $client = $request->client();
	my $genreID = $request->getParam('_genreID');

	lastInteractionUpdate($client);

	if ($totalStations == 0 && $dataRequests == 0 && $webMessage{$client} ne 'Retrieving channel data...') {
		$webMessage{$client}='Retrieving channel data...';
		$webRefresh{$client} = 2;

		getCategories($client);
	}

	my %channelGenreHash = ();
		
		my $i=0;
		while ($i <$totalStations) {
			if ($channels[7][$i] eq $genreID) { 
				$channelGenreHash{$channels[1][$i]} = $i;
			}
			elsif ($genreID eq 'specials' && $channels[4][$i] eq 'HOWARD STERN') {
				$channelGenreHash{$channels[1][$i]} = $i;
			}
			elsif ($genreID eq 'catnews' && $channels[4][$i] eq 'NEWS') {
				$channelGenreHash{$channels[1][$i]} = $i;
			}
			elsif ($genreID eq 'comedy' && $channels[4][$i] eq 'COMEDY') {
				$channelGenreHash{$channels[1][$i]} = $i;
			}
			elsif ($genreID eq 'sports' && $channels[4][$i] eq 'SPORTS') {
				$channelGenreHash{$channels[1][$i]} = $i;
			}					
			elsif ($genreID eq 'catfamilykid' && $channels[4][$i] eq 'FAMILY & HEALTH') {
				$channelGenreHash{$channels[1][$i]} = $i;
			}										
			elsif ($genreID eq 'cattalk' && $channels[4][$i] eq 'TALK/ENT') {
				$channelGenreHash{$channels[1][$i]} = $i;
			}															
			$i++;
		}

	my @sorted = sort keys %channelGenreHash;
	
	my @menu = ();
	
	my $i=0;
	while ($i <@sorted) {
		push @menu, {
			text => $sorted[$i],
         actions  => {
           go  => {
               player => 0,
               cmd    => [ 'siriusDetail', $channels[0][$channelGenreHash{$sorted[$i]}] ],
               params => {
               	menu => 'nowhere',
               },
           },
           play  => {
               player => 0,
               cmd    => [ 'siriusPlayChannel',  $channels[0][$channelGenreHash{$sorted[$i]}] ],
               params => {
               	menu => 'nowhere',
               }
           }           
         },
		};
				
		$i++;
	}
	
	my $numitems = scalar(@menu);
	
	$request->addResult("count", $numitems);
	$request->addResult("offset", 0);
	my $cnt = 0;
	for my $eachGenreMenu (@menu[0..$#menu]) {
		#$log->debug(Dumper($eachGenreMenu));
		$request->setResultLoopHash('item_loop', $cnt, $eachGenreMenu);
		$cnt++;
	}
	$request->setStatusDone();
}

sub siriusCommon {
	my $request = shift;
	my $client = $request->client();
	my $showNum = $request->getParam('_showNum'); #Append channel number
	my $showPlaying = $request->getParam('_showPlaying'); #Append now playing
	my $showIcon = $request->getParam('_showIcon'); #Include channel icon
	
	my $arrayLoc = $request->getParam('_arrayLoc'); #What array location of info to display
	my @menu = ();
	
	lastInteractionUpdate($client);

	if ($totalStations == 0 && $dataRequests == 0 && $webMessage{$client} ne 'Retrieving channel data...') {
		$webMessage{$client}='Retrieving channel data...';
		$webRefresh{$client} = 2;

		getCategories($client);
	}
	elsif ($webMessage{$client} ne 'Retrieving channel data...') {
		my %channelHash = ();
			my $i=0;
			my $nowPlaying = '';
	
			while ($i <$totalStations) {
				if ($showPlaying == 1) {
					$nowPlaying = "\n" . $channels[9][$i];
				}
							
				if ($showNum == 1) {
					$channelHash{$channels[0][$i].'. '. $channels[$arrayLoc][$i].$nowPlaying} = $channels[0][$i];
				}
				else {
					$channelHash{$channels[$arrayLoc][$i].$nowPlaying} = $channels[0][$i];
				}
			$i++;
		}
	
		my @sorted;
		if ($showNum == 1) {			
			@sorted = sort by_number keys %channelHash;
		}
		else {
			@sorted = sort keys %channelHash;
		}
			
		my $i=0;
		while ($i <@sorted) {
			if ($showIcon == 0) { #I'm sure there's a more elegant way to do this... but I'm feeling lazy
				push @menu, {
					text => $sorted[$i],
	      	   actions  => {
	      	     go  => {
	      	         player => 0,
	      	         cmd    => [ 'siriusDetail', $channelHash{$sorted[$i]} ],
	      	         params => {
	      	         	menu => 'nowhere',
	      	         },
	      	     },
	      	     play  => {
	      	         player => 0,
	      	         cmd    => [ 'siriusPlayChannel', $channelHash{$sorted[$i]} ],
	      	         params => {
	      	         	menu => 'nowhere',
	      	         }
	      	     }           
	      	   },
				};
			}
			else { #Show icons
				push @menu, {
					text => $sorted[$i],
	      	   'icon-id' => 'plugins/SiriusRadio/html/images/' . $channelHash{$sorted[$i]} . '_56x56_p.gif',
	      	   actions  => {
	      	     go  => {
	      	         player => 0,
	      	         cmd    => [ 'siriusDetail', $channelHash{$sorted[$i]} ],
	      	         params => {
	      	         	menu => 'nowhere',
	      	         },
	      	     },
	      	     play  => {
	      	         player => 0,
	      	         cmd    => [ 'siriusPlayChannel', $channelHash{$sorted[$i]} ],
	      	         params => {
	      	         	menu => 'nowhere',
	      	         }
	      	     }           
	      	   },
				};
			}
					
			$i++;
		}
	}
	else {
		push @menu, {
			#'icon-id' => "plugins/SiriusRadio/html/images/$presets[$i]_56x56_p.gif",
			text => "Retrieving channel data...\nPlease try again.",
				};	
	}

	my $numitems = scalar(@menu);
	
	if ($showIcon == 1) {
		$request->addResult("base", {window => { titleStyle => 'album' }});
	}
	
	$request->addResult("count", $numitems);
	$request->addResult("offset", 0);
	my $cnt = 0;
	for my $eachGenreMenu (@menu[0..$#menu]) {
		#$log->debug(Dumper($eachGenreMenu));
		$request->setResultLoopHash('item_loop', $cnt, $eachGenreMenu);
		$cnt++;
	}
	$request->setStatusDone();
}

sub siriusDetail {
	my $request = shift;
	my $client = $request->client();
	my $channelNum = $request->getParam('_channelNum');

	my $channelRef = channelLookup($channelNum);
	
	lastInteractionUpdate($client);

	if ($totalStations == 0 && $dataRequests == 0 && $webMessage{$client} ne 'Retrieving channel data...') {
		$webMessage{$client}='Retrieving channel data...';
		$webRefresh{$client} = 2;

		getCategories($client);
	}

	my @menu = ();
		push @menu, {
			text => $channels[1][$channelRef],
         actions  => {
           play  => {
               player => 0,
               cmd    => [ 'siriusPlayChannel', $channelNum ],
               params => {
               	menu => 'nowhere',
               }
           }
         }
      };

		push @menu, {
			text => "$channels[9][$channelRef]",
         actions  => {
           play  => {
               player => 0,
               cmd    => [ 'siriusPlayChannel', $channelNum ],
               params => {
               	menu => 'nowhere',
               }
           }
         }
      };
      
		push @menu, {
			text => "Genre: $channels[6][$channelRef]",
         actions  => {
           go  => {
               player => 0,
               cmd    => [ 'siriusByGenre', $channels[7][$channelRef] ],
               params => {
               	menu => 'siriusByGenre',
               },
           },
         }
      };	

		push @menu, {
			text => "Number: $channels[0][$channelRef]",
         actions  => {
           play  => {
               player => 0,
               cmd    => [ 'siriusPlayChannel', $channelNum ],
               params => {
               	menu => 'nowhere',
               }
           }
         }
      };	


		my @presets = @{ $prefs->get('plugin_siriusradio_presets') || [] };
		my $presetMode = 'Add';
	
		#Figure out if preset already exists
		my $i=0;
		while ($i <@presets) {
			if ($channelNum == $presets[$i]) {
				$presetMode = 'Remove';
			}
	
			$i++;
		}		

		push @menu, {
			text => $presetMode.' Preset',
     	   actions  => {
     	     do  => {
     	         player => 0,
     	         cmd    => [ 'siriusAddPreset', $channelNum, $presetMode ],
     	     },
           play  => {
               player => 0,
               cmd    => [ 'siriusPlayChannel', $channelNum ],
               params => {
               	menu => 'nowhere',
               }
           }     	     
     	   },
		};

	my $numitems = scalar(@menu);

	$request->addResult("count", $numitems);
	$request->addResult("offset", 0);
	my $cnt = 0;
	for my $eachGenreMenu (@menu[0..$#menu]) {
		#$log->debug(Dumper($eachGenreMenu));
		$request->setResultLoopHash('item_loop', $cnt, $eachGenreMenu);
		$cnt++;
	}
	$request->setStatusDone();
}


sub siriusTopMenu {
	my $request = shift;
	my $client = $request->client();
	
	lastInteractionUpdate($client);

	if ($totalStations == 0 && $dataRequests == 0 && $webMessage{$client} ne 'Retrieving channel data...') {
		$webMessage{$client}='Retrieving channel data...';
		$webRefresh{$client} = 2;

		getCategories($client);
	}

	my @menu = ();
	
		push @menu, {
			text => 'Sirius Presets',
			window => {menuStyle=>'album'},
         actions  => {
           go  => {
               player => 0,
               cmd    => [ 'siriuspresets' ],
               params => {
               	menu => 'siriuspresets',
               },
           },
         }
      };

		push @menu, {
			text => 'Browse Genres',
         actions  => {
           go  => {
               player => 0,
               cmd    => [ 'siriusGenres' ],
               params => {
               	menu => 'siriusGenres',
               },
           },
         }
      };        

		push @menu, {
			text => 'Browse By Name',
         actions  => {
           go  => {
               player => 0,
               cmd    => [ 'siriusCommon', 0, 0, 0, 1 ],
               params => {
               	menu => 'siriusCommon',
               },
           },
         }
      };

		push @menu, {
			text => 'Browse By Number',
         actions  => {
           go  => {
               player => 0,
               cmd    => [ 'siriusCommon', 1, 0, 0, 1 ],
               params => {
               	menu => 'siriusCommon',
               },
           },
         }
      };
         
		push @menu, {
			text => 'Browse Now Playing',
         actions  => {
           go  => {
               player => 0,
               cmd    => [ 'siriusCommon', 1, 0, 0, 9 ],
               params => {
               	menu => 'siriusCommon',
               },
           },
         }
      };  
      
		push @menu, {
			text => 'Browse Extended',
			window => {menuStyle=>'album'},
         actions  => {
           go  => {
               player => 0,
               cmd    => [ 'siriusCommon', 1, 1, 1, 1 ],
               params => {
               	menu => 'siriusCommon',
               },
           },
         }
      };  
	
	my $numitems = scalar(@menu);

	$request->addResult("count", $numitems);
	$request->addResult("offset", 0);
	my $cnt = 0;
	for my $eachGenreMenu (@menu[0..$#menu]) {
		#$log->debug(Dumper($eachGenreMenu));
		$request->setResultLoopHash('item_loop', $cnt, $eachGenreMenu);
		$cnt++;
	}
	$request->setStatusDone();
}

sub cliRadiosQuery {
	my $request = shift;
	my $menu = $request->getParam('menu');

	my $data;
	# what we want the query to report about ourself
	if (defined $menu) {
		$data = {
			'text'    => Slim::Utils::Strings::string(getDisplayName()),  # nice name
			#'icon-id' => Slim::Plugin::SiriusRadio::Plugin->_pluginDataFor('icon'),
			'icon-id' => 'plugins/SiriusRadio/html/images/sirius5_56x56_p.png',
			'actions' => {
				'go' => {
					'cmd' => ['siriusTopMenu'],
					'params' => {
						'menu' => 'siriusTopMenu',
					},
				},
			},
			window    => {
				titleStyle => 'album',
			},
		};
	}
	else {
		$data = {
			'cmd' => 'siriusTopMenu',                    # cmd label
			'name' => Slim::Utils::Strings::string(getDisplayName()),  # nice name
			'type' => 'xmlbrowser',              # type
		};
	}
	
	# let our super duper function do all the hard work
	Slim::Control::Queries::dynamicAutoQuery($request, 'radios', $cli_next, $data);
}

sub playChannel {
	my $request    = shift;
	my $client     = $request->client();
	my $channelNum = $request->getParam('_channelNum');

	$client->showBriefly( { 'jive' => { 'text'    => [ "Playing Sirius Channel $channelNum.\n".$channels[1][channelLookup($channelNum)]."\n".$channels[9][channelLookup($channelNum)] ], } },{'duration' => 1, 'block' => 1, } );
	
	addSiriusURL($client, $channelNum, 'play');
	
	$client->update();		
	
	$request->setStatusDone();
}

#Adds a SiriusRadio to a client's playlist. Can either 'add' to existing playlist or destory existing playlist and 'play'
sub addSiriusURL {
	my $client = shift;
	my $channelNum = shift;
	my $action = shift;

	if ($action eq 'play') {
		$client->execute(['playlist', 'clear']);
		$client->execute(['playlist', 'add', "siriusradio://$channelNum/".$channels[1][channelLookup($channelNum)]]);
		$client->execute(['play']);	
	}
	else {
		$client->execute(['playlist', 'add', "siriusradio://$channelNum/".$channels[1][channelLookup($channelNum)]]);
	}
}


sub addPreset {
	my $request   = shift;
	my $client    = $request->client();
	my $channelNum = $request->getParam('_channelNum');
	my $mode = $request->getParam('_mode'); #Add or Remove

	my @presets = @{ $prefs->get('plugin_siriusradio_presets') || [] };
	
	if ($mode eq 'Add') {
		push(@presets, $channelNum);
		$client->showBriefly( { 'jive' => { 'text'    => [ 'Preset added.' ], } },{'duration' => 1, 'block' => 1, } );
	}
	else { #Remove preset
		my $i=0;
		while ($i <@presets) {
			if ($channelNum == $presets[$i]) {
				splice(@presets, $i, 1);
			}

			$i++;
		}
		$client->showBriefly( { 'jive' => { 'text'    => [ 'Preset removed.' ], } },{'duration' => 1, 'block' => 1, } );
	}

	$prefs->set('plugin_siriusradio_presets', \@presets);
	$request->setStatusDone();
}

sub getToken {  #Set up Async HTTP request
	my $client = shift;
	my $channelRef = shift; #Channel to play once relogged in
	
	$token = ''; #Reset token in case old value is set
	$cookie =''; #Reset cooking in case old value is set
	
	#my $url = 'http://www.sirius.com/servlet/MediaPlayerLogin/subscriber';
	#my $url = 'http://www.sirius.com/sirius/servlet/MediaPlayerLogin/subscriber';
	
	my $url;
	if ($prefs->get('plugin_siriusradio_location') == 0) { #USA
		$url = 'http://www.sirius.com/sirius/servlet/MediaPlayer?stream=undefined&'; #USA
	}
	else { #Canada
		$url = 'http://mp.siriuscanada.ca/sirius/ca/servlet/MediaPlayer?stream=undefined&'; #Canada
	}
	
	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&gotToken,
							  \&gotErrorViaHTTP,
							  {caller => 'getToken',
							   client => $client,
							   channelRef => $channelRef});
	
	$log->info("getToken: $url");

	#Website no longer seems to care...
	#$webMessage{$client} = 'Logging into Sirius.';
	#$webRefresh{$client} = 4;
	
	$http->get( $url, 'User-Agent' => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.1) Gecko/20061204 Firefox/2.0.0.1' );
	
}

sub gotToken {  #Token data was received
	my $http = shift;

	my $params = $http->params();
	my $client = $params->{'client'};
	my $channelRef = $params->{'channelRef'}; #Channel to play once relogged in

	$errorCount = 0;  #Successful get, reset error count

	$log->info("SiriusRadio: gotToken:" . $http->url());
	
	#$::d_plugins && msg("SiriusRadio: content type is " . $http->headers()->{'Content-Type'} . "\n");
	#$::d_plugins && msg("SiriusRadio: COOKIE:" . $http->headers()->{'Set-Cookie'} . "\n");
	#$::d_plugins && msg("SiriusRadio: gotToken DATA:" . $http->content() . "\n");
	$log->info($http->content());

	#my %hashey = $http->headers();
	#my @keys = keys %hashey;
	#my @values = values %hashey;
	
	my $content = $http->content();
	my @ary=split /\n/,$content; #break large string into array

	#$cookie = $http->headers()->{'Set-Cookie'};
	my @cookies = $http->headers->header('Set-Cookie');

	#$log->info("gotToken COOKIE0:" . $cookies[0]);
	#$log->info("gotToken COOKIE1:" . $cookies[1]);
	#$log->info("gotToken COOKIE2:" . $cookies[2]);
	#$log->info("gotToken COOKIE3:" . $cookies[3]);
	#$log->info("gotToken COOKIE4:" . $cookies[4]);
	#$log->info("gotToken COOKIE5:" . $cookies[5]);
	
	#Need to make this more elegant
	$cookie = $cookies[0];
	my $username = $prefs->get('plugin_siriusradio_username');
	
	my $captchaTS = $cookies[3];
	if ($captchaTS =~ /(.*);/) {
		$captchaTS = $1;
	}
	
	if ($cookie =~ /(.*);/) {
		if ($prefs->get('plugin_siriusradio_location') == 0) { #USA
			$cookie = $1. ";sirius_campain_code=null;sirius_login_type=subscriber;sirius_user_name=$username;sirius_mp_playertype=0;sirius_mp_pw=".getPassword().";$captchaTS"; #USA
		}
		else { #Canada
			$cookie = $1 . ";sirius_mp_pw=".getPassword().";sirius_user_name=$username;sirius_mp_playertype=0;sirius_login_type=subscriber;sirius_promocode=null;$captchaTS;sirius_campaign_code=null"; #Canada
		}
		
		if($prefs->get('plugin_siriusradio_bitrate') == 1) { #High bandwidth?
			$cookie = $cookie . ";sirius_mp_bitrate_button_status_cookie=high;sirius_mp_bitrate_entitlement_cookie=highbandwidth";
		}
	}
	
	my $captchaID = '';
	my $captchaIMG = -1;
	
	my @codes;
	$codes[0]='';
	$codes[1]='vRLCHr';
	$codes[2]='Rk9f3b';
	$codes[3]='tN2R1A';
	$codes[4]='R3iwj5';
	$codes[5]='jBjsVj';
	$codes[6]='v3jvKg';
	$codes[7]='iimNmx';
	$codes[8]='cahMYf';
	$codes[9]='Vw3rxG';
	$codes[10]='R7KPgK';
	$codes[11]='RUyTUS';
	$codes[12]='Cef11w';
	$codes[13]='NAQbyX';
	$codes[14]='q6EYAH';
	$codes[15]='tReWYs';
	$codes[16]='fimQlm';
	$codes[17]='U6qsi6';
	$codes[18]='m5Wkwh';
	$codes[19]='FpVR2T';
	$codes[20]='CuAF1k';
	$codes[21]='sgnUw7';
	$codes[22]='4N1RPP';
	$codes[23]='ech2am';
	$codes[24]='CtbsNQ';
	$codes[25]='kXrPES';
	$codes[26]='1AgXSR';
	$codes[27]='5DHYSR';
	$codes[28]='e3ru7T';
	$codes[29]='c1yjHE';
	$codes[30]='FR1ltI';
	$codes[31]='Xtn36U';
	$codes[32]='DHEWnx';
	$codes[33]='8KePqv';
	$codes[34]='1TKVVk';
	$codes[35]='BIY138';
	$codes[36]='RA6c83';
	$codes[37]='SaluKT';
	$codes[38]='T89gGV';
	$codes[39]='gUPVqL';
	$codes[40]='J4F3gi';
	$codes[41]='BbQnjy';
	$codes[42]='qLrRgi';
	$codes[43]='c3eSfa';
	$codes[44]='yAhdN5';
	$codes[45]='3YW4WC';
	$codes[46]='mPvBah';
	$codes[47]='UZnHN4';
	$codes[48]='x24GCx';
	$codes[49]='GLdYdn';
	$codes[50]='DsUIMk';
	$codes[51]='7GCaEc';
	$codes[52]='1WXPNr';
	$codes[53]='SRpRsG';
	$codes[54]='vSlae4';
	$codes[55]='r95Vhm';
	$codes[56]='1tGuK7';
	$codes[57]='wnZyD4';
	$codes[58]='c8lj6k';
	$codes[59]='sdQ3X4';
	$codes[60]='5FNMsi';
	$codes[61]='Up7Rni';
	$codes[62]='csjyJa';
	$codes[63]='9Uq5rm';
	$codes[64]='p9kbvj';
	$codes[65]='Cy1iip';
	$codes[66]='mc7y2c';
	$codes[67]='SE3rqi';
	$codes[68]='YmJ3Tv';
	$codes[69]='Qr32YN';
	$codes[70]='l3rcdJ';
	$codes[71]='xn33VA';
	$codes[72]='tjxuf4';
	$codes[73]='3hLBuU';
	$codes[74]='3fntSq';
	$codes[75]='rMYmpH';
	$codes[76]='yvKfyR';
	$codes[77]='bkxHDW';
	$codes[78]='EtUSs3';
	$codes[79]='3gA7wG';
	$codes[80]='Yn3uUL';
	$codes[81]='hCW9Cg';
	$codes[82]='aLI1R7';
	$codes[83]='wmkRRP';
	$codes[84]='Rm3C3i';
	$codes[85]='CgS98N';
	$codes[86]='xaF7cd';
	$codes[87]='ATxch8';
	$codes[88]='8I1rDk';
	$codes[89]='C8896y';
	$codes[90]='SiNusq';
	$codes[91]='AQZ3kR';
	$codes[92]='ARFUSP';
	$codes[93]='hDgs72';
	$codes[94]='Lxbg1X';
	$codes[95]='4716A3';
	$codes[96]='gCkAqa';
	$codes[97]='wRDWeN';
	$codes[98]='h64fGf';
	$codes[99]='Cr2VPm';
	$codes[100]='66SiiF';
	
	for (@ary) {
		if (/token" value="(.*)">/) {
			$token = $1;
		}
		elsif (/captchaID" value="(.+)">/) {
			$captchaID = $1;
		}
		elsif (/captcha\/image\/img_(\d\d\d)/) {
			$captchaIMG = $1;
		}
	}
	
	$log->info("CaptchaID:" . $captchaID);
	$log->info("CaptchaIMG:" . $captchaIMG);
	$log->info("CaptchaANS:" . $codes[$captchaIMG]);
	$log->info("New Token:" . $token);
	$log->info("New Cookie:" . $cookie);

	if ($cookie ne '' && $token ne '') {
		getLogin($client, $channelRef, $captchaID, $codes[$captchaIMG]);
	}
	else {
		$log->warn("Failed to get a new token and cookie.");
		Slim::Utils::Timers::killTimers($client, \&getTitle); #No need to continue to get titles if not logged in properly.
		$log->debug("*** UNBLOCKING 2 ***");
		$client->unblock();
		$client->update();
	}
}

sub getLogin {  #Set up Async HTTP request
	my $client = shift;
	my $channelRef = shift;
	my $captchaID = shift;
	my $captchaANS = shift;
	
	$loggedIn = 0;
	
	my $url;
	if ($prefs->get('plugin_siriusradio_location') == 0) { #USA
		$url = 'http://www.sirius.com/sirius/servlet/MediaPlayerLogin/subscriber'; #USA
	}
	else { #Canada
		$url = 'http://mp.siriuscanada.ca/sirius/ca/servlet/MediaPlayerLogin/subscriber'; #Canada
	}
	
	my $username = $prefs->get('plugin_siriusradio_username');
	#$url = $url . '?activity=login&type=subscriber&loginForm=subscriber&stream=undefined&token=' . $token . '&playerType=full&username='.$username.'&password=' . getPassword() . '&rememberMe=no'; 
	$url = $url . '?activity=login&type=subscriber&loginForm=subscriber&stream=undefined&token=' . $token . '&username='.$username.'&password=' . getPassword() . '&rememberMe=no&captchaID=' . $captchaID . '&captcha_response='. $captchaANS . '&playerType=full'; 

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&gotLogin,
							  \&gotErrorViaHTTP,
							  {caller => 'getLogin',
							   client => $client,
							   channelRef => $channelRef});
	$log->info($url);

	my %headers = (
		"Cookie" => $cookie,
		"User-Agent" => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.1) Gecko/20061204 Firefox/2.0.0.1'
	);

	#$http->get($url, %headers);
	#$http->get($url, {cookie => $cookie,
	#						"User-Agent" => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.1) Gecko/20061204 Firefox/2.0.0.1'});
	$http->get($url, cookie => $cookie,	"User-Agent" => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.1) Gecko/20061204 Firefox/2.0.0.1');
	
}

sub gotLogin {  #Token data was received
	my $http = shift;
	my $params = $http->params();
	my $client = $params->{'client'};
	my $channelRef = $params->{'channelRef'};

	$errorCount = 0;  #Successful get, reset error count

	$log->info($http->url());
	
	#$::d_plugins && msg("SiriusRadio: content type is " . $http->headers()->{'Content-Type'} . "\n");
	#$::d_plugins && msg("SiriusRadio: COOKIE:" . $http->headers()->{'Set-Cookie'} . "\n");
	#$::d_plugins && msg("SiriusRadio: gotLogin DATA:" . $http->content() . "\n");

	my $content = $http->content();
	my @ary=split /\n/,$content; #break large string into array

	for (@ary) {
		if (/launchSubscriberPlayer/) {
				$loggedIn = 1;
				
				#Save login data in case SlimServer is restarted on the same day
				$prefs->set('plugin_siriusradio_cookie',$cookie);
				$prefs->set('plugin_siriusradio_token',$token);
				$tokenTime = Time::HiRes::time();
				$prefs->set('plugin_siriusradio_tokenTime',$tokenTime);

				#$client->update();
		}
		elsif (/Sorry, an error has occurred.  Please try again/) {
			$log->warn("Sirius.com said: Sorry, an error has occurred.  Please try again.");
		}
		elsif (/Unsuccessful Login.  Please check username and password./) {
			$log->warn("Sirius.com said: Unsuccessful Login.  Please check username and password.");
		}
		elsif (/The entered text does not match the image. Please try again./) {
			$log->warn("Sirius.com said: The entered text does not match the image. Please try again.");
		}
	}

	if ($loggedIn == 1) {
		if ($dataRequests>0 || $totalStations == 0) {
			$log->debug("***BLOCKING 3***");
			$client->block({'line1' => 'Retrieving channel data...'});
		}
		else {
			$log->debug("***UNBLOCKING 3***");
			$client->unblock();
			$client->update();
		}
		
		$log->info("Login Successful.");
		
		if (defined($channelRef)) { #Supposed to play a channel after logged in.
			my $channelNum = $channels[0][$channelRef];
			addSiriusURL($client, $channelNum, 'play');
		}
		$webMessage{$client} = '';
		$webRefresh{$client} = 3;
	}
	elsif ($loggedIn == 0) {
		$log->debug("***UNBLOCKING 4***");
		$client->unblock();
		Slim::Buttons::Common::popModeRight($client);
		$client->showBriefly( {
			line => ['Error: Login Failed.']
		},
		{
			scroll => 1,
			block  => 1,
		} );		

		$log->warn("Login Failed.");
		$webMessage{$client} = 'gotLogin:Login failed.';
		$webRefresh{$client} = 0;
	}
}

sub getHashKey {  #Set up Async HTTP request
	my $client = shift;
	my $channelLoc = shift;
	my $action = shift;
	my $callback = shift;
	my $song = shift;

	my $url;	
	if ($prefs->get('plugin_siriusradio_location') == 0) { #USA
		$url = 'http://www.sirius.com/sirius/servlet/MediaPlayer?activity=selectStream&stream='. $channelsRef->[2][$channelLoc] .'&genre='. $channelsRef->[7][$channelLoc] .'&category='. $channelsRef->[5][$channelLoc].'&token='. $token; #USA
	}
	else { #Canada
		$url = 'http://mp.siriuscanada.ca/sirius/ca/servlet/MediaPlayer?activity=selectStream&stream='. $channelsRef->[2][$channelLoc] . '&genre='. $channelsRef->[7][$channelLoc] .'&category='. $channelsRef->[5][$channelLoc] .'&token='. $token; #Canada
	}

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&gotHashKey,
							  \&gotErrorViaHTTP,
							  {caller => 'getHashKey',
							   client => $client,
							   channelRef => $channelLoc,
							   action => $action,
							   callback => $callback,
							   song => $song});
	
	$log->info("Using Cookie: $cookie");
	$log->info($url);
	
	my %headers = (
		"Cookie" => $cookie,
		"User-Agent" => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.1) Gecko/20061204 Firefox/2.0.0.1'
	);
	
	$http->get($url, %headers);
}

sub gotHashKey {  
	my $http = shift;
	my $params = $http->params();
	my $client = $params->{'client'};
	my $channelRef = $params->{'channelRef'};
	my $action = $params->{'action'};
	my $callback = $params->{'callback'};
	my $song = $params->{'song'};

	my $link = '';
	my $hashkey;
	
	$errorCount = 0;  #Successful get, reset error count

	$log->info($http->url());
	#$::d_plugins && msg("SiriusRadio: content type is " . $http->headers()->{'Content-Type'} . "\n");
	#$::d_plugins && msg("SiriusRadio: COOKIE:" . $http->headers()->{'Set-Cookie'} . "\n");
	#$::d_plugins && msg("SiriusRadio: gotHashKey DATA:" . $http->content() . "\n");

	my $content = $http->content();
	my @ary=split /\n/,$content; #break large string into array

	for (@ary) {
		if (/hashkey=(.*)">/) { #No longer used???
			$hashkey= $1;
			$log->info("Hash Key: $hashkey");
		}
		elsif (/SRC="(.*)"/) {
			$link = $1;
			$log->info("Link: $link");
		}
		elsif (/Max Daily Logins Exceeded/) {
			$log->warn("Max Daily Logins Exceeded.");
			$client->showBriefly( {
				line => ['Error: Maximum daily logins reached.']
				},
				{
				scroll => 1,
				block  => 1,
			} );		


			$webMessage{$client} = 'Error: Maximum daily logins reached.';
			$webRefresh{$client} = 0;

			return; #Must return otherwise it'll attempt to relogin again		
		}
		elsif (/unavailable/) {
			$log->warn("Sirius streams unavailable.");
			$webRefresh{$client} = 0;

			return; #Must return otherwise it'll attempt to relogin again		
		}
		elsif (/logged in too many times/) {
			$log->warn("Sorry, you've logged in too many times today.  Please try back tomorrow.");
			$client->showBriefly( {
				line => ['Error: Maximum daily logins reached.']
			},
			{
				scroll => 1,
				block  => 1,
			} );			
			
			$webMessage{$client} = 'Error: Maximum daily logins reached.';
			$webRefresh{$client} = 0;

			return; #Must return otherwise it'll attempt to relogin again
		}
	}

	#if ($hashkey ne '') {
	if ($link ne '') {
		getURL($client, $link, $channelRef, $action, $callback, $song);
	}
	else {
		$log->warn("ERROR: No link returned...");
		#Login must have expired
		$log->info("Login expired. Re-logging in...");
		$log->debug("***BLOCKING 4***");
		$client->block({'line1' => 'Re-Logging into Sirius...'});
		getToken($client, $channelRef);
	}
}


sub getURL {  #Set up Async HTTP request
	my $client = shift;
	my $link = shift;
	my $channelRef = shift;
	my $action = shift;
	my $callback = shift;
	my $song = shift;
	
	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&gotURL,
							  \&gotErrorViaHTTP,
							  {caller => 'getURL',
							   client => $client,
							   channelRef => $channelRef,
							   action => $action,
							   callback => $callback,
							   song => $song});
	$log->info($link);

	my %headers = (
		"Cookie" => $cookie,
		"User-Agent" => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.1) Gecko/20061204 Firefox/2.0.0.1'
	);
	
	$http->get($link, %headers);

}

sub gotURL {  
	my $http = shift;

	my $params = $http->params();
	my $client = $params->{'client'};
	my $channelRef = $params->{'channelRef'};
	my $action = $params->{'action'};
	my $callback = $params->{'callback'};
	my $song = $params->{'song'};

	$errorCount = 0;  #Successful get, reset error count

	$log->debug($http->url());
	#$::d_plugins && msg("SiriusRadio: content type is " . $http->headers()->{'Content-Type'} . "\n");
	#$::d_plugins && msg("SiriusRadio: COOKIE:" . $http->headers()->{'Set-Cookie'} . "\n");
	#$::d_plugins && msg("SiriusRadio: gotURL DATA:" . $http->content() . "\n");

	my $content = $http->content();
	
	$log->debug('RAW:' . $content);
	
	my @ary=split /\n/,$content; #break large string into array

	for (@ary) {	
	#	if (/href="(mms:\/\/.*)"/) {
		if (/Ref1=http(:\/\/.*asf)/) {
			$nowPlaying{$client}= 'mms' . $1;
			$client->pluginData( url     => 'mms' . $1 );
		   $nowPlayingRef{$client}=$channelRef;
		   $nowPlayingTime{$client} = 0;
			$channels[8][$channelRef] = $1; #Is this used anymore???
		}
		elsif (/http(:\/\/.*cache=0)/) { #Sirius Canada
			$nowPlaying{$client}= 'mms' . $1;
			$client->pluginData( url     => 'mms' . $1 );
		   $nowPlayingRef{$client}=$channelRef;
		   $nowPlayingTime{$client} = 0;
			$channels[8][$channelRef] = $1; #Is this used anymore???
		}		
	}   

	$log->info("Playing Stream: $channels[1][$channelRef]:" . $nowPlaying{$client});
	
	if ($action eq 'callback') {
		$song->{'streamUrl'} = $nowPlaying{$client};

		# Include the metadata sub-stream for this station
		$song->{'wmaMetadataStream'} = 2;
				
		$log->debug('******ABOUT TO DO A CALLBACK****');
		$callback->();
		return;
	}
	else {
		$log->debug("************** I SHOULD NOT BE HERE IN THE CODE********");
	}
}

sub getCategories {  #Set up Async HTTP request
	my $client = shift;
	
	$::d_plugins && msg('SiriusRadio: Location: '.$prefs->get('plugin_siriusradio_location')."\n");
	$log->info("Location:" . $prefs->get('plugin_siriusradio_location'));
	
	my $url;
	if ($prefs->get('plugin_siriusradio_location') == 0) { #USA
		$url = 'http://www.sirius.com/sirius/mediaplayer/player/common/lineup/category.jsp?category=&genre=&channel='; #USA
	}
	else { #Canada
		$url = 'http://mp.siriuscanada.ca/sirius/ca/mediaplayer/player/common/lineup/category.jsp?category=&genre=&channel='; #Canada
	}

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&gotCategories,
							  \&gotErrorViaHTTP,
							  {caller => 'getCategories',
							   client => $client});
	$log->debug($url);

	my %headers = (
		"Cookie" => $cookie,
		"User-Agent" => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.1) Gecko/20061204 Firefox/2.0.0.1'
	);
	
	$dataRequests++;
	$http->get($url, %headers);
}

sub gotCategories {  
	my $http = shift;

	my $params = $http->params();
	my $client = $params->{'client'};

	$errorCount = 0;  #Successful get, reset error count

	$log->debug($http->url());
	#$::d_plugins && msg("SiriusRadio: content type is " . $http->headers()->{'Content-Type'} . "\n");
	#$::d_plugins && msg("SiriusRadio: COOKIE:" . $http->headers()->{'Set-Cookie'} . "\n");
	#$::d_plugins && msg("SiriusRadio: DATA" . $http->content() . "\n");

	my $content = $http->content();
	my @ary=split /\n/,$content; #break large string into array

	for (@ary) { #Could probably speed this up a tat if necessary...
		if (/myPlayer.Category\('(.*)','\/sirius\/mediaplayer.*>(.*)</) { #USA
			push(@CDgetGenre1,$2);
			push(@CDgetGenre2,$1);
			$log->info("Found Category: $1 - $2");
		}
		elsif (/myPlayer.Category\('(.*)','\/sirius\/ca\/mediaplayer.*>(.*)</) { #Canada
			push(@CDgetGenre1,$2);
			push(@CDgetGenre2,$1);
		}
	}

	getGenres(pop(@CDgetGenre1), pop(@CDgetGenre2), $client);
	$dataRequests--;
}

sub getGenres {  #Set up Async HTTP request

	my $categoryName = shift;
	my $categoryRef = shift;
	my $client = shift;

	my $url;
	if ($prefs->get('plugin_siriusradio_location') == 0) { #USA
		$url = 'http://www.sirius.com/sirius/mediaplayer/player/common/lineup/genre.jsp?category='. $categoryRef; #USA
	}
	else { #Canada
		$url = 'http://mp.siriuscanada.ca/sirius/ca/mediaplayer/player/common/lineup/genre.jsp?category='. $categoryRef; #Canada
	}

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&gotGenres,
							  \&gotErrorViaHTTP,
							  {caller => 'getGenres',
							   categoryName => $categoryName,
							   categoryRef => $categoryRef,
							   client => $client});
							   
	$log->debug($url);

	my %headers = (
		"Cookie" => $cookie,
		"User-Agent" => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.1) Gecko/20061204 Firefox/2.0.0.1'		
	);
	
	$dataRequests++;
	$http->get($url, %headers);

}

sub gotGenres {  
	my $http = shift;
	my $params = $http->params();
	my $categoryName = $params->{'categoryName'};
	my $categoryRef = $params->{'categoryRef'};
	my $client = $params->{'client'};
	
	$errorCount = 0;  #Successful get, reset error count
	
	$log->debug($http->url());
	#$::d_plugins && msg("SiriusRadio: content type is " . $http->headers()->{'Content-Type'} . "\n");
	#$::d_plugins && msg("SiriusRadio: COOKIE:" . $http->headers()->{'Set-Cookie'} . "\n");
	#$log->debug($http->content());

	my $content = $http->content();
	my @ary=split /\n/,$content; #break large string into array
  
	for (@ary) {
		if (/myPlayer.Genre\('.*', '(.*)','\/sirius\/mediaplayer.*>(.*)</) {
			$log->info("Found Channel: " . $2 . '-' . $1);
			#Add genre to arrays to retrieve stations one at a time
			push(@CDcategoryName, $categoryName);
			push(@CDcategoryRef, $categoryRef);
			push(@CDgenreName, $2);
			push(@CDgenreRef, $1);
		}
		elsif (/myPlayer.Genre\('.*', '(.*)','\/sirius\/ca\/mediaplayer.*>(.*)</) { #Canada
			#$::d_plugins && msg("SiriusRadio: Genre:" . $2 . '-' . $1 . "\n");			
			#Add genre to arrays to retrieve stations one at a time
			push(@CDcategoryName, $categoryName);
			push(@CDcategoryRef, $categoryRef);
			push(@CDgenreName, $2);
			push(@CDgenreRef, $1);
		}
	}
	
	#Are there genres to get stations from?
	if (@CDcategoryName>0) {
		getStations($client);
	}
	
	$dataRequests--;
}

sub getStations {  #Set up Async HTTP request
	my $client = shift;
	my $categoryName = shift;
	my $categoryRef = shift;
	my $genreName = shift;
	my $genreRef = shift;

	if (!defined($categoryName)) {
		$categoryName = pop(@CDcategoryName);
	}

	if (!defined($categoryRef)) {
		$categoryRef = pop(@CDcategoryRef);
	}

	if (!defined($genreName)) {
		$genreName = pop(@CDgenreName);
	}
	
	if (!defined($genreRef)) {
		$genreRef = pop(@CDgenreRef);
	}

	my $url;
	if ($prefs->get('plugin_siriusradio_location') == 0) { #USA
		$url = 'http://www.sirius.com/sirius/mediaplayer/player/common/lineup/channel.jsp?category='.$categoryRef.'&genre='.$genreRef; #USA
	}
	else { #Canada
		$url = 'http://mp.siriuscanada.ca/sirius/ca/mediaplayer/player/common/lineup/channel.jsp?category='.$categoryRef.'&genre='.$genreRef; #Canada
	}
	
	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&gotStations,
							  \&gotErrorViaHTTP,
							  {caller => 'getStations',
							   categoryName => $categoryName,
							   categoryRef => $categoryRef,
							   genreName => $genreName,
							   genreRef => $genreRef,
							   client => $client});
	$log->debug($url);

	my %headers = (
		"Cookie" => $cookie,
		"User-Agent" => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.1) Gecko/20061204 Firefox/2.0.0.1'		
	);
	
	$dataRequests++;
	$http->get($url, %headers);

}

sub gotStations {  
	my $http = shift;
	my $params = $http->params();
	my $categoryName = $params->{'categoryName'};
	my $categoryRef = $params->{'categoryRef'};
	my $genreName = $params->{'genreName'};
	my $genreRef = $params->{'genreRef'};
	my $client = $params->{'client'};

	my $channelNum;
	my $channelName;
	my $channelRef;
	my $channelDesc;

	$errorCount = 0;  #Successful get, reset error count

	$log->debug($http->url());
	#$::d_plugins && msg("SiriusRadio: content type is " . $http->headers()->{'Content-Type'} . "\n");
	#$::d_plugins && msg("SiriusRadio: COOKIE:" . $http->headers()->{'Set-Cookie'} . "\n");
	#$::d_plugins && msg("SiriusRadio: DATA" . $http->content() . "\n");

	my $content = $http->content();
	my @ary=split /\n/,$content; #break large string into array
  	
	for (@ary) {
		if (/Channel\('.*', '.*', '(.*)','in.*class="channel">(\d+)/) {
			$channelNum = $2;
			$channelRef = $1;
		}
		elsif (/Channel\('.*', '.*', '(.*)','in.*class="channel">SIR-(\d+)/) { #Special case for SIR-# channels.  They'll be SIR-#+1000
			$channelNum = $2 + 1000;
			$channelRef = $1;
		}
		elsif (/class="text">(.*)</) {
			$channelName = $1;
		}
		elsif (/class="desc">(.*)</) {
			$channelDesc = $1;					
			#$::d_plugins && msg("SiriusRadio: Index $totalStations:$channelNum - $channelName $categoryName $genreName\n");

			#Store the channel info as an available channel
			$channels[0][$totalStations] = $channelNum;
			$channels[1][$totalStations] = $channelName;
			$channels[2][$totalStations] = $channelRef;
			$channels[3][$totalStations] = $channelDesc;
			$channels[4][$totalStations] = $categoryName;
			$channels[5][$totalStations] = $categoryRef;
			$channels[6][$totalStations] = $genreName;
			$channels[7][$totalStations] = $genreRef;			
			
			$channelNumLoc{$channelNum}=$totalStations;
			$log->info("Adding Channel $channelNum $channelName @ Index $totalStations");

			$totalStations++;
		}
	}
	$dataRequests--;

	#Are there genres remaining to get stations from?	
	if (@CDcategoryName>0) {
		getStations($client);
	}
	elsif (@CDgetGenre1>0) {
		getGenres(pop(@CDgetGenre1), pop(@CDgetGenre2), $client);
	}
	
	if ($dataRequests == 0) {
		$log->info("Total Channels Found: $totalStations");
		$log->debug("*** UNBLOCKING 5 ***");
		getTitle($client);
		if (defined($client)) {
			$client->unblock();
		}
		$webMessage{$client} = '';
		$webRefresh{$client} = 0;
	}
	
	if (defined($client)) {
		$client->update();
	}
}

#Not sure if this is necessary... but we'll keep it in case!
sub getStillListening {  #Set up Async HTTP request
	my $client = shift;

	my $url;
	if ($prefs->get('plugin_siriusradio_location') == 0) { #USA
		$url = 'http://www.sirius.com/sirius/mediaplayer/still_listening.jsp'; #USA
	}
	else {
		$url = 'http://mp.siriuscanada.ca/sirius/ca/mediaplayer/still_listening.jsp'; #Canada
	}

	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&gotStillListening,
							  \&gotErrorViaHTTP,
							  {caller => 'getStillListening',
							   client => $client});
	$log->info($url);

	my %headers = (
		"Cookie" => $cookie,
		"User-Agent" => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.1) Gecko/20061204 Firefox/2.0.0.1'		
	);
	
	$http->get($url, %headers);

}

sub gotStillListening {  
	my $http = shift;
	my $params = $http->params();
	my $client = $params->{'client'};

	$errorCount = 0;  #Successful get, reset error count

	$log->info($http->url());
	#$::d_plugins && msg("SiriusRadio: content type is " . $http->headers()->{'Content-Type'} . "\n");
	#$::d_plugins && msg("SiriusRadio: COOKIE:" . $http->headers()->{'Set-Cookie'} . "\n");
	#$::d_plugins && msg("SiriusRadio: DATA" . $http->content() . "\n");

	#my $content = $http->content();
	
	#Create new still there timer for 90minutes
	Slim::Utils::Timers::setTimer($client,
						Time::HiRes::time() + (90*60),
						\&getStillListening);	
	
}

sub gotErrorViaHTTP {
	my $http = shift;
	my $params = $http->params();
	my $caller = $params->{'caller'};
	my $client = $params->{'client'};
		
	$log->info("Error getting" . $http->url() . " Caller:$caller" . " Error:" . $http->error());

	#Add message to display to indicate error
	#gotError($params->{'client'}, $http->url(), $http->error());
	$errorCount++;
	$log->info("Network error count: $errorCount");
	
	if ($errorCount >= 20) {
		$log->warn("Network error count reached. I give up.");
		$log->debug("*** UNBLOCKING 6 ***");
		$client->showBriefly( {
			line => ['Network error count reached..']
		},
		{
			scroll => 1,
			block  => 1,
		} );		

		$client->unblock(); #Just in case its blocking when net errors occur
		$client->update();

		$lastInteraction = 0; #Reset this so that if user clicks something it'll try again...
		return;
	}
	
	if ($caller eq 'getTitle') {
		#Previous call to getTitle failed.  Lets try again. 
		getTitle($client);
	}
	elsif ($caller eq 'getCategories') {
		#Previous call failed, lets try again.
		$log->info("Trying $caller again...");
		$dataRequests--; #Subtract one since original failed, but new one will be created
		getCategories($client);
	}
	elsif ($caller eq 'getGenres') {
		#Previous call failed, lets try again.
		$log->info("Trying $caller again...");
		my $categoryName = $params->{'categoryName'};
		my $categoryRef = $params->{'categoryRef'};
		$dataRequests--; #Subtract one since original failed, but new one will be created
		getGenres($categoryName, $categoryRef, $client);
	}	
	elsif ($caller eq 'getStations') {
		#Previous call failed, lets try again.
		$log->info("Trying $caller again...");
		my $categoryName = $params->{'categoryName'};
		my $categoryRef = $params->{'categoryRef'};
		my $genreName = $params->{'genreName'};
		my $genreRef = $params->{'genreRef'};
		$dataRequests--; #Subtract one since original failed, but new one will be created
		getStations($client, $categoryName, $categoryRef, $genreName, $genreRef);
	}	
	elsif ($caller eq 'getToken') {
		#Previous call failed, lets try again.
		$log->info("Trying $caller again...");
		my $channelRef = $params->{'channelRef'};
		getToken($client, $channelRef);
	}	
	elsif ($caller eq 'getHashKey') {
		#Previous call failed, lets try again.
		$log->info("Trying $caller again...");
		my $channelRef = $params->{'channelRef'};
		my $action = $params->{'action'};
		my $callback = $params->{'callback'};
		my $song = $params->{'song'};

		getHashKey($client, $channelRef, $action, $callback, $song);
	}
	elsif ($caller eq 'getURL') {
		#Previous call failed, lets try again.
		$log->info("Trying $caller again...");
		my $channelRef = $params->{'channelRef'};
		my $action = $params->{'action'};
		getURL($client, $channelRef, $action);
	}
	elsif ($caller eq 'getStillListening') {
		#Previous call failed, lets try again.
		$log->info("Trying $caller again...");
		getStillListening($client);
	}
	else {
		$log->warn("Network error. Unblocking client.");
		Slim::Buttons::Common::popModeRight($client);
		$client->showBriefly( {
			line => ['Network error.']
		},
		{
			scroll => 1,
			block  => 1,
		} );		

		$log->debug("*** UNBLOCKING 1 ***");
		$client->unblock(); #Just in case its blocking when net errors occur
		$client->update();

		$totalStations = 0; #This way channel data will be refreshed next time plugin is entered

		return;
	}	
}

sub lastInteractionUpdate {
	my $client = shift;

	my $now =Time::HiRes::time();
	if ($now > ($lastInteraction + 1800)) { #Every 30min
		$log->info("Starting up getTitle monitoring.");

		Slim::Utils::Timers::killTimers($client, \&getTitle); #Kill an existing timer in case there is one				

		#Create still there timer for 90minutes
		Slim::Utils::Timers::setTimer($client,
							Time::HiRes::time() + (90*60),
							\&getStillListening);	
		
		getTitle($client);
	}	

	$lastInteraction = $now;
}

sub setMode() {
	my $class  = shift;
	my $client = shift;
	my $method = shift;

	#There has been some user interaction...
	lastInteractionUpdate($client);
	
	if ($method eq 'pop') {
		#$::d_plugins && msg("SiriusRadio: Inside setMode POP.\n");
		Slim::Buttons::Common::popMode($client);
		return;
	}

	if ($totalStations == 0) {
		getCategories($client);
	}	
		
	$current{$client} ||= 0;

	#Menus shown when using remote control
	my @mainmenu = ("Browse by Preset", "Browse by name", "Browse by number", "Browse by genre", "Browse by now playing");

	my %params = (
		header => $client->string('PLUGIN_SIRIUSRADIO'),
		title    => $client->string(getDisplayName()),
		listRef => \@mainmenu,
		externRef => sub {
			my $client = shift;
			my $value = shift;
			
			$selectedChannel{$client} = '';
			return $value;
		},
		headerAddCount => 1,
		overlayRef => sub {return (undef, $client->symbols('rightarrow'));},
		valueRef => \$current{$client},
		callback => sub {
			my $client = shift;
			my $method = shift;
			
			my $selection = ${$client->modeParam('valueRef')};
			
			#Need to store names in strings.txt at some point....
			if ($selection eq $mainmenu[0]) {#By preset
				my @presets = @{ $prefs->get('plugin_siriusradio_presets') || [] };
				if (@presets>0 && $presets[0]>0) { #Are there any presets set.  Check >0 since server stores 0 value for none for some reason...
					channelPresetMode($client, $method);
				}
				else {
					$client->showBriefly( {
						line => ['No presets defined.']
					},
					{
						scroll => 1,
						block  => 1,
					} );		
				}
			}			
			if ($selection eq $mainmenu[1]) { #By name
				channelNameMode($client, $method);
			}
			elsif ($selection eq $mainmenu[2]) {#By number
				channelNumberMode($client, $method);
			}
			elsif ($selection eq $mainmenu[3]) {#By genre
				channelGenreListMode($client, $method);
			}
			elsif ($selection eq $mainmenu[4]) {#By now playing
				channelNowPlayingMode($client, $method);
			}
		},
	);

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);

	if ($loggedIn == 0) {
		$log->debug("*** BLOCKING 1 ***");
		$client->block({'line1' => 'Logging into Sirius...'});
		getToken($client);
	}	
	elsif ($dataRequests>0) {
		$log->debug("*** BLOCKING 2 ***");
		$client->block({'line1' => 'Retrieving channel data...'});
	}	
}

sub channelNameMode() {
	my $client = shift;
	my $method = shift;

	#There has been some user interaction...
	lastInteractionUpdate($client);

	if ($method eq 'right') {		
		my %channelHash = ();
		my $i=0;
		while ($i <$totalStations) {
			$channelHash{$channels[1][$i]} = $i;
			$i++;
		}
		
		my @sorted = sort keys %channelHash;

		my %params = (
			header => 'Sirius Channels',
			listRef => \@sorted,
			externRef => sub {
				my $client = shift;
				my $value = shift;
			
				$selectedChannel{$client} = $channelHash{$value};
				return $value;
			},			
			headerAddCount => 1,
			overlayRef => sub {return (undef, $client->symbols('notesymbol'));},
			#valueRef => \$current{$client},
			isSorted => 'I',
		);
		
		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
	}
	elsif ($method eq 'left') {
		Slim::Buttons::Common::popModeRight($client);
	}
}

sub channelGenreListMode() {
	my $client = shift;
	my $method = shift;

	#There has been some user interaction...
	lastInteractionUpdate($client);

	if ($method eq 'right') {		
		my %channelGenreListHash = ();
		my $i=0;
		while ($i <$totalStations) {
			if ($channels[4][$i] eq 'MUSIC') {
				$channelGenreListHash{$channels[6][$i]} = $channels[7][$i];	
			}

			$i++;
		}
		
		#Manually add genres
		$channelGenreListHash{'Howard Stern'} = 'specials';
		$channelGenreListHash{'Comedy'} = 'comedy';
		$channelGenreListHash{'News'} = 'catnews';
		$channelGenreListHash{'Sports'} = 'sports';
		$channelGenreListHash{'Family & Health'} = 'catfamilykid';
		$channelGenreListHash{'Talk/Entertainment'} = 'cattalk';
						
		my @sorted = sort keys %channelGenreListHash;

		my %params = (
			header => 'Sirius Genres',
			listRef => \@sorted,
			externRef => sub {
				my $client = shift;
				my $value = shift;
			
				$selectedChannel{$client} = '';
				return $value;
			},					
			headerAddCount => 1,
			overlayRef => sub {return (undef, $client->symbols('rightarrow'));},
			valueRef => \$current{$client},
			isSorted => 'I',
			callback => sub {
				my $client = shift;
				my $method = shift;
				channelGenreMode($client, $method, $channelGenreListHash{$sorted[$client->modeParam('listIndex')]});
			}
		);
		
		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
	}
	elsif ($method eq 'left') {
		Slim::Buttons::Common::popModeRight($client);
	}
}

sub channelGenreMode() {
	my $client = shift;
	my $method = shift;
	my $genreRef = shift;

	#There has been some user interaction...
	lastInteractionUpdate($client);

	if ($method eq 'right') {		
		my %channelGenreHash = ();
		my $i=0;
		while ($i <$totalStations) {
			if ($channels[7][$i] eq $genreRef) { 
				$channelGenreHash{$channels[1][$i]} = $i;
			}
			elsif ($genreRef eq 'catnews' && $channels[4][$i] eq 'NEWS') {
				$channelGenreHash{$channels[1][$i]} = $i;
			}
			elsif ($genreRef eq 'specials' && $channels[4][$i] eq 'HOWARD STERN') {
				$channelGenreHash{$channels[1][$i]} = $i;
			}
			elsif ($genreRef eq 'comedy' && $channels[4][$i] eq 'COMEDY') {
				$channelGenreHash{$channels[1][$i]} = $i;
			}
			elsif ($genreRef eq 'sports' && $channels[4][$i] eq 'SPORTS') {
				$channelGenreHash{$channels[1][$i]} = $i;
			}			
			elsif ($genreRef eq 'catfamilykid' && $channels[4][$i] eq 'FAMILY & HEALTH') {
				$channelGenreHash{$channels[1][$i]} = $i;
			}						
			elsif ($genreRef eq 'cattalk' && $channels[4][$i] eq 'TALK/ENT') {
				$channelGenreHash{$channels[1][$i]} = $i;
			}									
			$i++;
		}
		
		my @sortedGenres = sort keys %channelGenreHash;

		my %params = (
			header => 'Sirius Channels',
			listRef => \@sortedGenres,
			externRef => sub {
				my $client = shift;
				my $value = shift;
			
				$selectedChannel{$client} = $channelGenreHash{$value};
				return $value;
			},			
			headerAddCount => 1,
			overlayRef => sub {return (undef, $client->symbols('notesymbol'));},
			valueRef => \$current{$client},
			isSorted => 'I',
		);
		
		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
	}
	elsif ($method eq 'left') {
		Slim::Buttons::Common::popModeRight($client);
	}
}

sub by_number {
	my $first;
	my $second;
	
	if ($a =~ /(\d+)./) {
		$first = $1;
	}
	
	if ($b =~ /(\d+)./) {
		$second = $1;
	}

    if ($first < $second) {
        return -1;
    } elsif ($first == $second) {
        return 0;
    } elsif ($first > $second) {
        return 1;
    }
}

sub channelNumberMode() {
	my $client = shift;
	my $method = shift;

	#There has been some user interaction...
	lastInteractionUpdate($client);

	if ($method eq 'right') {		
		my %channelHash = ();
		my $i=0;
		while ($i <$totalStations) {
			$channelHash{$channels[0][$i].'. '. $channels[1][$i]} = $i;
			$i++;
		}
		
		my @sorted = sort by_number keys %channelHash;

		my %params = (
			header => 'Sirius Channels',
			listRef => \@sorted,
			externRef => sub {
				my $client = shift;
				my $value = shift;
			
				$selectedChannel{$client} = $channelHash{$value};
				return $value;
			},				
			headerAddCount => 1,
			overlayRef => sub {return (undef, $client->symbols('notesymbol'));},
			valueRef => \$current{$client},
		);
		
		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
	}
	elsif ($method eq 'left') {
		Slim::Buttons::Common::popModeRight($client);
	}
	
}

sub channelNowPlayingMode() {
	my $client = shift;
	my $method = shift;

	#There has been some user interaction...
	lastInteractionUpdate($client);

	if ($method eq 'right') {		
		my %channelHash = ();
		my $i=0;
		while ($i <$totalStations) {
			if (defined($channels[9][$i])) {
	   		$channelHash{$channels[0][$i].'. '. $channels[9][$i]} = $i;
			}
	   	elsif ($channels[0][$i] != 98 && $channels[0][$i] != 143) { #Channels would appear twice because theyre in the directory twice
				$channelHash{$channels[0][$i].'. Not Available'} = $i;
			}
			$i++;
		}
		
		my @sorted = sort by_number keys %channelHash;

		my %params = (
			header => 'Sirius Channels',
			listRef => \@sorted,
			externRef => sub {
				my $client = shift;
				my $value = shift;
			
				$selectedChannel{$client} = $channelHash{$value};
				return $value;
			},				
			headerAddCount => 1,
			overlayRef => sub {return (undef, $client->symbols('notesymbol'));},
			valueRef => \$current{$client},
		);
		
		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
	}
	elsif ($method eq 'left') {
		Slim::Buttons::Common::popModeRight($client);
	}	
}

#Looks up the internal ref for a given Sirius channel number
sub channelLookup {
	my $blah = shift;
	
	return $channelNumLoc{$blah};
}

sub channelPresetMode() {
	my $client = shift;
	my $method = shift;

	#There has been some user interaction...
	lastInteractionUpdate($client);

	if ($method eq 'right') {		
		my %channelHash = ();
		
		my @presets = @{ $prefs->get('plugin_siriusradio_presets') || [] };
		my @presetsDisp;
		
		my $i=0;
		while ($i <@presets) {
			$presetsDisp[$i] = $channels[0][$channelNumLoc{$presets[$i]}].'. '. $channels[1][$channelNumLoc{$presets[$i]}];
			$channelHash{$presetsDisp[$i]}= $channelNumLoc{$presets[$i]};
			$i++;
		}
		
		my %params = (
			header => 'Sirius Presets',
			listRef => \@presetsDisp,
			externRef => sub {
				my $client = shift;
				my $value = shift;
			
				$selectedChannel{$client} = $channelHash{$value};
				
				return $value;
			},				
			headerAddCount => 1,
			overlayRef => sub {return (undef, $client->symbols('notesymbol'));},
			valueRef => \$current{$client},
		);
		
		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
	}
	elsif ($method eq 'left') {
		Slim::Buttons::Common::popModeRight($client);
	}
	
}

sub getTitle() {
	my $client = shift;

	my $titleSource = $prefs->get('plugin_siriusradio_titlesource');
	my $url;
	if ($titleSource == 0) {
		$url = 'http://itsonsirius.net/';
	}
	elsif ($titleSource == 1) {
		$url = 'http://itson.siriusbackstage.com:8999/itson/streams.php';
	}
	else {
		$url = 'http://dogstardata.org/tracker/squeezebox.txt';
	}
	
	my $http = Slim::Networking::SimpleAsyncHTTP->new(\&gotTitle,
							  \&gotErrorViaHTTP,
							  {caller => 'getTitle',
							   client => $client});

	if (($dataRequests==0) && ($totalStations>10)) { #Make sure all the channels are received already
	#if (($loggedIn == 1) && ($dataRequests==0) && ($totalStations>10)) { #Make sure all the channels are received already
		#$::d_plugins && msg("SiriusRadio: getTitle.\n");
		$log->debug($url);
		$http->get( $url, 'User-Agent' => 'SlimServer/7.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.1) Gecko/20061204 Sirius/1.0.0' );
	}
	
}

sub gotTitle() {
	my $http = shift;
	my $params = $http->params();
	my $client = $params->{'client'};

	$errorCount = 0;  #Successful get, reset error count

	#$log->debug("gotTitle.");
	#$::d_plugins && msg("SiriusRadio: gotTitle: " . $http->url() . "\n");
	#$::d_plugins && msg("SiriusRadio: content type is " . $http->headers()->{'Content-Type'} . "\n");
	#$::d_plugins && msg("SiriusRadio: COOKIE:" . $http->headers()->{'Set-Cookie'} . "\n");
	#$::d_plugins && msg("SiriusRadio: DATA" . $http->content() . "\n");

	my $content = $http->content();
	
#	my $channelNum = $channels[0][$selectedChannel{$client}];

#	$::d_plugins && msg("SiriusRadio: Channel Number:$channelNum\n");
#	$::d_plugins && msg("SiriusRadio: Selected Ref:$selectedChannel{$client}\n");
#	$::d_plugins && msg("SiriusRadio: Now Playing Ref:$nowPlayingRef{$client}\n");

	my $titleSource = $prefs->get('plugin_siriusradio_titlesource');

	if ($dataRequests == 0) { #If there are still lingering data requests, no need to update channel info.  Otherwise could corrupt.
		if ($titleSource == 1) { #Sirus backstage
			my @ary=split /\n/,$content; #break large string into array

			for (@ary) {
				if (/Array\((\d+),"(.*)","(.*)",""\)/) {			
					$channels[9][$channelNumLoc{$1}] = $2 . ' - ' . $3;			
					#$::d_plugins && msg("SiriusRadio: Saving channel $1 -  Location $channelNumLoc{$1} is $2-$3\n");
				}
			}
		}
		elsif ($titleSource == 0) { #itsonsirus.net
			my @ary=split /\n/,$content; #break large string into array

			my $channelNum;
			my $artist = '';
			my $song = '';
			for (@ary) {
				if (/artist(\d+)'>(.*)\s/) {			
					$channelNum = $1;
					$artist = $2;
				}
				elsif (/song\d+'>(.*)\s/) {
					$song = $1;
					
					for ($artist) {
						s/&amp;/&/;
					}
					
					if (defined($channelNumLoc{$channelNum})) {  #Make sure the channel is one that is available online
						$channels[9][$channelNumLoc{$channelNum}] = $artist . ' - ' . $song;			
					}
					
					#Wipe variables "just in case"
					$channelNum ='';
					$artist='';
					$song='';
				}
			}
		}
		else { #dogstarradio
			my $channelNum;
			my $artist;
			my $song;
			
			my @ary=split /---\n/,$content; #break large string into array of channels
			
			for (@ary) {
				if (/^(\d+)\n.+\n(.*)\n(.*)\n/) {
					$channelNum = $1;
					#$::d_plugins && msg("SiriusRadio: ***** $1 $2 $3\n");
					$artist = $2;
					$song = $3;
				}
				elsif (/^\d+\/.*\n(\d+)\n.+\n(.*)\n(.*)\n/) {#Covers first line which includes the timestamp
					$channelNum = $1;
					#$::d_plugins && msg("SiriusRadio: ***** $1 $2 $3\n");
					$artist = $2;
					$song = $3;				
				}
					
				for ($artist) {
					s/&amp;/&/;
				}
					
				if (defined($channelNumLoc{$channelNum})) {  #Make sure the channel is one that is available online
					$channels[9][$channelNumLoc{$channelNum}] = $artist . ' - ' . $song;			
				}
					
				#Wipe variables "just in case"
				$channelNum ='';
				$artist='';
				$song='';
			}
		}		
	}

	if(( $lastInteraction + 900) > Time::HiRes::time() ) {
		#User has had interaction in the last 15minutes
			Slim::Utils::Timers::killTimers($client, \&getTitle); #Kill an existing timer if there is one				
			#Create timer to retrieve title in 10seconds
			Slim::Utils::Timers::setTimer($client,
													Time::HiRes::time() + 10,
													\&getTitle);	
	}
	else {	
		$log->info("No user interaction.  No longer refreshing song info.");

		Slim::Utils::Timers::killTimers($client, \&getStillListening); #Kill still listening timer since no one is browsing
	}

	#Check for dead streams
	foreach my $key (Slim::Player::Client::clients()) {
		my $currentSong = Slim::Player::Playlist::song($key);
		my $currentMode = Slim::Player::Source::playmode($key);
		my $currentTime = Slim::Player::Source::songTime($key);	
		if (defined($currentSong)) {  #Make sure there's a URL
			if ($currentSong->url eq $nowPlaying{$key} && $currentMode eq 'play') {
				if ($currentTime >0) { #Stream is actively playing
					$nowPlayingTime{$key} = $currentTime;
				}
				elsif ($currentTime == 0 && $nowPlayingTime{$key} >0) { #Stream played previously but appears to have stopped
					#Restart stream
					$log->info("Dead stream detected. Restarting stream.");
					my $channelNum = $channels[0][$nowPlayingRef{$key}];
					addSiriusURL($key, $channelNum, 'play');
				}
			}
		}
	}
}

sub getPassword {
	my $password = $prefs->get('plugin_siriusradio_password');
	if (defined $password) {
		$password = unpack('u', $password);
	}

	#Passwords are sent to Sirius using MD5 encryption
	return md5_hex($password);
}

sub webPages {
	my %pages = (
		"index\.(?:htm|xml)" => \&handleIndex,
	);

	Slim::Web::Pages->addPageLinks('radios', { 'PLUGIN_SIRIUSRADIO' => 'plugins/SiriusRadio/index.html' });
	Slim::Web::Pages->addPageLinks('icons', { 'PLUGIN_SIRIUSRADIO' => 'plugins/SiriusRadio/html/images/sirius5.png' });
	Slim::Web::HTTP::addPageFunction("plugins/SiriusRadio/index.html", \&Plugins::SiriusRadio::Plugin::handleIndex);

	return (\%pages, undef);
}

sub handleIndex {
   my ($client, $params) = @_;
   
   #There has been some user interaction...
	lastInteractionUpdate($client);

   my $body = "";

	my $action = $params->{'action'};
	my $streamID = $params->{'streamID'};
	my $genreID = $params->{'genreID'};
		
	#if ($loggedIn == 0 && $dataRequests == 0) { #Make sure not already in the process of logging in
	#	getToken($client);
	#}	
	#if ($totalStations == 0 && $dataRequests == 0 && $webMessage{$client} ne 'Retrieving channel data...' && $loggedIn == 1) {
	if ($totalStations == 0 && $dataRequests == 0 && $webMessage{$client} ne 'Retrieving channel data...') {
		$webMessage{$client}='Retrieving channel data...';
		$webRefresh{$client} = 2;

		getCategories($client); #BUG-- Does this handle all possibilities???
	}

	if (defined($action)) {	#Make sure action is defined, otherwise perl will complain about it being uninitialized
		if ($action eq 'play' || $action eq 'add') {
			$log->info("Web action: $action");
			$selectedChannel{$client} = $streamID;
			$nowPlayingRef{$client}=$streamID; #Needed so that web interface is updated quick enough
			
			my $channelNum = $channels[0][$streamID];
			addSiriusURL($client, $channelNum, $action);
	   }
	}

	if (defined $params->{'addPreset'}) {
   	$log->info("Adding channel " . $params->{'addPrest'} . " to presets...");
   	my @presets = @{ $prefs->get('plugin_siriusradio_presets') || [] };
   	push(@presets, $params->{'addPreset'});
   	$prefs->set('plugin_siriusradio_presets', \@presets);
   }

			my $currentSong;
			my $currentMode;
			
			if (defined($client)) {
				$currentSong = Slim::Player::Playlist::song($client);
				$currentMode = Slim::Player::Source::playmode($client);
			}

			if (defined($currentSong) && defined($currentMode) && defined($nowPlayingRef{$client})) { #Make sure there's actually a song defined otherwise will get perl eq comparison warnings
				if ($currentSong->url eq $nowPlaying{$client} && $currentMode eq 'play') {
					$params->{'playing'} = 1;
					$params->{'icon'} = $channels[0][$nowPlayingRef{$client}];
					$params->{'channel'} = $channels[1][$nowPlayingRef{$client}];
					$params->{'song'} = $channels[9][$nowPlayingRef{$client}];
				}
				else {
					$params->{'playing'} = 0;
				}
			}
			else {
				$params->{'playing'} = 0;
			}
   
	if (defined $params->{'menulevel'}) {
    	my $menuLevel = $params->{'menulevel'};

		if ($menuLevel == 1) { #GENRES
			if (not defined($genreID)) { #ALL GENRES
				my %channelGenreListHash = ();
				my $i=0;
				while ($i <$totalStations) {
					if ($channels[4][$i] eq 'MUSIC') {
						$channelGenreListHash{$channels[6][$i]} = $channels[7][$i];	
					}
					
					$i++;
				}
				
				#Manually add genres
				$channelGenreListHash{'Howard Stern'} = 'specials';
				$channelGenreListHash{'News'} = 'catnews';
				$channelGenreListHash{'Comedy'} = 'comedy';
				$channelGenreListHash{'Sports'} = 'sports';
				$channelGenreListHash{'Family & Health'} = 'catfamilykid';
				$channelGenreListHash{'Talk/Entertainment'} = 'cattalk';
				
				my @sorted = sort keys %channelGenreListHash;
				$params->{'stationList'} = \%channelGenreListHash;
			}
			else { #SPECIFIC GENRE
				my %channelGenreHash = ();
				my $i=0;
				while ($i <$totalStations) {
					if ($channels[7][$i] eq $genreID) { 
						$channelGenreHash{$channels[1][$i]} = $i;
						$params->{'genreName'} = $channels[6][$i]; #Figure out genre full name for top of page navigation
					}
					elsif ($genreID eq 'specials' && $channels[4][$i] eq 'HOWARD STERN') {
						$channelGenreHash{$channels[1][$i]} = $i;
						$params->{'genreName'} = 'Howard Stern'; #For top of page navigation
					}
					elsif ($genreID eq 'catnews' && $channels[4][$i] eq 'NEWS') {
						$channelGenreHash{$channels[1][$i]} = $i;
						$params->{'genreName'} = 'News'; #For top of page navigation
					}
					elsif ($genreID eq 'comedy' && $channels[4][$i] eq 'COMEDY') {
						$channelGenreHash{$channels[1][$i]} = $i;
						$params->{'genreName'} = 'Comedy'; #For top of page navigation
					}
					elsif ($genreID eq 'sports' && $channels[4][$i] eq 'SPORTS') {
						$channelGenreHash{$channels[1][$i]} = $i;
						$params->{'genreName'} = 'Sports'; #For top of page navigation
					}					
					elsif ($genreID eq 'catfamilykid' && $channels[4][$i] eq 'FAMILY & HEALTH') {
						$channelGenreHash{$channels[1][$i]} = $i;
						$params->{'genreName'} = 'Family & Health'; #For top of page navigation
					}										
					elsif ($genreID eq 'cattalk' && $channels[4][$i] eq 'TALK/ENT') {
						$channelGenreHash{$channels[1][$i]} = $i;
						$params->{'genreName'} = 'Talk/Entertainment'; #For top of page navigation
					}															
					$i++;
				}
				
				my @sortedGenres = sort keys %channelGenreHash;
				$params->{'stationList'} = \@sortedGenres;
				$params->{'stationRefs'} = \%channelGenreHash;
				$params->{'nowPlayingRef'} = $nowPlayingRef{$client};
			}
		}
    	elsif ($menuLevel == 2) { #NAMES
    		my %channelHash = ();
	 		my $i=0;
	 		while ($i <$totalStations) {
	 			$channelHash{$channels[1][$i]} = $i;
	 			$i++;
	 		}
	 		
	 		my @sorted = sort keys %channelHash;
   		$params->{'stationList'} = \%channelHash;
   		$params->{'nowPlayingRef'} = $nowPlayingRef{$client};
    	}
    	elsif ($menuLevel == 3) { #NUMBER
    		my %channelHash = ();
			my $i=0;
			while ($i <$totalStations) {
				$channelHash{$channels[0][$i].'. '. $channels[1][$i]} = $i;
				$i++;
			}
			
			my @sorted = sort by_number keys %channelHash;
		
			$params->{'stationList'} = \@sorted;
			$params->{'stationRefs'} = \%channelHash;
			$params->{'nowPlayingRef'} = $nowPlayingRef{$client};
    	}
    	elsif ($menuLevel == 4) { #CHANNEL DETAIL
    		$params->{'channelNumber'}= $channels[0][$streamID];
    		$params->{'channelName'} = $channels[1][$streamID];
    		$params->{'channelDesc'} = $channels[3][$streamID];
    		
    		if ($channels[4][$streamID] eq 'HOWARD STERN') {
    			$params->{'channelGenre'} = 'Howard Stern';
    		}
    		elsif ($channels[4][$streamID] eq 'NEWS') {
    			$params->{'channelGenre'} = 'News';
    		}
    		elsif ($channels[4][$streamID] eq 'COMEDY') {
    			$params->{'channelGenre'} = 'Comedy';
    		}
    		elsif ($channels[4][$streamID] eq 'SPORTS') {
    			$params->{'channelGenre'} = 'Sports';
    		}
    		elsif ($channels[4][$streamID] eq 'FAMILY & HEALTH') {
    			$params->{'channelGenre'} = 'Family & Health';
    		}    		
    		elsif ($channels[4][$streamID] eq 'TALK/ENT') {
    			$params->{'channelGenre'} = 'Talk/Entertainment';
    		}    		    		
    		else {
    			$params->{'channelGenre'} = $channels[6][$streamID];
    		}
    		
    		
    		if ($channels[9][$streamID] ne '') {
    			$params->{'lastSong'} = $channels[9][$streamID];
    		}
    		else {
    			$params->{'lastSong'} = '<i>Not Available</i>';
    		}

			#Add Amazon link
			my $artist = $channels[9][$streamID];
			$artist =~ m/(.*) - /;
			$artist = $1;
			$artist =~ s/ /%20/g;
			$params->{'amazon'} = '<iframe src="http://rcm.amazon.com/e/cm?t=wwwgregbrowne-20&o=1&p=13&l=st1&mode=music&search=' . $artist . '&fc1=&lt1=&lc1=&bg1=&f=ifr" marginwidth="0" marginheight="0" width="468" height="60" border="0" frameborder="0" style="border:none;" scrolling="no"></iframe>';
    	}
    	elsif ($menuLevel == 5) { #NOW PLAYING
    		my %channelHash = ();
			my $i=0;
			while ($i <$totalStations) {
	    		if (defined($channels[9][$i])) {
	    			$channelHash{$channels[0][$i].'. '. $channels[9][$i]} = $i;
	    		}
	    		elsif ($channels[0][$i] != 98 && $channels[0][$i] != 143) { #Channels would appear twice because theyre in the directory twice
	    			$channelHash{$channels[0][$i].'. <i>Not Available</i>'} = $i;
	    		}

				$i++;
			}
			
			my @sorted = sort by_number keys %channelHash;
		
			$params->{'stationList'} = \@sorted;
			$params->{'stationRefs'} = \%channelHash;
			$params->{'nowPlayingRef'} = $nowPlayingRef{$client};
    	}
    	elsif ($menuLevel == 6) { #PRESETS
    		my @presets = @{ $prefs->get('plugin_siriusradio_presets') || [] };
    		my @presetsDisp;
    		
    		my %channelHash = ();
    		my %channelNum = ();
    		my %channelPlaying = ();
			my $i=0;
			while ($i <@presets) {
				if ($presets[$i]>0) { #Make sure list isnt blank.  WHAT ABOUT INVALID ENTRIES???
					$presetsDisp[$i] = $channels[0][$channelNumLoc{$presets[$i]}].'. '. $channels[1][$channelNumLoc{$presets[$i]}];
					$channelHash{$presetsDisp[$i]} = $channelNumLoc{$presets[$i]};
					$channelNum{$presetsDisp[$i]} = $presets[$i];  #Channel number
					$channelPlaying{$presetsDisp[$i]} = $channels[9][$channelNumLoc{$presets[$i]}];
				}
				$i++;
			}
			
			$params->{'stationList'} = \@presetsDisp;			
			$params->{'stationRefs'} = \%channelHash;
			$params->{'stationNums'} = \%channelNum;
			$params->{'stationPlaying'} = \%channelPlaying;
			$params->{'nowPlayingRef'} = $nowPlayingRef{$client};
    	}
    	elsif ($menuLevel == 7) { #EXTENDED VIEW
    		my %channelHash = ();
    		my %channelNum = ();
			my %channelPlaying = ();
			
			my $i=0;
			while ($i <$totalStations) {
				$channelHash{$channels[0][$i].'. '. $channels[1][$i]} = $i;
				$channelNum{$channels[0][$i].'. '. $channels[1][$i]} = $channels[0][$i];
				$channelPlaying{$channels[0][$i].'. '. $channels[1][$i]} = $channels[9][$i];
				$i++;
			}
			
			my @sorted = sort by_number keys %channelHash;
		    					
			$params->{'stationList'} = \@sorted;			
			$params->{'stationRefs'} = \%channelHash;
			$params->{'stationNums'} = \%channelNum;
			$params->{'stationPlaying'} = \%channelPlaying;
			$params->{'nowPlayingRef'} = $nowPlayingRef{$client};
			
    	}
    	elsif ($menuLevel == 8) { #AUTO REFRESH VIEW
    		my @presets = @{ $prefs->get('plugin_siriusradio_presets') || [] };
    		my @presetsDisp;
    		
    		my %channelHash = ();
    		my %channelNum = ();
    		my %channelPlaying = ();
			my $i=0;
			while ($i <@presets) {
				if ($presets[$i]>0) { #Make sure list isnt blank.  WHAT ABOUT INVALID ENTRIES???
					$presetsDisp[$i] = $channels[0][$channelNumLoc{$presets[$i]}].'. '. $channels[1][$channelNumLoc{$presets[$i]}];
					$channelHash{$presetsDisp[$i]} = $channelNumLoc{$presets[$i]};
					$channelNum{$presetsDisp[$i]} = $presets[$i];  #Channel number
					$channelPlaying{$presetsDisp[$i]} = $channels[9][$channelNumLoc{$presets[$i]}];
				}
				$i++;
			}
			
			$params->{'stationList'} = \@presetsDisp;			
			$params->{'stationRefs'} = \%channelHash;
			$params->{'stationNums'} = \%channelNum;
			$params->{'stationPlaying'} = \%channelPlaying;
			$params->{'nowPlayingRef'} = $nowPlayingRef{$client};
			
			#Add Amazon link
			my $artist = $channels[9][$nowPlayingRef{$client}];
			$artist =~ m/(.*) - /;
			$artist = $1;
			$artist =~ s/ /%20/g;
			$params->{'amazon'} = '<iframe src="http://rcm.amazon.com/e/cm?t=wwwgregbrowne-20&o=1&p=13&l=st1&mode=music&search=' . $artist . '&fc1=&lt1=&lc1=&bg1=&f=ifr" marginwidth="0" marginheight="0" width="468" height="60" border="0" frameborder="0" style="border:none;" scrolling="no"></iframe>';
    	}
    }
    else { #Main menu
    	$params->{'menulevel'} = 0;
    }

	#These are available to every Sirius web page
	$params->{'totalStations'} = $totalStations;
	$params->{'webMessage'} = $webMessage{$client};
	$params->{'webRefresh'} = $webRefresh{$client};
	
	$body = Slim::Web::HTTP::filltemplatefile("plugins/SiriusRadio/index.html", $params);

	return $body;
}

my %functions = (
	'play' => sub  {
		my $client = shift;

		if ($selectedChannel{$client} ne '') {			
			$client->showBriefly( {
				line => [ 'Connecting to: '.$channels[1][$selectedChannel{$client}] ]
			},
			{
				scroll => 1,
				block  => 1,
			} );			
			
			my $channelNum = $channels[0][$selectedChannel{$client}];
			addSiriusURL($client, $channelNum, 'play');
		}
	}
);

sub getFunctions() {
  return \%functions;
}

1;
__END__
