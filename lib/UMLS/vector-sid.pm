# UMLS::Similarity::vector.pm version 0.01
# This is a work in progress
#
#
# Module to accept two WordNet synsets and to return a floating point
# number that indicates how similar those two synsets are, using a
# gloss vector overlap measure based on "context vectors" described by 
# Schütze (1998).
#
# Copyright (c) 2004,
#
# Siddharth Patwardhan, University of Utah, Salt Lake City
# sidd@cs.utah.edu
#
# Serguei Pakhomov, Mayo Clinic, Rochester
# pakhomov.serguei@mayo.edu
#
# Ted Pedersen, University of Minnesota, Duluth
# tpederse@d.umn.edu
#
# Satanjeev Banerjee, Carnegie Mellon University, Pittsburgh
# banerjee+@cs.cmu.edu
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to 
#
# The Free Software Foundation, Inc., 
# 59 Temple Place - Suite 330, 
# Boston, MA  02111-1307, USA.


package UMLS::Similarity::vector;

use strict;
use warnings;
use vars qw($VERSION);
use dbif;

use UMLS::Interface;

$VERSION = '0.01';

sub new
{
    my $className = shift;
    return undef if(ref $className);

    my $interface = shift;
    my $dbfile    = shift;

    my $self = {};

    #  set the db file
    my $vectorDB = $dbfile;
    $self->{'vectorDB'} = $vectorDB;

    # Initialize the error string and the error level.
    $self->{'errorString'} = "";
    $self->{'error'} = 0;
    
    # The WordNet::QueryData object.
    $self->{'interface'} = $interface;
    if(!$interface)
    {
	$self->{'errorString'} .= "\nError (UMLS::Similarity::vector->new()) - ";
	$self->{'errorString'} .= "An interface object is required.";
	$self->{'error'} = 2;
    }

    # Test the interface for required methods...
    if(!
       #(defined $interface->can("exists") && MODIFIED BTM
       (defined $interface->can("checkConceptExists") &&
	
	#defined $interface->can("getTerms") && MODIFIED BTM
	defined $interface->can("getTermList") &&
	
	#defined $interface->can("getConcepts") && MODIFIED BTM
	defined $interface->can("getConceptList")
       )) 
	
	#MODIFIED BTM - not needed
	#defined $interface->can("relations") && 
	#defined $interface->can("query")))	
	
    {
	$self->{'errorString'} .= "\nError (UMLS::Similarity::vector->new()) - ";
	$self->{'errorString'} .= "Interface does not provide the required methods.";
	$self->{'error'} = 2;
    }
    # Bless object, initialize it and return it.
    bless($self, $className);
    $self->_initialize(shift) if($self->{'error'} < 2);

    # [trace]
    $self->{'traceString'} = "UMLS::Similarity::vector object created:\n";
    $self->{'traceString'} .= "trace :: ".($self->{'trace'})."\n" if(defined $self->{'trace'});
    $self->{'traceString'} .= "cache :: ".($self->{'doCache'})."\n" if(defined $self->{'doCache'});
    $self->{'traceString'} .= "CacheSize :: ".($self->{'maxCacheSize'})."\n" 
	if(defined $self->{'maxCacheSize'});
    $self->{'traceString'} .= "stop List :: ".($self->{'stopFile'})."\n" if(defined $self->{'stopFile'});
    $self->{'traceString'} .= "word Vector DB :: ".($self->{'vectorDB'})."\n" if(defined $self->{'vectorDB'});
    # [/trace]

    


    return $self;
}


