fatpack:
	rm -rf local
	cpm install --target-perl 5.8.1
	rm -rfv local/lib/perl5/*/auto/version local/lib/perl5/*/version/vxs.pm
	perl -I/Users/skaji/src/github.com/skaji/App-FatPacker-Simple/lib /Users/skaji/src/github.com/skaji/App-FatPacker-Simple/script/fatpack-simple --cache .cache -e Test::More,Cwd,Carp build.pl -o ../build.pl
	chmod +x ../build.pl
