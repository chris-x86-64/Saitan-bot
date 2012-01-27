#!/usr/bin/perl

use strict;
use warnings;
use Encode;
use utf8;
use AnyEvent::Twitter::Stream;    # Handles Userstream API
use lib './lib';
require 'SaitanBot.pm';
binmode STDOUT, ":utf8";          # All output will be UTF-8

# my $connected = 0;
# Initiate Userstream
my $done = AE::cv;                # Handles event condition

my $saitan = SaitanBot->new();
my $whoami = $saitan->whoami;

my $stream = AnyEvent::Twitter::Stream->new(
    $saitan->oauth_keys_stream,
    ANYEVENT_TWITTER_STREAM_SSL => 1,
    method                      => "userstream",
    on_connect                  => sub {
        $saitan->wakeup;
    },
    on_tweet => sub {
        my $tweet = shift;
        return if (!$tweet->{id});

        if ($tweet->{user}{id} != $whoami and $tweet->{source} !~ /twittbot\.net/) { # ToDo: Configurable ignore settings
			my $text  = decode_utf8( $tweet->{text} );
			$saitan->react($tweet);
			$saitan->fav($tweet);
			$saitan->add_data($tweet);
		}
    },
    on_event => sub {
        my $event = shift;
        $saitan->refollow($event);
    },
    on_error => sub {
        my $error = shift;
        warn "Error: $error\n";
        $done->send;
    },
    on_eof => sub {
        $done->send;
    },
);

$saitan->talk_randomly;

$done->recv;
