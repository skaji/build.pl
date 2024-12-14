fatpack:
	rm -rf local
	cpm install --target-perl 5.16
	fatpack-simple --cache ~/.perl-cpm/.fatpack-cache build.pl -o ../build.pl
	perl-gzip-script -i ../build.pl
	chmod +x ../build.pl
	perl-cpan-index-generate local > index.txt