# Initialization of the UMLS::Similarity::vector object... 
# parses the config file and sets up global variables.
# INPUT PARAMS  : $paramFile .. File containing the 
#                               module-specific params.
# RETURN VALUES : (none)
sub _initialize
{
    my $self = shift;
    return if(!defined $self || !ref $self);
    my $paramFile = shift;
    my $relationFile;
    my $stopFile;
    my $compFile;
    my $vectorDB;
    my $documentCount;
    my $interface;
    my $gwi;
    my $db;
    my %stopHash = ();

    # Get reference to WordNet.
    $interface = $self->{'interface'};

    #  get the vector database file
    $vectorDB = $self->{'vectorDB'};

    print "$vectorDB\n";

    # Initialize the cache stuff.
    $self->{'doCache'} = 1;
    $self->{'simCache'} = ();
    $self->{'traceCache'} = ();
    $self->{'cacheQ'} = ();
    $self->{'maxCacheSize'} = 1000;
    $self->{'vCache'} = ();
    $self->{'vCacheQ'} = ();
    $self->{'vCacheSize'} = 80;
    
    # Initialize tracing.
    $self->{'trace'} = 0;
    $self->{'traceString'} = "";

    # Stemming? Cutoff? Compounds?
    $self->{'doStem'} = 0;
    $self->{'compounds'} = {};
    $self->{'stopHash'} = {};

    # Parse the config file and
    # read parameters from the file.
    # Looking for params --> 
    # trace, infocontent file, cache
    if(defined $paramFile)
    {
	my $modname = "";
	
	if(!open(PARAM, $paramFile))
	{
	    $self->{'errorString'} .= "\nError (UMLS::Similarity::vector->_initialize()) - ";
	    $self->{'errorString'} .= "Unable to open config file $paramFile.";
	    $self->{'error'} = 2;
	    return;
	}

	while($modname eq "")
	{
	    $modname = <PARAM>;
	    $modname =~ s/[\r\f\n]//g;
	    $modname =~ s/\s+//g;
	}

	if($modname !~ /^UMLS::Similarity::vector/)
	{
	    close PARAM;
	    $self->{'errorString'} .= "\nError (UMLS::Similarity::vector->_initialize()) - ";
	    $self->{'errorString'} .= "$paramFile does not appear to be a config file.";
	    $self->{'error'} = 2;
	    return;
	}

	while(<PARAM>)
	{
	    s/[\r\f\n]//g;
	    s/\#.*//;
	    s/\s+//g;
	    if(/^trace::(.*)/)
	    {
		my $tmp = $1;
		$self->{'trace'} = 1;
		$self->{'trace'} = $tmp if($tmp =~ /^[01]$/);
	    }
	    elsif(/^relation::(.*)/)
	    {
		$relationFile = $1;
	    }
	    #elsif(/^vectordb::(.*)/)
	    #{
	    #	$vectorDB = $1;
	    #}
	    elsif(/^stop::(.*)/)
	    {
		$stopFile = $1;
	    }
	    elsif(/^cache::(.*)/)
	    {
		my $tmp = $1;
		$self->{'doCache'} = 1;
		$self->{'doCache'} = $tmp if($tmp =~ /^[01]$/);
	    }
	    elsif($_ ne "")
	    {
		s/::.*//;
		$self->{'errorString'} .= "\nWarning (UMLS::Similarity::vector->_initialize()) - ";
		$self->{'errorString'} .= "Unrecognized parameter '$_'. Ignoring.";
		$self->{'error'} = 1 if($self->{'error'} < 1);
	    }
	}
	close(PARAM);
    }
    
    # Load the stop list.
    if($stopFile)
    {
	my $line;

	if(open(STOP, $stopFile))
	{
	    $self->{'stopFile'} = $stopFile;
	    while($line = <STOP>)
	    {
		$line =~ s/[\r\f\n]//g;
		$line =~ s/^\s+//;
		$line =~ s/\s+$//;
		$line =~ s/\s+/_/g;
		$stopHash{$line} = 1;
		$self->{'stopHash'}->{$line} = 1;
	    }
	    close(STOP);   
	}
	else
	{
	    $self->{'errorString'} .= "\nWarning (UMLS::Similarity::vector->_initialize()) - ";
	    $self->{'errorString'} .= "Unable to open $stopFile.";
	    $self->{'error'} = 1 if($self->{'error'} < 1);
	}
    }

    # Initialize the word vector database interface...
    if(!defined $vectorDB)    {	
	$self->{'errorString'} .= "\nError (UMLS::Similarity::vector->_initialize()) - ";
	$self->{'errorString'} .= "Word Vector database file not specified. Use configuration file.";
	$self->{'error'} = 2;
	return;
    }
    
    # Get the documentCount...
    $db = dbif->new($vectorDB, "DocumentCount");
    if(!$db)
    {
	$self->{'errorString'} .= "\nError (UMLS::Similarity::vector->_initialize()) - ";
	$self->{'errorString'} .= "Unable to open word vector database.";
	$self->{'error'} = 2;
	return;
    }
    ($documentCount) = $db->getKeys();
    $db->finalize();

    # Load the word vector dimensions...
    $db = dbif->new($vectorDB, "Dimensions");
    if(!$db)
    {
	$self->{'errorString'} .= "\nError (UMLS::Similarity::vector->_initialize()) - ";
	$self->{'errorString'} .= "Unable to open word vector database.";
	$self->{'error'} = 2;
	return;
    }
    my @keys = $db->getKeys();
    my $key;
    $self->{'numberOfDimensions'} = scalar(@keys);
    foreach $key (@keys)
    {
	my $ans = $db->getValue($key);
	my @prts = split(/\s+/, $ans);
	$self->{'wordIndex'}->{$key} = $prts[0];
	$self->{'indexWord'}->[$prts[0]] = $key;
    }
    $db->finalize();
    
    # Set up the interface to the word vectors...
    $db = dbif->new($vectorDB, "Vectors");
    if(!$db)
    {
	$self->{'errorString'} .= "\nError (UMLS::Similarity::vector->_initialize()) - ";
	$self->{'errorString'} .= "Unable to open word vector database.";
	$self->{'error'} = 2;
	return;
    }
    @keys = $db->getKeys();
    foreach $key (@keys)
    {
	my $vec = $db->getValue($key);
	if(defined $vec)
	{
	    $self->{'table'}->{$key} = $vec;
	}
    }
    $db->finalize();
}


