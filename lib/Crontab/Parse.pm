package Crontab::Parse;
use warnings;
use strict;
use Carp qw!carp croak confess cluck!;
use utf8;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw/
    crontab_time
    cron_next
    next_to_english
    parse_crontab
    parse_crontab_file
    cron_time_map
    time_to_english
    to_english
/;
our %EXPORT_TAGS = (
    all => \@EXPORT_OK,
);
our $VERSION = '0.01';
use File::Temp 'tempfile';
use File::Slurper 'read_binary';
use Date::Calc ':all';

my @dows   = qw(Sun Mon Tue Wed Thu Fri Sat);
my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my (%dow2num, %month2num, %num2dow, %num2month);
my %mil2ampm;
@mil2ampm{0 .. 23}
= ('midnight', map($_ . 'am', 1 .. 11), 'noon', map($_ . 'pm', 1 .. 11));

@dow2num{map lc($_), @dows} = (0 .. 6);
push @dows, 'Sun';
@num2dow{0 .. $#dows} = @dows;
@month2num{map lc($_), @months} = (1 .. 12);
@num2month{1 .. 12} = @months;
my $dow = join '|', map quotemeta(lc ($_)), @dows;
my $months = join '|', map quotemeta(lc ($_)), @months;
my(%num2month_long, %num2dow_long);

@num2month_long{1 .. 12} = qw(
    January February March April May June July August September October
    November December
);
@num2dow_long{0 .. 6} = qw(
    Sunday Monday Tuesday Wednesday Thursday Friday Saturday
);
$num2dow_long{7} = 'Sunday';

my $atom = '\d+|(?:\d+-\d+(?:/\d+)?)';
my $atoms = "^(?:$atom)(?:,$atom)*\$";

my %atword = (
    'reboot'   => 'reboot',
    # These values are from man 5 crontab
    'yearly'   => '0 0 1 1 *',
    'annually' => '0 0 1 1 *',
    'monthly'  => '0 0 1 * *',
    'weekly'   => '0 0 * * 0',
    'daily'    => '0 0 * * *',
    'midnight' => '0 0 * * *',
    'hourly'   => '0 * * * *',
    # The following are not in Sean Burke's script but they are
    # mentioned in man 5 crontab.
    'every_minute' => "*/1 * * * *",
    # FreeBSD specific
    'every_second' => 'every_second',
);

# This is a bit confusing, these are minimum value (i.e. is it
# numbered from 0 or 1) followed by number of values allowed. Maximum
# allowed = sum of the two things - 1.

our %limits = (
    minute => [0, 60],
    hour => [0, 24],
    dom => [1, 31],
    dow => [0, 7],
    month => [1, 12],
);

# From man 5 crontab again.

our @env = (qw!
    HOME
    LOGNAME
    MAILFROM
    MAILTO
    PATH
    SHELL
    USER
!);

our %env_ok;

for (@env) {
    $env_ok{$_} = 1;
}

our @names = (qw!minute hour dom month dow!);

sub parse_crontab
{
    parse_crontab_file (undef, @_);
}

sub parse_crontab_file
{
    my ($file, %options) = @_;
    # System crontab, has user name as well.
    my $system = $options{system};
    if ($system) {
	delete $options{system};
    }
    my $strip = $options{strip};
    if ($strip) {
	delete $options{strip};
    }
    my $text = $options{text};
    if ($text) {
	delete $options{text};
    }
    elsif ($file) {
	$text = read_binary ($file);
    }
    else {
	$text = crontab_l ();
    }
    for my $k (%options) {
	carp "Unknown option $k";
	delete $options{$k};
    }
    my @output;
    if (! $text) {
	carp "Crontab is empty";
	return @output;
    }
    my @lines = split /\n/, $text;
    if (scalar (@lines) == 0) {
	carp "Crontab is empty";
	return @output;
    }
    my $n = 0;
    for my $line (@lines) {
	$n++;
	my %out = (
	    text => $line,
	    line => $n,
	);
	push @output, \%out;
	if ($line =~ /^#(.*)$/) {
	    $out{type} = 'comment';
	    $out{comment} = $1;
	    if ($strip) {
		pop @output;
	    }
	    next;
	}
	if ($line =~ /^\s*$/) {
	    $out{type} = 'blank';
	    if ($strip) {
		pop @output;
	    }
	    next;
	}
	my $k;
	my $v;
	if ($line =~ m/^([^= \t]+)[ \t]*=[ \t]*\"(.*)\"[ \t]*$/s ) {
	    # NAME = "VALUE"
	    ($k, $v) = ($1, $2);
	    $k =~ s/[ \t]+$//;
	}
	elsif ($line =~ m/^([^= \t]+)[ \t]*=[ \t]*\'(.*)\'[ \t]*$/s ) {
	    # NAME = 'VALUE'
	    ($k, $v) = ($1, $2);
	}
	elsif ($line =~ m/^([^= \t]+)[ \t]*=(.*)/s ) {
	    # NAME = VALUE
	    ($k, $v) = ($1, $2);
	    $v =~ s/^[ \t]+//;
	}
	if ($k && $v) {
	    $out{name} = $k;
	    $out{value} = $v;
	    $out{type} = 'env';
	    if (! $env_ok{$out{name}}) {
		# We love to nag the users.
		carp "Unknown environment variable '$out{name}'";
	    }
	    next;
	}
	# The time as input
	my $input_time;
	my $time;
	my $command;
	if ($line =~ m/^(\@(\w+))[ \t]+(.*)/ &&
	    exists $atword{lc $2}) {
	    $input_time = $1;
	    my $w = lc $2;
	    $time = $atword{$w};
	    $command = $3;
	}
	elsif ($line =~ m/^\s*((?:\S+\s+){4}\S+)\s+(.*)$/) {
	    $input_time = $1;
	    $time = $1;
	    $command = $2;
	}
	if ($time && $command) {
	    $out{time} = $input_time;
	    $out{type} = 'job';
	    if ($system) {
		($out{user}, $out{command}) = split /\s+/, $command, 2;
	    }
	    else {
		$out{command} = $command;
	    }
	    time_to_segments (\%out, $time);
	    next;
	}
	warn "$n: Unparseable line \"$line\"\n";
    }
    return @output;
}

sub crontab_l
{
    my ($fh, $temp) = tempfile ();
    close $fh or die $!;
    my $status = system ("crontab -l > $temp");
    if ($status != 0) {
	carp "crontab -l failed: $?";
	return undef;
    }
    if (! -f $temp) {
	carp "crontab -l did not produce output";
	return undef;
    }
    my $text = read_binary ($temp);
    unlink $temp or die $!;
    return $text;
}

sub time_to_segments
{
    my ($out, $time) = @_;
    if ($time eq 'reboot' || $time eq 'every_second') {
	$out->{special} = $time;
	return;
    }
    # For error messages.
    my $line = $out->{line};
    my @bits = split /\s+/, $time;
    if (scalar (@bits) != 5) {
	warn "Wrong number of time elements in '$time'.\n";
	return;
    }
    for (my $i = 0; $i < 5 ; ++$i) {
	my $name = $names[$i];
	my $b = $bits[$i];
	my ($min, $n) = @{$limits{$name}};
	my $max = $min + $n - 1;
	if ($name eq 'month') {
	    $b =~ s!($months)!$month2num{lc ($1)}!gi;
	}
	if ($name eq 'dow') {
	    $b =~ s!-sun!-7!;
	    $b =~ s!($dow)!$dow2num{$1}!gi;
	}
	my @segments;
	$out->{$name} = \@segments;
	if ($b eq '*') {
	    push @segments, {
		type => 'each',
	    };
	    next;
	}
	if ($b =~ m<^\*/(\d+)$>s) {
	    my $step = $1;
	    if ($step < 1 || $step > $max) {
		carp "Bad step $step";
		return undef;
	    }
	    push @segments, {
		type => 'every',
		step => $step,
	    };			# */3
	    next;
	}
	if ($b =~ m/$atoms/ois) {
	    foreach my $thang (split ',', $b) {
		if ($thang =~ m<^(?:(\d+)|(?:(\d+)-(\d+)(?:/(\d+))?))$>s) {
		    if (defined $1) {
			my $value = $1;
			if ($value < $min || $value > $max) {
			    carp "Bad $name $value";
			    return undef;
			}
			push @segments, {
			    type => 'single',
			    value => $value,
			};	# "7"
		    }
		    elsif (defined $4) {
			my $start = $2;
			my $end = $3;
			my $step = $4;
			if ($start < $min || $start > $max) {
			    carp "Bad $name start $start";
			    return undef;
			}
			if ($end < $min || $start > $max) {
			    carp "Bad $name end $end";
			    return undef;
			}
			if ($step < $min || $step > $max) {
			    carp "Bad $name step $step";
			    return undef;
			}
			push @segments, {
			    type => 'range-every',
			    start => $2,
			    end => $3,
			    step => $4,
			};	# "3-20/4"
		    }
		    else {
			my $start = $2;
			my $end = $3;
			if ($start < $min || $start > $max) {
			    carp "Bad $name start $start";
			    return undef;
			}
			if ($end < $min || $start > $max) {
			    carp "Bad $name end $end";
			    return undef;
			}
			push @segments, {
			    type => 'range',
			    start => $2,
			    end => $3,
			};	# "3-20"
		    }
		    next;
		}
		warn "$line: Unparseable time element '$thang'.\n";
	    }
	    next;
	}
	warn "$line: Unparseable time element $i '$b'.\n";
    }
}

sub crontab_time
{
    my ($out) = @_;
    if ($out->{special}) {
	return "\@$out->{special}";;
    }
    my $r = '';
    for my $name (@Crontab::Parse::names) {
	my $time = $_->{$name};
	my $ntime = $#$time;
	for my $i (0..$ntime) {
	    my $el = $time->[$i];
	    my $t = $el->{type};
	    if ($t eq 'single') {
		$r .= $el->{value};
	    }
	    elsif ($t eq 'each') {
		$r .= '*';
	    }
	    elsif ($t eq 'every') {
		$r .= "*/$el->{step}";
	    }
	    elsif ($t eq 'range') {
		$r .= "$el->{start}-$el->{end}";
	    }
	    elsif ($t eq 'range-every') {
		$r .= "$el->{start}-$el->{end}/$el->{step}";
	    }
	    if ($i < $ntime) {
		$r .= ',';
	    }
	}
	$r .= "\t";
    }
    return $r;
}

sub to_english
{
    my ($line) = @_;
    my $r = undef;
    if (ref $line ne 'HASH') {
	carp "Input value is not a line of a crontab";
	return $r;
    }
    my $t = $line->{type};
    if (! $t) {
	carp "Unknown line type";
	return $r;
    }
    my $n = $line->{line};
    if (! $n) {
	carp "No line number in input";
	$n = '?';
    }
    $r = "$n: ";
    if ($t eq 'comment') {
	$r .= "comment: $line->{comment}";
	return $r;
    }
    if ($t eq 'env') {
	$r .= "set environment variable '$line->{name}' to value '$line->{value}'";
	return $r;
    }
    if ($t ne 'job') {
	carp "Unknown line type '$t'";
	return undef;
    }
    $r .= "Do $line->{command}";
    if ($line->{user}) {
	$r .= " as user $line->{user} ";
    }
    $r .= "\n\t";
    $r .= time_to_english ($line);
    return $r;
}

sub time_to_english
{
    my ($line) = @_;
    my $r = '';
    if ($line->{special}) {
	my $s = $line->{special};
	if ($s eq 'reboot') {
	    $r .= 'at reboot';
	    return $r;
	}
	if ($s eq 'every_second') {
	    $r .= 'every second';
	    return $r;
	}
	carp "Unknown special '$s'";
	return $r;
    }
    my $minute = $line->{minute};
    my $mm = scalar (@$minute);
    my $i = 0;
    for my $m (@$minute) {
	$i++;
	my $mt = $m->{type};
	if ($mt eq 'each' || ($mt eq 'every' && $m->{step} == 1)) {
	    $r .= 'every minute';
	}
	elsif ($mt eq 'every') {
	    $r .= "every $m->{step} minutes";
	}
	elsif ($mt eq 'single') {
	    $r .= "at $m->{value} minutes";
	}
	elsif ($mt eq 'range') {
	    $r .= "from $m->{start} to $m->{end} minutes";
	}
	elsif ($mt eq 'range-every') {
	    $r .= "every $m->{step} minutes between $m->{start} to $m->{end} minutes past";
	}
	else {
	    carp "Unknown minute type $mt";
	}
	if ($i < $mm) {
	    $r .= ' and ';
	}
    }
    $r .= ' ';
    my $hour = $line->{hour};
    my $hh = scalar (@$hour);
    my $j = 0;
    for my $h (@$hour) {
	$j++;
	my $ht = $h->{type};
	if ($ht eq 'each' || ($ht eq 'every' && $h->{step} == 1)) {
	    $r .= "every hour";
	}
	elsif ($ht eq 'every') {
	    $r .= "every $h->{step} hours";
	}
	elsif ($ht eq 'single') {
	    $r .= "past $h->{value} o'clock";
	}
	if ($j < $hh) {
	    $r .= ' and ';
	}
    }
    my $dow = $line->{dow};
    for my $d (@$dow) {
	my $dt = $d->{type};
	if ($dt eq 'single') {
	    $r .= " on " . $num2dow_long{$d->{value}};
	}
    }
    my $dom = $line->{dom};
    for my $d (@$dom) {
	my $dt = $d->{type};
	if ($dt eq 'single') {
	    $r .= " on the " . $d->{value} . "th ";
	}
    }
    my $month = $line->{month};
    for my $m (@$month) {
	my $mt = $m->{type};
	if ($mt eq 'single') {
	    $r .= " in " . $num2month_long{$m->{value}};
	}
    }
    return $r;
}

sub cron_run
{
    my ($map, $now) = @_;
    my ($mo, $dom, $dow, $h, $mi) = @{$now}{qw!month dom dow hour minute!};
    if ($map->{month}[$mo] && ($map->{dom}[$dom] || $map->{dow}[$dow]) &&
	$map->{hour}[$h] && $map->{minute}[$mi]) {
	return 1;
    }
    return undef;
}

sub dow
{
    my $dow = Day_of_Week (@_);
    if ($dow == 7) {
	$dow = 0;
    }
    return $dow;
}

sub cron_next
{
    my ($map, $now) = @_;
    if (! defined $now) {
	my %now;
	@now{qw!year month dom hour minute sec doy dow dst!} = System_Clock ();
	die unless defined $now{dow};
	$now = \%now;
	# Convert from Date::Calc to our conventions
	if ($now->{dow} == 7) {
	    $now->{dow} = 0;
	}
    }
    if (! defined $now->{dow}) {
	$now->{dow} = dow ($now->{year}, $now->{month}, $now->{dom});
    }
    # Set to a true value to skip one case.
    my $skip;
    if (cron_run ($map, $now)) {
	$skip = 1;
    }
    my %next;
    my $year = $now->{year};
    # We have to cycle around to this month again to deal with yearly
    # jobs.
    my @months = ($now->{month}..12, 1..$now->{month});
    for my $month (@months) {
	my $is_first_month = ($year == $now->{year} &&
			      $month == $now->{month});
	if (! $is_first_month && $month == 1) {
	    $year++;
	}
	if (! $map->{month}[$month]) {
	    next;
	}
	my $first_dom = 1;
	if ($is_first_month) {
	    $first_dom = $now->{dom};
	}
	my $last_dom = Days_in_Month ($year, $month);
	my @doms = ($first_dom..$last_dom);
	for my $dom (@doms) {
	    my $is_first_dom = 0;
	    if ($is_first_month && $dom == $first_dom) {
		$is_first_dom = 1;
	    }
	    my $dow = dow ($year, $month, $dom);
	    if (! $map->{dom}[$dom] && ! $map->{dow}[$dow]) {
		next;
	    }
	    my $first_hour = 0;
	    my $last_hour = 23;
	    if ($is_first_month && $is_first_dom) {
		$first_hour = $now->{hour};
	    }
	    my @hours = ($first_hour..$last_hour);
	    for my $hour (@hours) {
		if (! $map->{hour}[$hour]) {
		    next;
		}
		my $is_first_hour = 0;
		if ($is_first_month && $is_first_dom && $hour == $first_hour) {
		    $is_first_hour = 1;
		}
		my $first_minute = 0;
		my $last_minute = 59;
		if ($is_first_hour) {
		    $first_minute = $now->{minute};
		}
		my @minutes = ($first_minute..$last_minute);
		for my $minute (@minutes) {
		    if ($map->{minute}[$minute]) {
			if ($skip) {
			    $skip = 0;
			    next;
			}
			return {
			    year => $year,
			    month => $month,
			    dom => $dom,
			    dow => $dow,
			    hour => $hour,
			    minute => $minute,
			};
		    }
		}
	    }
	}
    }
    return undef;
}

sub cron_time_map
{
    my ($line, $dump_map) = @_;
    my %map;
    my $dow_each;
    my $dom_each;
    for my $k (keys %limits) {
	my $lim = $limits{$k};
	my $min = $lim->[0];
	my $n = $lim->[1];
	my $max = $n + $lim->[0];
	my @map = (0) x $max;
	if (! $line->{$k}) {
	    carp "Line has no rules for time field '$k'";
	    return undef;
	}
	for my $rule (@{$line->{$k}}) {
	    my $t = $rule->{type};
	    if ($t eq 'each') {
		# If the DOW is "*", and we put 1, 1, ..., 1, in the
		# DOW field, the cron job runs every day of the week,
		# which is wrong: if DOW is unspecified, cron decides
		# whether to run on the basis of whether DOM is true
		# or not.
		if ($k eq 'dow') {
		    $dow_each = 1;
		}
		elsif ($k eq 'dom') {
		    $dom_each = 1;
		}
		else {
		    @map = ((0) x $min, (1) x $n);
		}
		last;
	    }
	    if ($t eq 'every') {
		# The fill is up to and including $end, so use $max -
		# 1 here.
		fill (\@map, $min, $max - 1, $rule->{step});
		next;
	    }
	    if ($t eq 'single') {
		$map[$rule->{value}] = 1;
		next;
	    }
	    if ($t eq 'range-every') {
		fill (\@map, $rule->{start}, $rule->{end}, $rule->{step});
		next;
	    }
	    if ($t eq 'range') {
		fill (\@map, $rule->{start}, $rule->{end}, 1);
		next;
	    }
	    carp "Unknown type of time '$t'";
	    return undef;
	}
	if ($k eq 'dow' && $map[7]) {
	    $map[0] = $map[7];
	    pop @map;
	}
	if (scalar (@map) > $max) {
	    confess sprintf ("Wrong length of \@map %d > %d for %s",
			     scalar (@map), $max, $k);
	}
	if ($limits{$k}[0] > 0 && $map[0] != 0) {
	    die "Bad non-zero entry in \$map[0] for $k";
	}
	if ($dump_map) {
	    print "$k: @map\n";
	}
	$map{$k} = \@map;
    }
    if ($dom_each && $dow_each) {
	$map{dom} = [(0) x $limits{dom}[0], (1) x $limits{dom}[1]];
	if ($dump_map) {
	    print "dom adjusted: @{$map{dom}}\n";
	}
    }
    return \%map;
}

sub fill
{
    my ($map, $start, $end, $step) = @_;
    # The fill is up to and including $end.
    for (my $i = $start; $i <= $end; $i += $step) {
	$map->[$i] = 1;
    }
}

sub next_to_english
{
    my ($next) = @_;
    my $time = sprintf ("%02d:%02d", $next->{hour}, $next->{minute});
    my $month = $num2month_long{$next->{month}};
    my $dow = $num2dow_long{$next->{dow}};
    my $eng = "$dow $next->{dom} $month at $time";
    return $eng;
}

1;
