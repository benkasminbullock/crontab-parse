#!/home/ben/software/install/bin/perl
use warnings;
use strict;
use Crontab::Parse ':all';
my $tab = '* * * * 5-7 /usr/bin/fortune';
my @lines = parse_crontab (text => $tab);
my $map = cron_time_map ($lines[0]);
print join (' ', @{$map->{dow}}), "\n";