# The gloss vector relatedness measure subroutine ...
# INPUT PARAMS  : $concept1     .. one of the two wordsenses.
#                 $concept2     .. the second wordsense of the two whose 
#                              semantic relatedness needs to be measured.
# RETURN VALUES : $distance .. the semantic relatedness of the two word senses.
#              or undef     .. in case of an error.
sub getRelatedness
{
    my $self = shift;
    return undef if(!defined $self || !ref $self);
    my $concept1 = shift;
    my $concept2 = shift;
    my $term1 = shift;
    my $term2 = shift;

    my $interface = $self->{'interface'};
    my $db = $self->{'db'};

    # Check the existence of the WordNet::QueryData object.
    if(!$interface)
    {
	$self->{'errorString'} .= "\nError (UMLS::Similarity::vector->getRelatedness()) - ";
	$self->{'errorString'} .= "An interface object is required.";
	$self->{'error'} = 2;
	return undef;
    }

    # Initialize traces.
    $self->{'traceString'} = "" if($self->{'trace'});

    # Undefined input cannot go unpunished.
    if(!$concept1 || !$concept2)
    {
	$self->{'errorString'} .= "\nWarning (UMLS::Similarity::vector->getRelatedness()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'error'} = ($self->{'error'} < 1) ? 1 : $self->{'error'};
	return undef;
    }

    # Security check -- do the input concepts exist?
    #if(!($interface->exists($concept1))) - MODIFIED BTM
    if(!($interface->checkConceptExists($concept1)))
    {	
	$self->{'errorString'} .= "\nWarning (UMLS::Similarity::res->getRelatedness()) - ";
	$self->{'errorString'} .= "Concept '$concept1' not present in database.";
	$self->{'error'} = 1 if($self->{'error'} < 1);
	return undef;
    }

    #if(!($interface->exists($concept2))) - MODIFIED BTM
    if(!($interface->checkConceptExists($concept2)))
    {	
	$self->{'errorString'} .= "\nWarning (UMLS::Similarity::res->getRelatedness()) - ";
	$self->{'errorString'} .= "Concept '$concept2' not present in database.";
	$self->{'error'} = 1 if($self->{'error'} < 1);
	return undef;
    }

    # Now check if the similarity value for these two synsets is in
    # fact in the cache... if so return the cached value.
    if($self->{'doCache'} && defined $self->{'simCache'}->{"${concept1}::$concept2"})
    {
	if(defined $self->{'traceCache'}->{"${concept1}::$concept2"})
	{
	    $self->{'traceString'} = $self->{'traceCache'}->{"${concept1}::$concept2"}
	    if($self->{'trace'});
	}
	return $self->{'simCache'}->{"${concept1}::$concept2"};
    }

    # Are the gloss vectors present in the cache...
    if(defined $self->{'vCache'}->{$concept1} && defined $self->{'vCache'}->{$concept2})
    {
	if($self->{'trace'})
	{
	    # ah so we do need SOME traces! put in the synset names. 
	    $self->{'traceString'} .= "Synset 1: $concept1 (Gloss Vector found in Cache)\n";
	    $self->{'traceString'} .= "Synset 2: $concept2 (Gloss Vector found in Cache)\n";
	}	
	my $a = $self->{'vCache'}->{$concept1};
	my $b = $self->{'vCache'}->{$concept2};
	my $cos = &inner($a, $b);
	my $score = $cos;

	# that does all the scoring. Put in cache if doing cacheing. Then
	# return the score.    
	if($self->{'doCache'})
	{
	    $self->{'simCache'}->{"${concept1}::$concept2"} = $score;
	    $self->{'traceCache'}->{"${concept1}::$concept2"} = $self->{'traceString'} if($self->{'trace'});
	    push(@{$self->{'cacheQ'}}, "${concept1}::$concept2");
	    if($self->{'maxCacheSize'} >= 0)
	    {
		while(scalar(@{$self->{'cacheQ'}}) > $self->{'maxCacheSize'})
		{
		    my $delItem = shift(@{$self->{'cacheQ'}});
		    delete $self->{'simCache'}->{$delItem};
		    delete $self->{'traceCache'}->{$delItem};
		}
	    }
	}
	return $score;
    }

    # initialize the score
    my $score = 0;
    
    my $removal_regex = '[\\,\\-\\[\\]\\=\\&\\/\\:\\(\\)\\.]';
    my %firstTermHash = (); 
    my %secondTermHash = ();    
    
    my @firstTermList = $interface->getTermList($concept1);
    my @secondTermList = $interface->getTermList($concept2);

    #my @firstTermList = split/\s+/, $term1;
    #my @secondTermList =split/\s+/, $term2;
    
    for my $i (0..$#firstTermList) {
	my $word = $firstTermList[$i];
	$word=~s/\(.*?\)//g;
	$word=~s/\[.*?\]//g;
	$word=~s/$removal_regex/ /g;
	$word=~s/(nos|nes)//g;
	my @ws = split/\s+/, $word;
	foreach my $w (@ws) {
	    $firstTermHash{$w}++;
	}
	
    }

    for my $i (0..$#secondTermList) {
	my $word = $secondTermList[$i];
	$word=~s/\(.*?\)//g;  
	$word=~s/\[.*?\]//g; 
	$word=~s/$removal_regex/ /g;
	$word=~s/(nos|nes)//g;
	my @ws = split/\s+/, $word;
	foreach my $w (@ws) {
	    $secondTermHash{$w}++;
	}
    }
    

    foreach my $rel ($interface->getRelations($concept1))
    {
	#if($rel ne "PAR" and $rel ne "CHD") { next; }

	foreach my $relcon1 ($interface->getRelated($concept1, $rel))
    	{
    	    my $first = join(" ", $interface->getTermList($relcon1));
	    my @array = split/\s+/, $first;
	    foreach my $w (@array) { 
		$w=~s/\(.*?\)//g;  
		$w=~s/\[.*?\]//g;
		$w=~s/$removal_regex/ /g; 
		$w=~s/(nos|nes)//g;
		$w=~s/\s+//g;
		$w=~s/^\s+//g;
		$w=~s/\s+$//g;
		#$firstTermHash{$w}++; 
	    }

	    my @defs = join(" ", $interface->getCuiDef($relcon1));
	    foreach my $def (@defs) {
		my @array = split/\s+/, $def;
		foreach my $w (@array) { 
		    $w=~s/\(.*?\)//g;  
		    $w=~s/\[.*?\]//g;
		    $w=~s/$removal_regex/ /g; 
		    $w=~s/(nos|nes)//g;
		    $w=~s/\s+//g;
		    $w=~s/^\s+//g;
		    $w=~s/\s+$//g;
		    #$firstTermHash{$w}++; 
		}
	    }
	}
    }
    foreach my $rel ($interface->getRelations($concept2)) 
    {
	#if($rel ne "PAR" and $rel ne "CHD") { next; }
	
	foreach my $relcon2 ($interface->getRelated($concept2, $rel))
    	{
      	    my $second = join(" ", $interface->getTermList($concept2)); 
	    my @array = split/\s+/, $second;
	    foreach my $w (@array) { 
		$w=~s/\(.*?\)//g;  
		$w=~s/\[.*?\]//g; 
		$w=~s/$removal_regex/ /g;
		$w=~s/(nos|nes)//g;
		$w=~s/\s+//g;
		$w=~s/^\s+//g;
		$w=~s/\s+$//g;
		#$secondTermHash{$w}++; 
	    }


	    my @defs = join(" ", $interface->getCuiDef($relcon2));
	    foreach my $def (@defs) {
		my @array = split/\s+/, $def;
		foreach my $w (@array) { 
		    $w=~s/\(.*?\)//g;  
		    $w=~s/\[.*?\]//g; 
		    $w=~s/$removal_regex/ /g;
		    $w=~s/(nos|nes)//g;
		    $w=~s/\s+//g;
		    $w=~s/^\s+//g;
		    $w=~s/\s+$//g;
		    #$secondTermHash{$w}++; 
		}
	    }
        }
    }
    

    my @firstDef = $interface->getCuiDef($concept1);
    my @secondDef = $interface->getCuiDef($concept2);
    
    foreach my $def (@firstDef) {
	my @array = split/\s+/, $def;
	foreach my $w (@array) {
	    $w = lc($w);
	    $w=~s/\(.*?\)//g;  
	    $w=~s/\[.*?\]//g; 
	    $w=~s/$removal_regex/ /g;
	    $w=~s/(nos|nes)//g;
	    $w=~s/\s+//g;
	    $w=~s/^\s+//g;
	    $w=~s/\s+$//g;
	    #$firstTermHash{$w}++; 
	}
    }
    foreach my $def (@secondDef) {
	my @array = split/\s+/, $def;
	foreach my $w (@array) {
	    $w = lc($w);
	    $w=~s/\(.*?\)//g;  
	    $w=~s/\[.*?\]//g; 
	    $w=~s/$removal_regex/ /g;
	    $w=~s/(nos|nes)//g;
	    $w=~s/\s+//g;
	    $w=~s/^\s+//g;
	    $w=~s/\s+$//g;
	    #$secondTermHash{$w}++; 
	}
    }

        
    my @firstArray = keys %firstTermHash;
    my @secondArray = keys %secondTermHash;

    my $firstString = join(" ", @firstArray);
    my $secondString = join(" ", @secondArray);
   
    
    # Preprocess...
    $firstString =~ s/\'//g;
    $firstString =~ s/[^a-z0-9]+/ /g;
    $firstString =~ s/^\s+//;
    $firstString =~ s/\s+$//;
#    $firstString = $self->_compoundify($firstString);
    $secondString =~ s/\'//g;
    $secondString =~ s/[^a-z0-9]+/ /g;
    $secondString =~ s/^\s+//;
    $secondString =~ s/\s+$//;
#    $secondString = $self->_compoundify($secondString);
   
    #print STDERR "1: ($concept1) $firstString\n";
    #print STDERR "2: ($concept2) $secondString\n"; 

    # Get vectors... score...
    my $a;
    my $b;
    my $trr;

    # see if any traces reqd. if so, put in the synset arrays. 
    if($self->{'trace'})
    {
	# ah so we do need SOME traces! put in the synset names. 
	$self->{'traceString'} .= "Synset 1: $concept1";
    }
    if(defined $self->{'vCache'}->{$concept1})
    {
	$a = $self->{'vCache'}->{$concept1};
	$self->{'traceString'} .= " (Gloss vector found in cache)\n" if($self->{'trace'});
    }
    else
    {
	($a, $trr) = $self->_getVector($firstString);
	$self->{'traceString'} .= "\nString: \"$firstString\"\n$trr\n" if($self->{'trace'});
	$a = &norm($a);
	$self->{'vCache'}->{$concept1} = $a;
	push(@{$self->{'vCacheQ'}}, $concept1);
	while(scalar(@{$self->{'vCacheQ'}}) > $self->{'vCacheSize'})
	{
	    my $concept = shift(@{$self->{'vCacheQ'}});
	    delete $self->{'vCache'}->{$concept}
	}
    }

    if($self->{'trace'})
    {
	# ah so we do need SOME traces! put in the synset names. 
	$self->{'traceString'} .= "Synset 2: $concept2";
    }
    if(defined $self->{'vCache'}->{$concept2})
    {
	$b = $self->{'vCache'}->{$concept2};
	$self->{'traceString'} .= " (Gloss vector found in cache)\n" if($self->{'trace'});
    }
    else
    {
	($b, $trr) = $self->_getVector($secondString);
	$self->{'traceString'} .= "\nString: \"$secondString\"\n$trr\n" if($self->{'trace'});
	$b = &norm($b);
	$self->{'vCache'}->{$concept2} = $b;
	push(@{$self->{'vCacheQ'}}, $concept2);
	while(scalar(@{$self->{'vCacheQ'}}) > $self->{'vCacheSize'})
	{
	    my $concept = shift(@{$self->{'vCacheQ'}});
	    delete $self->{'vCache'}->{$concept}
	}
    }

    my $cos = &inner($a, $b);
    $score = $cos;
    
    # that does all the scoring. Put in cache if doing cacheing. Then
    # return the score.    
    if($self->{'doCache'})
    {
	$self->{'simCache'}->{"${concept1}::$concept2"} = $score;
	$self->{'traceCache'}->{"${concept1}::$concept2"} = $self->{'traceString'} if($self->{'trace'});
	push(@{$self->{'cacheQ'}}, "${concept1}::$concept2");
	if($self->{'maxCacheSize'} >= 0)
	{
	    while(scalar(@{$self->{'cacheQ'}}) > $self->{'maxCacheSize'})
	    {
		my $delItem = shift(@{$self->{'cacheQ'}});
		delete $self->{'simCache'}->{$delItem};
		delete $self->{'traceCache'}->{$delItem};
	    }
	}
    }
    
    return $score;
}


