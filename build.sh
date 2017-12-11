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
perl build.pl 5.26.1

THREAD_ON=1

perl build.pl 5.8.1  $THREAD_ON
perl build.pl 5.8.5  $THREAD_ON
perl build.pl 5.8.8  $THREAD_ON
perl build.pl 5.8.9  $THREAD_ON
perl build.pl 5.10.1 $THREAD_ON
perl build.pl 5.12.5 $THREAD_ON
perl build.pl 5.14.4 $THREAD_ON
perl build.pl 5.16.3 $THREAD_ON
perl build.pl 5.18.4 $THREAD_ON
perl build.pl 5.20.3 $THREAD_ON
perl build.pl 5.22.4 $THREAD_ON
perl build.pl 5.24.3 $THREAD_ON
perl build.pl 5.26.1 $THREAD_ON
