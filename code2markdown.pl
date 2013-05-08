#! /usr/bin/perl
use strict;
use warnings;

my $code = shift @ARGV;
( my $markdown = $code )  =~ s/(.+?)\..+?$/$1.txt/;
open my $fh, '<', $code;
open my $out,'>', $markdown;
my $str;
while (<$fh>) {
		s/^/\t/g;
	s/&/&amp/g;
	s/</&lt/g;
	$str .= $_;
}
print $out $str;


