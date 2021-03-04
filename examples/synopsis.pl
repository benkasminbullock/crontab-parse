#!/home/ben/software/install/bin/perl
use warnings;
use strict;
use Crontab::Parse 'parse_crontab_file';
my @lines = parse_crontab_file ('/etc/crontab', strip => 1, system => 1);
for (@lines) {
    if ($_->{type} eq 'job') {
	print $_->{command}, "\n";
    }
}

