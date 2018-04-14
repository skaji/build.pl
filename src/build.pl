#!/usr/bin/env perl
use strict;
use warnings;

use CPAN::Perl::Releases::MetaCPAN qw(perl_tarballs);
use Devel::PatchPerl;
use File::Basename qw(basename);
use File::Path qw(mkpath rmtree);
use File::pushd qw(pushd);
use HTTP::Tinyish;
use version ();

my $ROOT = $ENV{PLENV_ROOT} || "$ENV{HOME}/.plenv";
my $VERSIONS = "$ROOT/versions";

sub run { warn "@_\n"; !system @_ or die "FAIL @_\n" }

sub build {
    my ($version, @argv) = @_;
    for my $dir (grep !-d, "$ROOT/cache", "$ROOT/versions") {
        mkpath $dir or die;
    }

    my $shared = grep { $_ eq "-Duseshrplib"  } @argv;
    my $thread = grep { $_ eq "-Duseithreads" } @argv;
    my $prefix = sprintf "%s%s%s", $version,
        $thread ? "-thr" : "", $shared ? "-shr" : "";
    if (-f "$VERSIONS/$prefix.tar.gz") {
        warn "Already exists $prefix.tar.gz\n";
        return;
    }

    my $gaurd = pushd "$ROOT/cache";

    my ($cache) = glob "perl-$version.tar.*";
    if (!$cache) {
        my $hash = perl_tarballs($version) or die "Cannot find url for $version";
        my ($cpan_path) = sort values %$hash;
        $cache = basename($cpan_path);
        my $url = "https://cpan.metacpan.org/authors/id/$cpan_path";
        warn "Fetching $url\n";
        my $res = HTTP::Tinyish->new->mirror($url => $cache);
        die "$res->{status} $res->{reason}, $url\n" unless $res->{success};
    }
    rmtree "perl-$version";
    run "tar", "xf", $cache;
    chdir "perl-$version" or die;
    Devel::PatchPerl->patch_source;

    run "./Configure",
        "-des",
        "-DDEBUGGING=-g",
        "-Dprefix=$VERSIONS/$prefix",
        "-Dman1dir=none", "-Dman3dir=none",
        @argv,
    ;

    my @parallel = version->parse($version) >= version->parse("5.16.0") ? ("-j8") : ();
    run "make", @parallel, "install";
    chdir ".." or die;
    rmtree "perl-$version" or die;
    chdir $VERSIONS or die;
    unlink "$prefix/bin/perl$version" or die;
    run "tar", "czf", "$prefix.tar.gz", $prefix;
}

die "Usage: $0 5.26.1 -Duseithreads -Duseshrplib\n" if !@ARGV or $ARGV[0] =~ /^(-h|--help)$/;
build @ARGV;
