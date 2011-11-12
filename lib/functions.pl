package BotFunctions;

use strict;
use warnings;
use Encode;
use utf8;
use Net::Twitter::Lite;
use YAML::Syck;
use AnyEvent;
require 'lib/textdata.pl';

# Read OAuth keys from the (UTF-8) config file
local $YAML::Syck::ImplicitUnicode = 1;
my $conf = YAML::Syck::LoadFile('config.yml');

# Initiate Twitter-API methods
my $actions = Net::Twitter::Lite->new(
        consumer_key        => $conf->{oauth}->{consumer_key},
        consumer_secret     => $conf->{oauth}->{consumer_secret},
        access_token        => $conf->{oauth}->{access_token},
        access_token_secret => $conf->{oauth}->{access_token_secret},
        ssl                 => 1,
        traits              => [qw/API::REST OAuth WrapError/],
);

# Gets user data
my $whoami = $actions->verify_credentials;

# Boolean - Whether hitted the daily update limit or not
my $limit    = 0;
my $favlimit = 0;

# Gives OAuth keys to AnyEvent::Twitter::Stream
sub oauth_keys_stream {
        my %oauth = (
                consumer_key    => $conf->{oauth}->{consumer_key},
                consumer_secret => $conf->{oauth}->{consumer_secret},
                token           => $conf->{oauth}->{access_token},
                token_secret    => $conf->{oauth}->{access_token_secret},
        );
        return %oauth;
}

sub wakeup {
        my $status = decode_utf8(
                "こんにちは！さいたんbotがログインしたよ！");
        &talk( $status, undef );
}

sub shutdown {
        my $status = decode_utf8("またね！");
        &talk( $status, undef );
}

# Detects follow then automatically refollow
sub refollow {
        my $event = shift;

        # Ignore your own actions
        return unless ( $event->{source}->{id} != $whoami->{id} );

        # Follow the account which has just followed you
        if ( $event->{event} eq 'follow' ) {
                $actions->create_friend(
                        { user_id => $event->{source}->{id} } );
                print "Refollowed $event->{source}->{id}\n";
        }
}

sub react {
        my $tweet = shift;
        return unless ( defined $tweet->{id} );
        return if ( $tweet->{retweeted_status} );
        my $source_user = $tweet->{user}{screen_name};
        return unless ( $source_user ne $whoami->{screen_name} );
        my $id           = $tweet->{id};
        my $text         = decode_utf8( $tweet->{text} );
        my $is_mentioned = &is_mentioned( $tweet, $source_user );
        my $category     = &check_category( $text, $is_mentioned );

        if ( $category eq 'fav' ) {
                &fav($id);
        }
        else {
                &prepare_reply( $source_user, $id, $category, $is_mentioned );
        }
}

sub prepare_reply {
        my ( $source_user, $reply_id, $category, $is_mentioned ) = @_;
        my $status = '@' . $source_user . ' ';
        if ( $category eq 'unknown' and $is_mentioned == 0 ) {
                return;
        }
        elsif ( $category eq 'unknown' and $is_mentioned == 1 ) {
                $status .= &TextData::markov;
        }
        else {
                my $replies = $conf->{$category}->{replies};
                my $reply_string =
                  $replies->[ int( rand( scalar @$replies ) ) ];
                $status .= $reply_string;
        }
        &talk( $status, $reply_id );
}

sub check_category {
        my ( $text, $is_mentioned ) = @_;
        foreach my $category ( @{ $conf->{categories} } ) {
                foreach my $keyword ( @{ $conf->{$category}->{keywords} } ) {
                        if ( $text =~ decode_utf8($keyword) ) {
                                return $category;
                                last;
                        }
                }
        }
        if ( $is_mentioned == 1 ) {
                foreach my $replyonly ( @{ $conf->{replyonly} } ) {
                        foreach
                          my $keyword ( @{ $conf->{$replyonly}->{keywords} } )
                        {
                                if ( $text =~ decode_utf8($keyword) ) {
                                        return $replyonly;
                                        last;
                                }
                        }
                }
        }
        return "unknown";
}

sub is_mentioned {
        my ( $tweet, $source_user ) = @_;
        foreach my $mention ( @{ $tweet->{entities}{user_mentions} } ) {
                if ( $mention->{screen_name} eq $whoami->{screen_name} ) {
                        print "Detected mention from $source_user.\n";
                        return 1;
                        last;
                }
        }
        return 0;
}

sub fav {
        my $fav_id = shift;
        eval { $actions->create_favorite($fav_id); };
        if ($@) {
                if ( $@ =~ /favorite per day/ ) {
                        &talk(
                                decode_utf8(
"ふぁぼ規制ﾅｰｰｰｰｰｰｰｰｰｰｰｰｰｰ"
                                ),
                                undef
                        );
                        $favlimit = 1;
                        warn "$@\n";
                }
                else {
                        &talk(
                                decode_utf8(
"ふぁぼ失敗なう＞＜ 当該ID: $fav_id"
                                ),
                                undef
                        );
                        warn "$@\n";
                }
        }
        else {
                $favlimit = 0;
                print "Favorited: $fav_id\n";
        }
        return;
}

sub talk {

        #		return if ($limit == 1);
        my ( $status, $reply_id ) = @_;
        eval {
                $actions->update(
                        {
                                status                => $status,
                                in_reply_to_status_id => $reply_id,
                        }
                );
        };
        if ($@) {
                warn "$status ... Could not be posted: $@\n";
                if ( $@ =~ /duplicate/ ) {
                        $status .= ' #' . int( rand(256) );
                        &talk( $status, $reply_id );
                }
                elsif ( $@ =~ /limit/ ) {
                        $limit = 1;
                        &limit;
                }
        }
        else {
                print $status, "\n";
                $limit = 0;
                return 1;
        }
}

sub talk_randomly {
        my $wait = shift;
        $wait = rand( $conf->{interval} ) unless defined $wait;
        my $cv = AE::cv;
        my $timed;
        $timed = AE::timer(
                $wait, 0,
                sub {
                        &BotFunctions::talk( &TextData::markov, undef );
                        undef $timed;
                        $cv->send;
                },
        );
        $cv->recv;
        &talk_randomly( rand( $conf->{interval} ) );
}

sub limit {
        my $hashtag = ' #' . int( rand(256) );
        my $cv      = AE::cv;
        my $timer;
        $timer = AE::timer(
                600, 600,
                sub {
                        my $status =
                          &talk( decode_utf8("規制解除てす$hashtag"),
                                undef );
                        if ( $status == 1 ) {
                                $limit = 0;
                                undef $timer;
                                $cv->send;
                        }
                },
        );
        $cv->recv;
}
1;
