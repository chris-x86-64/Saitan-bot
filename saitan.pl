#!/usr/bin/perl

use strict;
use warnings;
use Encode;
use utf8;
use AnyEvent::Twitter::Stream;
use lib './lib';
use SaitanBot;
binmode STDOUT, ":utf8";

my $done = AE::cv;

my $saitan = SaitanBot->new;

my $stream = AnyEvent::Twitter::Stream->new(
    $saitan->oauth_keys_stream,
    ANYEVENT_TWITTER_STREAM_SSL => 1,
    method                      => "userstream",
    on_connect                  => sub {
#        $saitan->wakeup;
    },
    on_tweet => sub {
        my $tweet = shift;
    	$saitan->react($tweet) unless (!$tweet->{id});
    },
    on_event => sub {
        my $event = shift;
    	$saitan->refollow($event->{source}->{userid};
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

$saitan->talk;

$done->recv;
