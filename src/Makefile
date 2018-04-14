fatpack: ../build.pl

../build.pl: local build.pl
	rm -rfv local/lib/perl5/*/auto/version local/lib/perl5/*/version/vxs.pm
	fatpack-simple -e Test::More,Cwd,Carp build.pl -o ../build.pl
	chmod +x ../build.pl

local:
	cpm install --target-perl 5.8.1
