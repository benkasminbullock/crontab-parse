# These tests are from Algorithm::Cron.

use strict;
use warnings;

use Test::More;
use Crontab::Parse ':all';

is_deeply( expand( "*", "sec" ), undef, 'expand sec=*' );
is_deeply( expand( "0", "sec" ), [ 0 ], 'expand sec=0' );
is_deeply( expand( "*/10", "sec" ), [ 0, 10, 20, 30, 40, 50 ], 'expand sec=0/10' );
is_deeply( expand( "5-8", "sec" ), [ 5, 6, 7, 8 ], 'expand sec=5-8' );
is_deeply( expand( "3-17/4", "sec" ), [ 3, 7, 11, 15 ], 'expand sec=3-17/4' );

is_deeply( expand( "*/5", "mday" ), [ 1, 6, 11, 16, 21, 26, 31 ], 'expand mday=*/5' );

is_deeply( expand( "jan", "mon" ), [ 0 ], 'expand mon=jan' );
is_deeply( expand( "mar-sep", "mon" ), [ 2 .. 8 ], 'expand mon=mar-sep' );
is_deeply( expand( "5", "mon" ), [ 4 ], 'expand mon=5' );
is_deeply( expand( "*/3", "mon" ), [ 0, 3, 6, 9 ], 'expand mon=*/3' );

is_deeply( expand( "mon", "wday" ), [ 1 ], 'expand wday=mon' );
is_deeply( expand( "mon-fri", "wday" ), [ 1 .. 5 ], 'expand wday=mon-fri' );
is_deeply( expand( "4", "wday" ), [ 4 ], 'expand wday=4' );
is_deeply( expand( "5-7", "wday" ), [ 0, 5, 6 ], 'expand wday=5-7' );
is_deeply( expand( "thu-sun", "wday" ), [ 0, 4, 5, 6 ], 'expand wday=thu-sun' );

done_testing;

sub expand
{
    my ($field, $type) = @_;
    # We don't support seconds, use these as minute tests.
    if ($type eq 'sec') {
	$type = 'minute';
    }
    if ($type eq 'mday') {
	$type = 'dom';
    }
    if ($type eq 'wday') {
	$type = 'dow';
    }
    if ($type eq 'mon') {
	$type = 'month';
    }
    my $job;
    for my $what (qw!minute hour dom month dow!) {
	if ($type eq $what) {
	    $job .= "$field ";
	}
	else {
	    $job .= "* ";
	}
    }
    $job .= "sudo make me a sandwich\n";
    my @lines = parse_crontab (text => $job);
    my $map = cron_time_map ($lines[0]);
    my $r = $map->{$type};
    my @ret;
    my $every = 1;
    my $start = 0;
    if ($type eq 'month') {
	$start = 1;
    }

    for (my $i = $start; $i <= $#$r; $i++) {
	if ($r->[$i]) {
	    push @ret, $i - $start;
	}
	else {
	    $every = undef;
	}
    }
    if ($every) {
	return undef;
    }
    return \@ret;
}
