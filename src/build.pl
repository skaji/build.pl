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
use Parallel::Pipes;

{
    package Devel::PatchPerl::Plugin::My;
    $INC{"Devel/PatchPerl/Plugin/My.pm"} = $0;
    sub patchperl {
        my ($class, %argv) = @_;
        my @plugin = qw(
            Darwin::RemoveIncludeGuard
            Darwin::getcwd
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
        my %perl;
        for my $r (@$self) {
            my $major_minor = sprintf "%d.%03d", $r->{major}, $r->{minor};
            push @{$perl{$major_minor}}, $r;
        }
        my @want;
        push @want, sort { $a->{patch} <=> $b->{patch} } grep { $_->{patch} != 0 } @{$perl{"5.008"}};
        push @want, sort { $a->{patch} <=> $b->{patch} } @{$perl{"5.010"}};
        for my $major_minor (grep { $_ > 5.010 } sort keys %perl) {
            my ($max) = sort { $b->{patch} <=> $a->{patch} } @{$perl{$major_minor}};
            push @want, $max;
        }
        @want;
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
    $self->_log("=== Executing @cmd");
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

    my $file = $argv{file};
    my $prefix = $argv{prefix};
    my $version = $argv{version};
    my @configure = @{$argv{configure}};

    local $self->{context} = $prefix;

    (my $base = basename $file) =~ s/\.tar\.(gz|bz2|xz)$//;
    my $dir = tempdir "$base-XXXXX", CLEANUP => 0, DIR => $self->{build_dir};
    $self->_system("tar", "xf", $file, "--strip-components=1", "-C", $dir) or die;

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
        my $file0 = catpath $self->{cache_dir}, basename $perl->{url};
        if (!-f $file0) {
            push @url, {
                version => $perl->{version},
                url => $perl->{url},
            };
        }
        my $file1 = catpath $self->{target_dir}, "$perl->{version}.tar.xz";
        if (!-f $file1) {
            push @build, {
                file => $file0,
                version => $perl->{version},
                prefix => $perl->{version},
                configure => [],
            };
        }
        my $file2 = catpath $self->{target_dir}, "$perl->{version}-thr.tar.xz";
        if (!-f $file2) {
            push @build, {
                file => $file0,
                version => $perl->{version},
                prefix => "$perl->{version}-thr",
                configure => ["-Duseithreads"],
            };
        }
    }

    if (@url) {
        my @result = $self->_parallel($self->{parallel}, \@url, sub {
            my $url = shift;
            $self->_log("Fetching $url->{url}");
            warn "$$ Fetching $url->{url}\n";
            my (undef, $err) = $self->fetch($url->{url});
            return { %$url, error => $err };
        });
        for my $result (@result) {
            die "$result->{error}\n" if $result->{error};
        }
    }
    if (!@build) {
        warn "There is no need to build perls.\n";
        return;
    }
    my @result = $self->_parallel($self->{parallel}, \@build, sub {
        my $build = shift;
        warn "$$ \e[1;33mSTART\e[m $build->{prefix}\n";
        my $start = time;
        my $ok = $self->build(%$build);
        my $elapsed = time - $start;
        warn sprintf "$$ %s %s %d secs\n",
            $ok ? "\e[1;32mDONE\e[m " : "\e[1;31mFAIL\e[m ", $build->{prefix}, $elapsed;
        return { %$build, error => $ok ? "" : "failed to build $build->{prefix}" };
    });
    for my $result (@result) {
        die "$result->{error}\n" if $result->{error};
    }
}

sub _parallel {
    my ($self, $num, $tasks, $sub) = @_;
    my $pipes = Parallel::Pipes->new($num, $sub);
    my @result;
    for my $task (@$tasks) {
        my @ready = $pipes->is_ready;
        push @result, $_->read for grep { $_->is_written } @ready;
        $ready[0]->write($task);
    }
    while (my @written = $pipes->is_written) {
        push @result, $_->read for @written;
    }
    $pipes->close;
    @result;
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
