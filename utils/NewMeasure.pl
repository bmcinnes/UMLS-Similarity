#!/usr/bin/perl 

## I TOOK THIS OUT RIGHT NO - THIS IS A PULL FROM SHORTESTPATH
## SO RATHER MESSY


###############################################################################

#                               THE CODE STARTS HERE
###############################################################################

#                           ================================
#                            COMMAND LINE OPTIONS AND USAGE
#                           ================================

use UMLS::Interface;
use UMLS::Similarity::vector;

use Getopt::Long;

eval(GetOptions("stop=s", "vectormatrix=s", "vectorindex=s", "version", "help", "username=s", "password=s", "hostname=s", "database=s", "socket=s", "config=s", "cui", "infile=s", "forcerun", "verbose", "debugpath=s", "cuilist=s", "realtime", "debug", "icpropagation=s", "length", "info", "undirected")) or die ("Please check the above mentioned option(s).\n");


#  if help is defined, print out help
if( defined $opt_help ) {
    $opt_help = 1;
    &showHelp();
    exit;
}

#  if version is requested, show version
if( defined $opt_version ) {
    $opt_version = 1;
    &showVersion();
    exit;
}
 
my @fileArray = ();
if(defined $opt_infile) {
    open(FILE, $opt_infile) || die "Could not open infile: $opt_infile\n";
    while(<FILE>) {
	chomp;
	if($_=~/^\s*$/) { next; }
	push @fileArray, $_;
    }
    close FILE;
}
else {
    
    # At least 2 terms and/or cuis should be given on the command line.
    if(scalar(@ARGV) < 2) {
	print STDERR "Two terms and/or CUIs are required\n";
	&minimalUsageNotes();
	exit;
    }
    

    my $i1 = shift;
    my $i2 = shift;

    my $string = "$i1<>$i2";
    push @fileArray, $string;
}

my $database = "umls";
if(defined $opt_database) { $database = $opt_database; }
my $hostname = "localhost";
if(defined $opt_hostname) { $hostname = $opt_hostname; }
my $socket   = "/tmp/mysql.sock";
if(defined $opt_socket)   { $socket   = $opt_socket;   }


my %option_hash = ();

if(defined $opt_config) {
    $option_hash{"config"} = $opt_config;
}

if(defined $opt_icpropagation) {
    $option_hash{"propagation"} = $opt_icpropagation;
}
if(defined $opt_debug) {
    $option_hash{"debug"} = $opt_debug;
}
if(defined $opt_realtime) {
    $option_hash{"realtime"} = $opt_realtime;
}
if(defined $opt_undirected) {
    $option_hash{"undirected"} = $opt_undirected;
}
if(defined $opt_forcerun) {
    $option_hash{"forcerun"} = $opt_forcerun;
}
if(defined $opt_debugpath) {
    $option_hash{"debugpath"} = $opt_debugpath;
}
if(defined $opt_verbose) {
    $option_hash{"verbose"} = $opt_verbose;
}
if(defined $opt_cuilist) {
    $option_hash{"cuilist"} = $opt_cuilist;
}
if(defined $opt_username) {
    $option_hash{"username"} = $opt_username;
}
if(defined $opt_driver) {
    $option_hash{"driver"}   = "mysql";
}
if(defined $opt_database) {
    $option_hash{"database"} = $database;
}
if(defined $opt_password) {
    $option_hash{"password"} = $opt_password;
}
if(defined $opt_hostname) {
    $option_hash{"hostname"} = $hostname;
}
if(defined $opt_socket) {
    $option_hash{"socket"}   = $socket;
}

my $umls = UMLS::Interface->new(\%option_hash); 
die "Unable to create UMLS::Interface object.\n" if(!$umls);

$vectoroptions{"vectorindex"} = $opt_vectorindex;
$vectoroptions{"vectormatrix"} = $opt_vectormatrix;
$vectoroptions{"stoplist"} = $opt_stop;

if(! (defined $opt_vectorindex) ) {
    print STDERR "Use --vectorindex option\n";
    exit;
}

if(! (defined $opt_vectormatrix) ) {
    print STDERR "Use --vectormatrix option\n";
    exit;
}



my $meas = UMLS::Similarity::vector->new($umls,\%vectoroptions);

