#!/bin/bash

set -ex

perl build.pl 5.8.1
perl build.pl 5.8.5
perl build.pl 5.8.8
perl build.pl 5.8.9
perl build.pl 5.10.1
perl build.pl 5.12.5
perl build.pl 5.14.4
perl build.pl 5.16.3
perl build.pl 5.18.4
perl build.pl 5.20.3
perl build.pl 5.22.4
perl build.pl 5.24.3
perl build.pl 5.26.2

perl build.pl 5.8.1  -Duseithreads
perl build.pl 5.8.5  -Duseithreads
perl build.pl 5.8.8  -Duseithreads
perl build.pl 5.8.9  -Duseithreads
perl build.pl 5.10.1 -Duseithreads
perl build.pl 5.12.5 -Duseithreads
perl build.pl 5.14.4 -Duseithreads
perl build.pl 5.16.3 -Duseithreads
perl build.pl 5.18.4 -Duseithreads
perl build.pl 5.20.3 -Duseithreads
perl build.pl 5.22.4 -Duseithreads
perl build.pl 5.24.3 -Duseithreads
perl build.pl 5.26.2 -Duseithreads
