#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Crontab::Parse ':all';

sub epoch2isogmt
{
    my ($time) = @_;
    my $x = sprintf ("%d-%02d-%02d %02d:%02d:00", 
		     $time->{year}, $time->{month}, $time->{dom},
		     $time->{hour}, $time->{minute});
    return $x;
}


my %start = (
    year => 2012,
    month => 1,
    hour => 0,
    minute => 0,
    dom => 1,
);

my $time = \%start;

is (epoch2isogmt ($time), "2012-01-01 00:00:00", 'epoch2isogmt');

sub list_times
{
    my ( $crontab, $count ) = @_;
    my $fake = "$crontab sudo make me a sandwich\n";
    my @ct = parse_crontab (text => $fake);
    my $map = cron_time_map ($ct[0]);

    my $next = $time;
    my @times;

    for (1 .. $count) {
	$next = cron_next ($map, $next);
	push @times, epoch2isogmt ($next);
    }

    return @times;
}

# is_deeply( [ list_times "* * * * * *", 5 ],
#    [ "2012-01-01 00:00:01",
#      "2012-01-01 00:00:02",
#      "2012-01-01 00:00:03",
#      "2012-01-01 00:00:04",
#      "2012-01-01 00:00:05" ], 'per second' );

is_deeply( [ list_times "* * * * *", 5 ],
   [ "2012-01-01 00:01:00",
     "2012-01-01 00:02:00",
     "2012-01-01 00:03:00",
     "2012-01-01 00:04:00",
     "2012-01-01 00:05:00" ], 'per minute' );

is_deeply( [ list_times "*/10 * * * *", 7 ],
   [ "2012-01-01 00:10:00",
     "2012-01-01 00:20:00",
     "2012-01-01 00:30:00",
     "2012-01-01 00:40:00",
     "2012-01-01 00:50:00",
     "2012-01-01 01:00:00",
     "2012-01-01 01:10:00" ], 'per 10 minutes' );

is_deeply( [ list_times "*/30 5 * * *", 7 ],
   [ "2012-01-01 05:00:00",
     "2012-01-01 05:30:00",
     "2012-01-02 05:00:00",
     "2012-01-02 05:30:00",
     "2012-01-03 05:00:00",
     "2012-01-03 05:30:00",
     "2012-01-04 05:00:00" ], 'per 30 minutes 5th hour' );

# 31st of Feb doesn't exist
is_deeply( [ list_times "0 0 */15 * *", 7 ],
   [ "2012-01-16 00:00:00",
     "2012-01-31 00:00:00",
     "2012-02-01 00:00:00",
     "2012-02-16 00:00:00",
     "2012-03-01 00:00:00",
     "2012-03-16 00:00:00",
     "2012-03-31 00:00:00" ], 'midnight per 15 days' );

is_deeply( [ list_times "0 0 1 3 *", 5 ],
   [ "2012-03-01 00:00:00",
     "2013-03-01 00:00:00",
     "2014-03-01 00:00:00",
     "2015-03-01 00:00:00",
     "2016-03-01 00:00:00" ], 'yearly 1st March' );

is_deeply( [ list_times "0 0 * * mon", 6 ],
   [ "2012-01-02 00:00:00",
     "2012-01-09 00:00:00",
     "2012-01-16 00:00:00",
     "2012-01-23 00:00:00",
     "2012-01-30 00:00:00",
     "2012-02-06 00:00:00" ], 'every Monday' );

is_deeply( [ list_times "0 0 * * thu", 6 ],
   [ "2012-01-05 00:00:00",
     "2012-01-12 00:00:00",
     "2012-01-19 00:00:00",
     "2012-01-26 00:00:00",
     "2012-02-02 00:00:00",
     "2012-02-09 00:00:00" ], 'every Thursday' );

is_deeply( [ list_times "0 0 * * mon-fri", 6 ],
   [ "2012-01-02 00:00:00",
     "2012-01-03 00:00:00",
     "2012-01-04 00:00:00",
     "2012-01-05 00:00:00",
     "2012-01-06 00:00:00",
     "2012-01-09 00:00:00" ], 'Monday-Friday' );

# Mixed mday + wday
is_deeply( [ list_times "15 2 15 * tue", 7 ],
   [ "2012-01-03 02:15:00",
     "2012-01-10 02:15:00",
     "2012-01-15 02:15:00",
     "2012-01-17 02:15:00",
     "2012-01-24 02:15:00",
     "2012-01-31 02:15:00",
     "2012-02-07 02:15:00" ], '02:15 15th or Tuesday' );

# is_deeply( [ list_times "59 59 23 31 01,03 *", 3 ],
#    [ "2012-01-31 23:59:59",
#      "2012-03-31 23:59:59",
#      "2013-01-31 23:59:59" ], 'last second of the month');

is_deeply( [ list_times "00 00 31  * *", 7 ],
   [ "2012-01-31 00:00:00",
     "2012-03-31 00:00:00",
     "2012-05-31 00:00:00",
     "2012-07-31 00:00:00",
     "2012-08-31 00:00:00",
     "2012-10-31 00:00:00",
     "2012-12-31 00:00:00" ], '31st of each month');

done_testing;