# build perls for plenv

This script builds perls for plenv. The one command `build.pl --all` builds:

* 5.8.1, 5.8.2, 5.8.3, 5.8.4, 5.8.5, 5.8.6, 5.8.7, 5.8.8, 5.8.9
* 5.10.0, 5.10.1
* latest 5.12
* latest 5.14
* latest 5.16
* latest 5.18
* latest 5.20
* latest 5.22
* latest 5.24
* latest 5.26
* latest 5.28
* (and latest 5.30, latest 5.32, ... once they are available)

with 2 flavors:

* thread disabled
* thread enabled

## Install

You can download a *self-contained* script:

```
$ curl -fsSL https://raw.githubusercontent.com/skaji/build.pl/master/build.pl > build.pl
$ chmod +x build.pl
$ mv build.pl /path/to/bin/
```

## Example

```
$ build.pl --all
(Be patient; this will take more than 1 hour...)

$ plenv versions
  system
  5.10.0
  5.10.0-thr
  5.10.1
  5.10.1-thr
  5.12.5
  5.12.5-thr
  5.14.4
  5.14.4-thr
  5.16.3
  5.16.3-thr
  5.18.4
  5.18.4-thr
  5.20.3
  5.20.3-thr
  5.22.4
  5.22.4-thr
  5.24.4
  5.24.4-thr
  5.26.3
  5.26.3-thr
  5.28.1
  5.28.1-thr
  5.8.1
  5.8.1-thr
  5.8.2
  5.8.2-thr
  5.8.3
  5.8.3-thr
  5.8.4
  5.8.4-thr
  5.8.5
  5.8.5-thr
  5.8.6
  5.8.6-thr
  5.8.7
  5.8.7-thr
  5.8.8
  5.8.8-thr
  5.8.9
  5.8.9-thr
```

## Upgrade perls

If a new stable perl is released, you may just execute `build.pl --all` again:

```
$ build.pl --all
Using /Users/skaji/env/plenv/build/build.log.1555227667
Building 5.8.1 ... SKIP it
Building 5.8.1 -Duseithreads ... SKIP it
...
Building 5.28.2 ...
```

## License

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

## Author

Shoichi Kaji
