package SaitanBot;

use strict;
use warnings;
use Encode;
use utf8;
use Net::Twitter::Lite;
use YAML::Syck;
use AnyEvent;
require 'Data/Data.pm';

# Read OAuth keys from the (UTF-8) config file
local $YAML::Syck::ImplicitUnicode = 1;

sub new {
	my($class, $opt) = @_;

	my $conf = YAML::Syck::LoadFile('config.yml');

	my $self = bless {
		conf    => $conf,
		
		# Initiate Twitter-API methods
		actions => Net::Twitter::Lite->new(
			consumer_key        => $conf->{oauth}->{consumer_key},
			consumer_secret     => $conf->{oauth}->{consumer_secret},
			access_token        => $conf->{oauth}->{access_token},
			access_token_secret => $conf->{oauth}->{access_token_secret},
			ssl                 => 1,
			traits              => [qw/API::REST OAuth WrapError/],
		),

		# Boolean - Whether hitted the daily update limit or not
		limit    => 0,
		favlimit => 0,

	}, $class;

	# Gets user data
	$self->{whoami} = $self->{actions}->verify_credentials;

	return $self;
}

# Gives OAuth keys to AnyEvent::Twitter::Stream
sub oauth_keys_stream {
	my $self = shift;

	my $conf = $self->{conf};
	my %oauth = (
		consumer_key    => $conf->{oauth}->{consumer_key},
		consumer_secret => $conf->{oauth}->{consumer_secret},
		token           => $conf->{oauth}->{access_token},
		token_secret    => $conf->{oauth}->{access_token_secret},
	);

	return %oauth;
}

sub wakeup {
	my $self = shift;

	my $status = decode_utf8(
		"こんにちは！さいたんbotがログインしたよ！");
	$self->_talk( $status, undef );
}

sub shutdown {
	my $self = shift;

	my $status = decode_utf8("またね！");
	$self->_talk( $status, undef );
}

# Detects follow then automatically refollow
sub refollow {
	my ($self, $event) = @_;

	# Ignore your own actions
	return unless ( $event->{source}->{id} != $self->{whoami}->{id} );

# Follow the account which has just followed you
	if ( $event->{event} eq 'follow' )
	{
		$self->{actions}->create_friend( {
			user_id => $event->{source}->{id}
		} );

		print "Refollowed $event->{source}->{id}\n";
	}
}

sub react {
	my ($self, $tweet) = @_;
	
	return unless ( defined $tweet->{id} );
	return if ( $tweet->{retweeted_status} );

	my $source_user = $tweet->{user}{screen_name};
	return unless ( $source_user ne $self->{whoami}->{screen_name} );
	
	my $id           = $tweet->{id};
	my $text         = decode_utf8( $tweet->{text} );
	my $is_mentioned = $self->_is_mentioned( $tweet, $source_user );
	my $category     = $self->_check_category( $text, $is_mentioned );

	if ( $category eq 'fav' ) {
		$self->_fav($id);
	}
	else {
		$self->_prepare_reply( $source_user, $id, $category, $is_mentioned );
	}
}

sub add_data {
	my ($self, $tweet) = @_;

	return unless (defined($tweet->{id}) or $tweet->{user}{id} != $self->{whoami});
	my $text = decode_utf8($tweet->{text});
	&SaitanBot::Data::add_data($text);
}

sub _prepare_reply {
	my ( $self, $source_user, $reply_id, $category, $is_mentioned ) = @_;

	my $status = '@' . $source_user . ' ';

	if ( $category eq 'unknown' and $is_mentioned == 0 ) {
		return;
	}
	elsif ( $category eq 'unknown' and $is_mentioned == 1 ) {
		$status .= SaitanBot::Data->markov;
	}
	else {
		my $replies = $self->{conf}->{$category}->{replies};

		my $reply_string = $replies->[ int( rand( scalar @$replies ) ) ];
		$status .= $reply_string;
	}
	$self->_talk( $status, $reply_id );
}

sub _check_category {
	my ( $self, $text, $is_mentioned ) = @_;

	my $conf = $self->{conf};
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

sub _is_mentioned {
	my ( $self, $tweet, $source_user ) = @_;

	foreach my $mention ( @{ $tweet->{entities}{user_mentions} } ) {
		if ( $mention->{screen_name} eq $self->{whoami}->{screen_name} ) {
			print "Detected mention from $source_user.\n";
			return 1;
			last;
		}
	}
	return 0;
}

sub fav {
	my ($self, $tweet) = @_;

	return unless ($tweet->{id});
	my $text = $tweet->{text};
	my $fav_id = $tweet->{id};

	my $conf = $self->{conf};
	return if ( $tweet->{retweeted_status} );

	foreach my $keyword ( @{ $conf->{fav}->{keywords} } ) {
		if ( $text =~ decode_utf8($keyword) ) {
			eval { $self->{actions}->create_favorite($fav_id); };
			if ($@) {
				if ( $@ =~ /favorite per day/ ) {
					$self->_talk(
						decode_utf8("ふぁぼ規制ﾅｰｰｰｰｰｰｰｰｰｰｰｰｰｰ"),
						undef
					);
					$self->{favlimit} = 1;
					warn "$@\n";
				}
				else {
					$self->_talk(
						decode_utf8("ふぁぼ失敗なう＞＜ 当該ID: $fav_id"),
						undef
					);
					warn "$@\n";
				}
			}
			else {
				$self->{favlimit} = 0;
				print "Favorited: $fav_id\n";
				last;
			}
		}
	}
	return;
}

sub _talk {
	#		return if ($limit == 1);
	my ( $self, $status, $reply_id ) = @_;
	eval {
		$self->{actions}->update(
			{
				status                => decode_utf8($status),
				in_reply_to_status_id => $reply_id,
			}
		);
	};
	if ($@) {
		warn "$status ... Could not be posted: $@\n";
		if ( $@ =~ /duplicate/ ) {
			$status .= ' #' . int( rand(256) );
			$self->_talk( $status, $reply_id );
		}
		elsif ( $@ =~ /limit/ ) {
			$self->{limit} = 1;
			$self->_limit;
		}
	}
	else {
		print $status, "\n";
		$self->{limit} = 0;
		return 1;
	}
}

sub talk_randomly {
	my ($self, $wait) = @_;

	$wait = rand( $self->{conf}->{interval} ) unless defined $wait;

	my $cv = AE::cv;
	my $timed;
	$timed = AE::timer(
		$wait, 0,
		sub {
			$self->_talk( SaitanBot::Data->markov, undef );
			undef $timed;
			$cv->send;
		},
	);
	$cv->recv;
	$self->talk_randomly( rand( $self->{conf}->{interval} ) );
}

sub _limit {
	my $self = shift;
	
	my $hashtag = ' #' . int( rand(256) );
	my $cv      = AE::cv;
	my $timer;
	$timer = AE::timer(
		600,
		600,
		sub {
			my $status = $self->_talk( decode_utf8("規制解除てす$hashtag"), undef );

			if ( $status == 1 ) {
				$self->{limit} = 0;
				undef $timer;
				$cv->send;
			}
		},
	);
	$cv->recv;
}
1;
