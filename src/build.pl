#!/usr/bin/env perl
use v5.16;
use warnings;

use App;
use Cwd qw(abs_path);
use Getopt::Long ();

my $HELP = <<'EOF';
Usage: build.pl [versions]

Options:
     --root      root dir; will install $root/versions
 -h, --help      show help
 -p, --parallel  parallel

Examples:
 $ build.pl --root ~/env/plenv
 $ build.pl --root ~/env/perl 5.34.0
 $ build.pl --root ~/.plenv --parallel=4 5.34.0
EOF

if ($^O eq 'darwin') {
    # OBJC_DISABLE_INITIALIZE_FORK_SAFETY
    require Socket;
    Socket::inet_aton("call-inet_aton-before_fork");
}

Getopt::Long::GetOptions
    "root=s" => \my $root,
    "h|help" => sub { die $HELP },
    "p|parallel=i" => \(my $parallel = 5),
or exit 2;

die "Need root argument\n" if !$root;

my $app = App->new(root => abs_path($root), parallel => $parallel);
warn "Build.log is $app->{logfile}\n";
$app->run(@ARGV);