# Function to return the current trace string
sub getTraceString
{
    my $self = shift;
    return "" if(!defined $self || !ref $self);
    my $returnString = $self->{'traceString'}."\n";
    $self->{'traceString'} = "" if($self->{'trace'});
    $returnString =~ s/\n+$/\n/;
    return $returnString;
}


# Method to return recent error/warning condition
sub getError
{
    my $self = shift;
    return (2, "") if(!defined $self || !ref $self);
    my $error = $self->{'error'};
    my $errorString = $self->{'errorString'};
    $self->{'error'} = 0;
    $self->{'errorString'} = "";
    $errorString =~ s/^\n//;
    return ($error, $errorString);
}

# Method to compute a context vector from a given body of text...
sub _getVector
{
    my $self = shift;
    return {} if(!defined $self || !ref $self);
    my $text = shift;
    my $ret = {};
    return $ret if(!defined $text);
    my @words = split(/\s+/, $text);
    my $word;
    my %types;
    my $fstFlag = 1;
    my $localTraces = "";

    # [trace]
    if($self->{'trace'})
    {
	$localTraces .= "Word Vectors for: ";
    }
    # [/trace]

    foreach $word (@words)
    {
	$types{$word} = 1;
    }
    foreach $word (keys %types)
    {
	if(defined $self->{'table'}->{$word} && !defined $self->{'stopHash'}->{$word})
	{
	    my %pieces = split(/\s+/, $self->{'table'}->{$word});
	    my $kk;

	    # [trace]
	    if($self->{'trace'})
	    {
		$localTraces .= ", " if(!$fstFlag);
		$localTraces .= "$word";
		$fstFlag = 0;
	    }
	    # [/trace]

	    foreach $kk (keys %pieces)
	    {
		$ret->{$kk} += $pieces{$kk};
	    }
	}
    }
    
    return ($ret, $localTraces);
}

