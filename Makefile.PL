use strict;
use warnings;
use ExtUtils::MakeMaker;

my $pm = 'lib/Crontab/Parse.pm';
my $pod = 'lib/Crontab/Parse.pod';
my $github = 'github.com/benkasminbullock/crontab-parse';
my $repo = "https://$github";
WriteMakefile (
    NAME => 'Crontab::Parse',
    VERSION_FROM => $pm,
    ABSTRACT_FROM => $pod,
    AUTHOR => 'Ben Bullock <bkb@cpan.org>',
    LICENSE => 'perl',
    PREREQ_PM => {
	'Date::Calc' => '6.4',
	'File::Temp' => '0.2309',
	'File::Slurper' => '0.012',
    },
    META_MERGE => {
	'meta-spec' => {
	    version => 2,
	},
        resources => {
            repository => {
		type => 'git',
		url => "git://$github.git",
		web => $repo,
	    },
            bugtracker => {
		web => "$repo/issues",
	    },
#	    homepage => 'http://',
        },
    },
    MIN_PERL_VERSION => '5.006001',
);
