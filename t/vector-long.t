#!/usr/local/bin/perl -w 
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl access.t'  
##################### We start with some black magic to print on failure.    
use strict;
use warnings;

use Test::More;
use UMLS::Interface;
use File::Spec;
use File::Path;
BEGIN 
{ 
    plan skip_all => "Lengthy Tests Disabled - set UMLS_SIMILARITY_RUN_ALL to run this test suite" 
        unless defined $ENV{UMLS_SIMILARITY_RUN_ALL} and 
	$ENV{UMLS_SIMILARITY_RUN_ALL}==1;
    
    # use Test::NoWarnings, if available
    my $extra = 0 ;
    $extra = 1
        if eval { require Test::NoWarnings ;  import Test::NoWarnings; 1 };

    plan tests => 7;
}

if(!(-d "t")) {
    
    print STDERR "Error - program must be run from UMLS::Similarity\n";
    print STDERR "directory as : perl t/relatedness-long.t \n";
    exit;  
}
#  initialize option hash
my %option_hash = ();

#  set the option hash
$option_hash{"realtime"} = 1;
$option_hash{"t"} = 1;

#  connect to the UMLS-Interface
my $umls = UMLS::Interface->new(\%option_hash);
ok($umls);

#  get the version of umls that is being used
my $version = $umls->version();

#  set the key directory (create it if it doesn't exist)
my $keydir = File::Spec->catfile('t','key', $version);
if(! (-e $keydir) ) {
    mkpath($keydir);
}

#  set up for required options
my $matrix = File::Spec->catfile('t','options', 'vectormatrix');
my $index  = File::Spec->catfile('t','options', 'vectorindex');

#  get the tests
my $testdir = File::Spec->catdir('t','tests','long-tests');
opendir(DIR, $testdir) || die "Could not open directory $testdir\n";
my @testfiles = grep { $_ ne '.' and $_ ne '..' and $_ ne "CVS"} readdir DIR;

my $perl     = $^X;
my $util_prg = File::Spec->catfile('utils', 'umls-similarity.pl');

my @measures = qw/vector/;

foreach my $measure (@measures) {

    foreach my $file (@testfiles) {
	
	my $configfile = "rel-config.$file";		      
	my $keyfile = "$measure.$file";
	
	my $infile  = File::Spec->catfile('t','tests','long-tests', $file);
	my $config  = File::Spec->catfile('t','config', $configfile);
	my $key     = File::Spec->catfile('t', 'key', $version, $keyfile);
	
	my $output = `$perl $util_prg --config $config --vectormatrix $matrix --vectorindex $index --measure $measure --infile $infile 2>&1`;
	
	if(-e $key) {
	    ok (open KEY, $key) or diag "Could not open $key: $!";
	    my $key = "";
	    while(<KEY>) { $key .= $_; } close KEY;
	    cmp_ok($output, 'eq', $key);
	}
	else {
	    ok(open KEY, ">$key") || diag "Could not open $key: $!";
	    print KEY $output;
	    close KEY; 
	  SKIP: {
	      skip ("Generating key, no need to run test", 1);
	    }
	}
    }
    
}