# Method that determines all possible compounds in a line of text.
sub _compoundify
{
    my $self = shift;
    return undef if(!defined $self || !ref $self);
    my $block = shift;
    my $interface = $self->{'interface'};
    my $string;
    my $done;
    my $temp;
    my $firstPointer;
    my $secondPointer;
    my @wordsArray;
    my @concepts;
    
    return undef if(!defined $block);
    
    # get all the words into an array
    @wordsArray = ();
    while ($block =~ /(\w+)/g)
    {
	push @wordsArray, $1;
    }
    
    # now compoundify, GREEDILY!!
    $firstPointer = 0;
    $string = "";
    
    while($firstPointer <= $#wordsArray)
    {
	$secondPointer = $#wordsArray;
	$done = 0;
	while($secondPointer > $firstPointer && !$done)
	{
	    $temp = join (" ", @wordsArray[$firstPointer..$secondPointer]);
	    #@concepts = $interface->getConcepts($temp); - MODIFIED BTM
	    @concepts = $interface->getConceptList($temp);
	    if(scalar(@concepts))
	    {
		$temp =~ s/\s+/_/g;
		$string .= "$temp "; 
		$done = 1;
	    }
	    else 
	    { 
		$secondPointer--; 
	    }
	}
	if(!$done) 
	{ 
	    $string .= "$wordsArray[$firstPointer] "; 
	}
	$firstPointer = $secondPointer + 1;
    }
    $string =~ s/ +$//;
    
    return $string;    
}

# Subroutine to normalize a vector.
sub norm
{
    my $vec = shift;
    my $out = {};
    my $lent = 0;
    my $ind;
    return {} if(!defined $vec);
    foreach $ind (keys %{$vec})
    {
	$lent += (($vec->{$ind}) * ($vec->{$ind}));
    }
    $lent = sqrt($lent);
    if($lent)
    {
	foreach $ind (keys %{$vec})
	{
	    $out->{$ind} = $vec->{$ind}/$lent;
	}    
    }

    return $out;
}

# Subroutine to find the dot-product of two vectors.
sub inner
{
    my $a = shift;
    my $b = shift;
    my $ind;
    my $dotProduct = 0;

    return 0 if(!defined $a || !defined $b);
    foreach $ind (keys %{$a})
    {
	$dotProduct += $a->{$ind} * $b->{$ind} if(defined $a->{$ind} && defined $b->{$ind});
    }

    return $dotProduct;
}

1;

__END__

=head1 NAME

UMLS::Similarity::vector - Perl module for computing semantic relatedness
of concepts using second order co-occurrence vectors of definitions of the
concepts.

=head1 SYNOPSIS

  use UMLS::Similarity::vector;

  use WordNet::QueryData;

  my $interface = WordNet::QueryData->new();

  my $vector = UMLS::Similarity::vector->new($interface);

  my $value = $vector->getRelatedness("car#n#1", "bus#n#2");

  ($error, $errorString) = $vector->getError();

  die "$errorString\n" if($error);

  print "car (sense 1) <-> bus (sense 2) = $value\n";

=head1 DESCRIPTION

Schütze (1998) creates what he calls context vectors (second order 
co-occurrence vectors) of pieces of text for the purpose of Word Sense
Discrimination. This idea is adopted by Patwardhan and Pedersen to represent the 
concepts by second-order co-occurrence vectors of their dictionary 
definitions. The relatedness of two concepts is then computed as the cosine of 
their representative vectors.

=head1 USAGE

The semantic relatedness modules in this distribution are built as classes
that expose the following methods:
  new()
  getRelatedness()
  getError()
  getTraceString()

See the UMLS::Similarity(3) documentation for details of these methods.

=head1 TYPICAL USAGE EXAMPLES

To create an object of the vector measure, we would have the following
lines of code in the perl program. 

  use UMLS::Similarity::vector;
  $measure = UMLS::Similarity::vector->new($interface, '/home/sid/vector.conf');

The reference of the initialized object is stored in the scalar
variable '$measure'. '$interface' contains a interface object that
should have been created earlier in the program. The interface object
provides the interface to the backend taxonomy (For example, WordNet,
Snomed, ,UMLS, etc.). The second parameter to the 'new' method is the
path of the configuration file for the vector measure. If the 'new'
method is unable to create the object, '$measure' would be
undefined. This, as well as any other error/warning may be tested.

  die "Unable to create object.\n" if(!defined $measure);
  ($err, $errString) = $measure->getError();
  die $errString."\n" if($err);

To find the sematic relatedness of the first sense of the noun 'car' and
the second sense of the noun 'bus' using the measure, we would write
the following piece of code:

  $relatedness = $measure->getRelatedness('car#n#1', 'bus#n#2');
  
To get traces for the above computation:

  print $measure->getTraceString();

However, traces must be enabled using configuration files. By default
traces are turned off.

=head1 CONFIGURATION FILE

The behaviour of the measures of semantic relatedness can be controlled by
using configuration files. These configuration files specify how certain
parameters are initialized within the object. A configuration file may be
specififed as a parameter during the creation of an object using the new
method. The configuration files must follow a fixed format.

Every configuration file starts the name of the module ON THE FIRST LINE of
the file. For example, a configuration file for the vector module will have
on the first line 'UMLS::Similarity::vector'. This is followed by the various
parameters, each on a new line and having the form 'name::value'. The
'value' of a parameter is optional (in case of boolean parameters). In case
'value' is omitted, we would have just 'name::' on that line. Comments are
supported in the configuration file. Anything following a '#' is ignored till
the end of the line.

The module parses the configuration file and recognizes the following 
parameters:

(a) 'trace::' -- The value of this parameter specifies the level of
tracing that should be employed for generating the traces. This value
is an integer 0, 1 or 2. A value of 0 switches tracing off. A value of
1 displays as traces only the gloss overlaps found. A value of 2 displays
as traces, all the text being compared.

(b) 'vectordb::' -- Value is a Berkeley DB database file containing word 
vectors, i.e. co-occurrence vectors for all the words in the definitions.

(c) 'stop::' -- The value is a string that specifies the path of a file 
containing a list of stop words that should be ignored in the vectors.

(d) 'compounds::' -- The value is a string that specifies the path of a file 
containing a list of compound words in the taxonomy.

(e) 'stem::' -- can take values 0 or 1 or the value can be omitted, in 
which case it takes the value 1, i.e. switches 'on' stemming. A value of 
0 switches stemming 'off'. When stemming is enabled, all the words of the
definitions are stemmed before their vectors are created.

(f) 'cache::' -- can take values 0 or 1 or the value can be omitted, in 
which case it takes the value 1, i.e. switches 'on' caching. A value of 
0 switches caching 'off'. By default caching is enabled.

=head1 SEE ALSO

perl(1), UMLS::Similarity(3)

http://www.cogsci.princeton.edu/~wn

http://www.ai.mit.edu/people/jrennie/WordNet

http://groups.yahoo.com/group/wn-similarity

=head1 AUTHORS

  Siddharth Patwardhan <sidd@cs.utah.edu>
  Serguei Pakhomov <pakhomov.serguei@mayo.edu>
  Ted Pedersen <tpederse@d.umn.edu>

=head1 COPYRIGHT AND LICENSE

Copyright 2004 by Siddharth Patwardhan, Serguei Pakhomov and Ted Pedersen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