foreach my $element (@fileArray) {
    
    my ($input1, $input2) = split/<>/, $element;
    
    my $flag1 = "cui";
    my $flag2 = "cui";

    my @c1 = ();
    my @c2 = ();

    #  check if the input are CUIs or terms
    if( ($input1=~/C[0-9]+/)) {
	push @c1, $input1;
    }
    else {
	@c1 = $umls->getConceptList($input1); 
	$flag1 = "term";
    }
    if( ($input2=~/C[0-9]+/)) {
	push @c2, $input2; 
    }
    else {
	@c2 = $umls->getConceptList($input2); 
	$flag2 = "term";
    }
    
    
    my $printFlag = 0;
    my $precision = 4;      
    my $floatformat = join '', '%', '.', $precision, 'f';    
    foreach $cui1 (@c1) {
	foreach $cui2 (@c2) {
	   
	    if(! ($umls->exists($cui1)) ) { next; }
	    if(! ($umls->exists($cui2)) ) { next; }
		    
	    my $t1 = $input1;
	    my $t2 = $input2;
	    
	    if($flag1 eq "cui") { ($t1) = $umls->getTermList($cui1); }
	    if($flag2 eq "cui") { ($t2) = $umls->getTermList($cui2); }

	    my @shortestpaths = ();
	    if($cui1 eq $cui2) { 
		my $path = "$cui1 $cui2";
		push @shortestpaths, $path;
	    }
	    else {
		@shortestpaths = $umls->findShortestPath($cui1, $cui2);
	    }
	    
	    my $max = -1;
	    foreach my $path (@shortestpaths) {
		my @shortestpath = split/\s+/, $path;

		#my $length = $#shortestpath+1;
		#if($max < $length)  { $max = $length; }
		
		my $cui = shift @shortestpath;
		my $score = 0;   
		foreach my $c (@shortestpath) {
		   
		    my $value = $meas->getRelatedness($cui, $c);
		    $score += $value;
		    $cui = $c;
		}
		my $totalscore = $score;
		#my $totalscore = $score / ($#shortestpath + 2);
		if($totalscore > $max) { 
		    $max = $totalscore;
		}
	    }

	    #my $value = $meas->getRelatedness($cui1, $cui2);
	    
	    if($max > 0) { $max = 1/$max; }

	    if($max < 0) { 
		print "-1<>$cui1<>$cui2\n";
	    }
	    else {
		#my $new = $max * $value;
		print "$max<>$cui1<>$cui2\n";
	    }
	}
    }
    
}

##############################################################################
#  function to output minimal usage notes
##############################################################################
sub minimalUsageNotes {
    
    print "Usage: NewMeasurePath.pl [OPTIONS] [CUI1|TERM1] [CUI2|TERM2]\n";
    &askHelp();
    exit;
}

##############################################################################
#  function to output help messages for this program
##############################################################################
sub showHelp() {

        
    print "This is a utility that takes as input two Terms or\n";
    print "CUIs and returns the shortest path between them.\n\n";
  
    print "Usage: findShortestPath.pl [OPTIONS] [CUI1|TERM1] [CUI2|TERM2]\n\n";

    print "Options:\n\n";

    print "--infile FILE            File containing TERM or CUI pairs\n\n";
    
    print "--debug                  Sets the debug flag for testing\n\n";

    print "--username STRING        Username required to access mysql\n\n";

    print "--password STRING        Password required to access mysql\n\n";

    print "--hostname STRING        Hostname for mysql (DEFAULT: localhost)\n\n";

    print "--database STRING        Database contain UMLS (DEFAULT: umls)\n\n";
    
    print "--socket STRING          Socket used by mysql (DEFAULT: /tmp.mysql.sock)\n\n";

    print "--config FILE            Configuration file for path\n\n";
    
    print "--realtime               This option will not create a database of the\n";
    print "                         path information for all of concepts but just\n"; 
    print "                         obtain the information for the input concept\n\n";
    print "--forcerun               This option will bypass any command \n";
    print "                         prompts such as asking if you would \n";
    print "                         like to continue with the index \n";
    print "                         creation. \n\n";

    print "--debugpath FILE         This option prints out the path\n";
    print "                         information for debugging purposes\n\n";

    print "--verbose                This option prints out the path information\n";
    print "                         to a file in your config directory.\n\n";    
    print "--cuilist FILE           This option takes in a file containing a \n";
    print "                         list of CUIs (one CUI per line) and stores\n";
    print "                         only the path information for those CUIs\n"; 
    print "                         rather than for all of the CUIs\n\n";

    print "--version                Prints the version number\n\n";
 
    print "--help                   Prints this help message.\n\n";
}

##############################################################################
#  function to output the version number
##############################################################################
sub showVersion {
    print '$Id: NewMeasure.pl,v 1.2 2010/10/11 22:20:46 btmcinnes Exp $';
    print "\nCopyright (c) 2008, Ted Pedersen & Bridget McInnes\n";
}

##############################################################################
#  function to output "ask for help" message when user's goofed
##############################################################################
sub askHelp {
    print STDERR "Type NewMeasure.pl --help for help.\n";
}
    
