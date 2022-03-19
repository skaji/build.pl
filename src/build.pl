#!/usr/bin/env perl
use strict;
use warnings;

use CPAN::Perl::Releases::MetaCPAN;
use Devel::PatchPerl::Plugin::FixCompoundTokenSplitByMacro;
use Devel::PatchPerl;
use File::Basename qw(basename);
use File::Path qw(mkpath rmtree);
use File::Spec;
use File::Temp qw(tempdir);
use File::pushd qw(pushd);
use HTTP::Tinyish;
use IO::Handle;
use POSIX qw(strftime);
use Parallel::Pipes::App;

{
    package Devel::PatchPerl::Plugin::My;
    $INC{"Devel/PatchPerl/Plugin/My.pm"} = $0;
    sub patchperl {
        my ($class, %argv) = @_;
        my @plugin = qw(
            Darwin::RemoveIncludeGuard
        );
        for my $klass (map { "Devel::PatchPerl::Plugin::$_" } @plugin) {
            eval "require $klass" or die $@;
            warn "Apply $klass\n";
            $klass->patchperl(%argv);
        }
    }
}

{
    package Releases;
    sub new {
        my $class = shift;
        my @release;
        for my $release (@{ CPAN::Perl::Releases::MetaCPAN->new->get }) {
            my $status = $release->{status};
            next if $status ne "cpan" && $status ne "latest";
            my $name = $release->{name};
            my ($version, $major, $minor, $patch)
                = $name =~ /^perl-(([57])\.(\d+)\.(\d+))$/ or next;
            next if $minor % 2 != 0;
            my $major_minor = sprintf "%d.%03d", $major, $minor;
            my $url = $release->{download_url};
            $url =~ s/\.(gz|bz2)$/.xz/ if $major_minor >= 5.022;
            push @release, {
                version => $version,
                major_minor => $major_minor,
                major => $major,
                minor => $minor,
                patch => $patch,
                url => $url,
            };
        }
        bless \@release, $class;
    }
    sub find {
        my ($self, $version) = @_;
        my ($found) = grep { $_->{version} eq $version } @$self;
        $found;
    }
    sub stables {
        my $self = shift;
        my %group;
        for my $r (@$self) {
            push @{$group{$r->{major_minor}}}, $r;
        }
        for my $major_minor (keys %group) {
            $group{$major_minor} = [ sort { $a->{patch} <=> $b->{patch} } @{$group{$major_minor}} ];
        }
        (
            ( grep { $_->{patch} != 0 } @{$group{"5.008"}} ),
            ( @{$group{"5.010"}} ),
            ( map { $group{$_}[-1] } grep { $_ > 5.010 } sort keys %group ),
        );
    }
}


sub catpath { File::Spec->catfile(@_) }

sub new {
    my ($class, %argv) = @_;
    my $root = $argv{root};
    my $cache_dir = catpath $root, "cache";
    my $build_dir = catpath $root, "build";
    my $target_dir = catpath $root, "versions";
    mkpath $_ for grep !-d, $cache_dir, $build_dir, $target_dir;
    my $logfile = catpath $build_dir, time . ".log";
    open my $logfh, ">>:unix", $logfile or die;
    bless {
        http => HTTP::Tinyish->new,
        logfh => $logfh,
        logfile => $logfile,
        cache_dir => $cache_dir,
        build_dir => $build_dir,
        target_dir => $target_dir,
        context => '',
        parallel => $argv{parallel} || 5,
    }, $class;
}

sub _log {
    my ($self, $line) = @_;
    chomp $line;
    $self->{logfh}->say("$$,$self->{context}," . strftime("%Y-%m-%dT%H:%M:%S", localtime) . "| " . $line);
}

sub _system {
    my ($self, @cmd) = @_;
    my $pid = open my $fh, "-|";
    if ($pid == 0) {
        open STDERR, ">&", \*STDOUT;
        if (@cmd == 1 and ref $cmd[0] eq "CODE") {
            $cmd[0]->();
            exit;
        }
        exec { $cmd[0] } @cmd;
        exit 255;
    }
    $self->_log("=== Executing @cmd") if ref $cmd[0] ne 'CODE';
    while (<$fh>) {
        $self->_log($_);
    }
    close $fh;
    $? == 0;
}

sub fetch {
    my ($self, $url) = @_;
    my $file = catpath $self->{cache_dir}, basename $url;
    my $res = $self->{http}->mirror($url, $file);
    ($file, $res->{success} ? undef : "$res->{status} $url");
}

