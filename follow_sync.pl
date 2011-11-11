#!/usr/bin/perl

use strict;
use warnings;
use Net::Twitter::Lite;
use YAML::Syck;
use Data::Dumper;

my $conf =
  YAML::Syck::LoadFile('config.yml');  # Loads OAuth keys from YAML

# Initiate Twitter-API methods
my $actions = new Net::Twitter::Lite(
    consumer_key        => $conf->{oauth}->{consumer_key},
    consumer_secret     => $conf->{oauth}->{consumer_secret},
    access_token        => $conf->{oauth}->{access_token},
    access_token_secret => $conf->{oauth}->{access_token_secret},
    ssl                 => 1,
    traits              => [qw/API::REST OAuth WrapError/],
);

my @followers = @{$actions->followers_ids->{ids}};
my @following = @{$actions->following_ids->{ids}};
my (%incoming, %outgoing);

@incoming{@followers} = @followers;
delete @incoming{@following};
@outgoing{@following} = @following;
delete @outgoing{@followers};

print "To newly follow --- \n" . join(",\n", keys %incoming);
print "\n";
print "To quit following --- \n" . join(",\n", keys %outgoing);
$actions->create_friend({user_id => $_}) foreach (keys %incoming);
$actions->destroy_friend({user_id => $_}) foreach (keys %outgoing);
