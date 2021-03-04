#!/home/ben/software/install/bin/perl
use warnings;
use strict;
use Crontab::Parse 'parse_crontab';
use JSON::Create 'create_json';
my $crontab =<<EOF;
# Save some entropy so that /dev/random can re-seed on boot.
*/11    *       *       *       *       operator /usr/libexec/save-entropy
# Adjust the time zone if the CMOS clock keeps local time, as opposed to
# UTC time.  See adjkerntz(8) for details.
1,31    0-5     *       *       *       root    adjkerntz -a
15 03 * * *	/home/ben/websites/common/bin/get_logs.pl www.sljfaq.org www.lemoda.net qhanzi qrpng nxmnpg
45 2,6,10,14,18,22 * * *	/home/ben/websites/kanji/bin/get-nfs-kanji-inputs.pl
EOF
my @lines = parse_crontab (text => $crontab, strip => 1);
print create_json (\@lines, indent => 1, sort => 1);
