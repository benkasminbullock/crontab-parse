#!/home/ben/software/install/bin/perl
use warnings;
use strict;
use Crontab::Parse ':all';
my $tab = <<'EOF';
@weekly ls -l /
1 2 3 jan-jul/2 mon-fri echo "Hello"
EOF
my @lines = parse_crontab (text => $tab);
for (@lines) {
    print crontab_time ($_), "\n";
}