sub build {
    my ($self, %argv) = @_;

    my $source = $argv{source};
    my $prefix = $argv{prefix};
    my $version = $argv{version};
    my @configure = @{$argv{configure}};

    local $self->{context} = $prefix;

    (my $base = basename $source) =~ s/\.tar\.(gz|bz2|xz)$//;
    my $dir = tempdir "$base-XXXXX", CLEANUP => 0, DIR => $self->{build_dir};
    $self->_system("tar", "xf", $source, "--strip-components=1", "-C", $dir) or die;

    {
        my $guard = pushd $dir;

        $self->_system(sub {
            local $ENV{PERL5_PATCHPERL_PLUGIN} = "My";
            Devel::PatchPerl->patch_source;

            # XXX Because we want to apply FixCompoundTokenSplitByMacro to perl 5.34.0,
            # execute it separately
            warn "Apply Devel::PatchPerl::Plugin::FixCompoundTokenSplitByMacro\n";
            Devel::PatchPerl::Plugin::FixCompoundTokenSplitByMacro->patchperl(version => $version);
        }) or return;
        $self->_system(
            "sh",
            "Configure",
            "-des",
            "-DDEBUGGING=-g",
            "-Dprefix=" . catpath($self->{target_dir}, $prefix),
            "-Dscriptdir=" . catpath($self->{target_dir}, $prefix, "bin"),
            "-Dman1dir=none",
            "-Dman3dir=none",
            @configure,
        ) or return;
        $self->_system("make", "install") or return;
        unlink catpath($self->{target_dir}, $prefix, "bin", "perl$version") or die;
    }
    $self->_system(
        "tar", "cJf",
        catpath($self->{target_dir}, "$prefix.tar.xz"),
        "-C", $self->{target_dir},
        $prefix,
    ) or die;
    rmtree $dir;
    1;
}

sub run {
    my ($self, @version) = @_;

    my $releases = Releases->new;
    my @perl;
    if (@version) {
        for my $v (@version) {
            my $found = $releases->find($v) or die "Invalid version $v\n";
            push @perl, $found;
        }
    } else {
        @perl = $releases->stables;
    }

    my (@url, @build);
    for my $perl (@perl) {
        my $source = catpath $self->{cache_dir}, basename $perl->{url};
        if (!-f $source) {
            push @url, {
                version => $perl->{version},
                url => $perl->{url},
            };
        }
        my $artifact = catpath $self->{target_dir}, "$perl->{version}.tar.xz";
        if (!-f $artifact) {
            push @build, {
                source => $source,
                version => $perl->{version},
                prefix => $perl->{version},
                configure => [],
            };
        }
        my $artifact_thr = catpath $self->{target_dir}, "$perl->{version}-thr.tar.xz";
        if (!-f $artifact_thr) {
            push @build, {
                source => $source,
                version => $perl->{version},
                prefix => "$perl->{version}-thr",
                configure => ["-Duseithreads"],
            };
        }
    }

    if (@url) {
        my @result = Parallel::Pipes::App->map(
            num => $self->{parallel},
            tasks => \@url,
            work => sub {
                my $url = shift;
                $self->_log("Fetching $url->{url}");
                warn "$$ Fetching $url->{url}\n";
                my (undef, $err) = $self->fetch($url->{url});
                return { %$url, error => $err };
            },
        );
        for my $result (@result) {
            die "$result->{error}\n" if $result->{error};
        }
    }
    if (!@build) {
        warn "There is no need to build perls.\n";
        unlink $self->{logfile};
        return;
    }
    my @result = Parallel::Pipes::App->map(
        num => $self->{parallel},
        tasks => \@build,
        work => sub {
            my $build = shift;
            warn sprintf "%s \e[1;33mSTART\e[m %s\n",
                (strftime "%Y-%m-%dT%H:%M:%S", localtime),
                $build->{prefix},
            ;
            my $start = time;
            my $ok = $self->build(%$build);
            my $elapsed = time - $start;
            warn sprintf "%s %s %s %d secs\n",
                (strftime "%Y-%m-%dT%H:%M:%S", localtime),
                $ok ? "\e[1;32mDONE\e[m " : "\e[1;31mFAIL\e[m ",
                $build->{prefix},
                $elapsed,
            ;
            return { %$build, error => $ok ? "" : "failed to build $build->{prefix}" };
        },
    );
    for my $result (@result) {
        die "$result->{error}\n" if $result->{error};
    }
}

if (@ARGV and $ARGV[0] =~ /^(-h|--help)$/) {
    die <<'EOF';
Usage: build.pl [versions]

Examples:
 $ build.pl
 $ build.pl 5.34.0
EOF
}

my $root = $ENV{PLENV_ROOT} || catpath($ENV{HOME}, ".plenv");
my $app = __PACKAGE__->new(root => $root, parallel => 4);
warn "Build.log is $app->{logfile}\n";
$app->run(@ARGV);
