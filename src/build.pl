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

sub run { warn "@_\n"; !system { $_[0] } @_ or die "FAIL @_\n" }

sub wrap {
    my ($file, $code) = @_;
    open my $fh, ">>", $file or die "$!: $file";
    open my $save_stdout, ">&", \*STDOUT;
    open my $save_stderr, ">&", \*STDERR;
    open STDOUT, ">&", $fh;
    open STDERR, ">&", \*STDOUT;
    my $start = time;
    my $res = eval { $code->() };
    my $err = $@;
    my $elapsed = time - $start;
    open STDOUT, ">&", $save_stdout;
    open STDERR, ">&", $save_stderr;
    die $err if $@;
    ($res, $elapsed);
}

sub build {
    my ($version, @argv) = @_;
    for my $dir (grep !-d, "$ROOT/cache", "$ROOT/versions") {
        mkpath $dir or die;
    }

    my $shared = grep { $_ eq "-Duseshrplib"  } @argv;
    my $thread = grep { $_ eq "-Duseithreads" } @argv;
    my $prefix = sprintf "%s%s%s", $version,
        $thread ? "-thr" : "", $shared ? "-shr" : "";
    if (-f "$VERSIONS/$prefix.tar.xz") {
        warn "Already exists $prefix.tar.xz\n";
        return;
    }
    rmtree "$VERSIONS/$prefix" if -d "$VERSIONS/$prefix";

    my $gaurd = pushd "$ROOT/cache";

    my ($cache) = glob "perl-$version.tar.*";
    if (!$cache) {
        my $hash = perl_tarballs($version) or die "Cannot find url for $version";
        my ($cpan_path) = sort values %$hash;
        $cpan_path =~ s/\.(gz|bz2)$/.xz/ if version->parse($version) >= version->parse("5.22.0");
        $cache = basename($cpan_path);
        my $url = "https://cpan.metacpan.org/authors/id/$cpan_path";
        warn "Fetching $url\n";
        my $res = HTTP::Tinyish->new(verify_SSL => 1)->mirror($url => $cache);
        if (!$res->{success}) {
            unlink $cache;
            die "$res->{status} $res->{reason}, $url\n";
        }
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

    my $v = version->parse($version);
    if ($v >= version->parse("5.20.0")) {
        run "make", "-j8", "install";
    } elsif ($v >= version->parse("5.16.0")) {
        run "make", "-j8";
        run "make", "install";
    } else {
        run "make", "install";
    }
    chdir ".." or die;
    rmtree "perl-$version" or die;
    chdir $VERSIONS or die;
    unlink "$prefix/bin/perl$version" or die;
    run "tar", "cJf", "$prefix.tar.xz", $prefix;
    return 1;
}

sub build_all {
    my $releases = CPAN::Perl::Releases::MetaCPAN->new->get;
    my %perl;
    for my $release (@$releases) {
        my $status = $release->{status};
        next if $status ne "cpan" && $status ne "latest";
        my $name = $release->{name};
        my ($version, $minor, $patch) = $name =~ /^perl-(5\.(\d+)\.(\d+))$/ or next;
        next if $minor % 2 != 0;
        push @{$perl{$minor}}, {
            version => $version,
            url => $release->{download_url},
            patch => $patch,
        };
    }
    my @want;
    push @want, sort { $a->{patch} <=> $b->{patch} } grep { $_->{patch} != 0 } @{$perl{8}};
    push @want, sort { $a->{patch} <=> $b->{patch} } @{$perl{10}};
    for my $minor (grep { $_ > 10 } sort keys %perl) {
        my ($max) = sort { $b->{patch} <=> $a->{patch} } @{$perl{$minor}};
        push @want, $max;
    }

    mkpath "$ROOT/build" unless -d "$ROOT/build";
    my $logfile = "$ROOT/build/build.log.@{[time]}";
    warn "Using $logfile\n";
    for my $want (@want) {
        my $v = $want->{version};
        print STDERR "Building $v ...";
        my ($done1, $took1) = wrap $logfile, sub { build $v };
        if ($done1) {
            print STDERR " DONE took $took1 seconds\n";
        } else {
            print STDERR " SKIP it\n";
        }

        print STDERR "Building $v -Duseithreads ...";
        my ($done2, $took2) = wrap $logfile, sub { build $v, "-Duseithreads" };
        if ($done2) {
            print STDERR " DONE took $took2 seconds\n";
        } else {
            print STDERR " SKIP it\n";
        }
    }
}

my $HELP = <<"___";
Usage:
  $0 5.28.1
  $0 5.28.1 -Duseithreads
  $0 5.28.1 -Duseshrplib
  $0 --all
___

die $HELP if !@ARGV or $ARGV[0] =~ /^(-h|--help)$/;
if ($ARGV[0] eq "--all") {
    build_all;
} else {
    build @ARGV;
}
