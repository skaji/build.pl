#!/usr/bin/env perl
use strict;
use warnings;

use Devel::PatchPerl;
use File::Path qw(mkpath rmtree);
use File::pushd qw(pushd);
use HTTP::Tinyish;

my $ROOT = $ENV{PLENV_ROOT} || "$ENV{HOME}/.plenv";
my $VERSIONS = "$ROOT/versions";

sub run { warn "@_\n"; !system @_ or die "FAIL @_\n" }

sub build {
    my ($version, $is_thread) = @_;
    for my $dir (grep !-d, "$ROOT/cache", "$ROOT/versions") {
        mkpath $dir or die;
    }

    my $prefix = sprintf "%s%s", $version, ($is_thread ? "-thr" : "");
    if (-f "$VERSIONS/$prefix.tar.gz") {
        warn "Already exists $prefix.tar.gz\n";
        return;
    }

    my $gaurd = pushd "$ROOT/cache";

    my $cache = "perl-$version.tar.gz";
    if (!-f $cache) {
        my $url = "https://www.cpan.org/src/5.0/$cache";
        warn "Fetching $url\n";
        my $res = HTTP::Tinyish->new->mirror($url => $cache);
        die "$res->{status} $res->{reason}, $url\n" unless $res->{success};
    }
    rmtree "perl-$version";
    run "tar", "xzf", $cache;
    chdir "perl-$version" or die;
    Devel::PatchPerl->patch_source;

    run "./Configure",
        "-des",
        "-DDEBUGGING=-g",
        "-Dprefix=$VERSIONS/$prefix",
        "-Dman1dir=none", "-Dman3dir=none",
        ($is_thread ? ("-Duseithreads") : ()),
    ;
    run "make", "install";
    chdir ".." or die;
    rmtree "perl-$version" or die;
    chdir $VERSIONS or die;
    unlink "$prefix/bin/perl$version" or die;
    run "tar", "czf", "$prefix.tar.gz", $prefix;
}

build @ARGV;
