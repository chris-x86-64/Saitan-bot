#!/usr/bin/perl

use strict;
use warnings;
use Encode;
use utf8;
use AnyEvent::Twitter::Stream;    # Handles Userstream API
require 'lib/functions.pl';       # Package name is "BotFunctions"
require 'lib/textdata.pl';        # Puts analyzed tweets into MySQL
binmode STDOUT, ":utf8";          # All output will be UTF-8

# my $connected = 0;
# Initiate Userstream
my $done = AE::cv;                # Handles event condition

my $stream = AnyEvent::Twitter::Stream->new(
        &BotFunctions::oauth_keys_stream,
        ANYEVENT_TWITTER_STREAM_SSL => 1,
        method                      => "userstream",
        on_connect                  => sub {

                &BotFunctions::wakeup;
        },
        on_tweet => sub {
                my $tweet = shift;
                my $text  = decode_utf8( $tweet->{text} );
                &BotFunctions::react($tweet);
                &TextData::add_data($text);
        },
        on_event => sub {
                my $event = shift;
                &BotFunctions::refollow($event);
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

&BotFunctions::talk_randomly;

$done->recv;
