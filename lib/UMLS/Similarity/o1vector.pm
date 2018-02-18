# UMLS::Similarity::o1vector.pm
#
# Module implementing the vector semantic relatedness measure 
# based on the measure using first order vectors
#
# Copyright (c) 2009-2012,
#
# Bridget T McInnes, University of Minnesota, Twin Cities
# bthomson at umn.edu
#
# Siddharth Patwardhan, University of Utah, Salt Lake City
# sidd at cs.utah.edu
#
# Serguei Pakhomov, University of Minnesota, Twin Cities
# pakh002 at umn.edu
#
# Ted Pedersen, University of Minnesota, Duluth
# tpederse at d.umn.edu
#
# Ying Liu, University of Minnesota
# liux0935 at umn.edu
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



package UMLS::Similarity::o1vector;

use strict;
use warnings;

use UMLS::Similarity;
use Lingua::Stem::En;
use UMLS::Similarity::ErrorHandler;
use Math::SparseVector;

use vars qw($VERSION);
$VERSION = '0.11';

my $debug        = 0;
my $defraw_option= 0;

my $compoundfile = "";
my $dictfile     = "";
my $doubledef    = "";
my $stoplist	 = "";
my $stem         = "";
my $stopregex	 = "";
my $debugfile    = "";
my $config       = "";

my %index         = ();
my %dictionary    = ();
my %ddef          = ();
my %stopwords     = ();
my %complist 	  = ();


local(*DEBUG);

###########################################################################
#  initializes the vector parameters
###########################################################################
sub new { 

    my $className = shift;

    return undef if(ref $className);

    if($debug) { print STDERR "In UMLS::Similarity::vector->new()\n"; }

    my $interface = shift;
    my $params    = shift;

    my $self = {};
    
    # Bless the object.
    bless($self, $className);
    
    # The backend interface object.
    $self->{'interface'} = $interface;
    
    #  check the configuration file if defined
    my $errorhandler = UMLS::Similarity::ErrorHandler->new("vector",  $interface);
    if(!$errorhandler) {
	print STDERR "The UMLS::Similarity::ErrorHandler did not load properly\n";
	exit;
    }
    
    $params = {} if(!defined $params);

    # set the vector parameters
    $config       = $params->{'config'};
    $dictfile     = $params->{'dictfile'};
    $doubledef    = $params->{'doubledef'};
    $compoundfile = $params->{'compoundfile'};
    $debugfile	  = $params->{'debugfile'};
    $stoplist	  = $params->{'stoplist'};
    $stem         = $params->{'stem'};
    
    my $defraw    = $params->{'defraw'};
    if(defined $defraw) { $defraw_option = 1; } 
   
    # read in the doubledef for --doubledef option 
    if (defined $doubledef) {
	open(DDEF, "$doubledef")
	    or die("Error: cannot open doubledef file ($doubledef).\n");
	
	while(<DDEF>) {
	    chomp;
	    if($_=~/^\s*$/) { next; }
	    
	    my @defs = split (":", $_);
	    my $concept = $defs[0]; 
	    $concept =~ s/^\s+//;
	    $concept =~ s/\s+$//;
	    my $definition = $defs[1];	
	    $ddef{$concept} = $definition;
	}
	close DDEF;
    }
    

    # read in the dictfile for --dictfile option 
    if (defined $dictfile) {
	open(DICT, "$dictfile")
	    or die("Error: cannot open dictionary file ($dictfile).\n");
	
	while(<DICT>) {
	    chomp;
	    
	    if($_=~/^\s*$/) { next; }
	    
	    my @defs = split (":", $_);
	    my $concept = $defs[0]; 
	    $concept =~ s/^\s+//;
	    $concept =~ s/\s+$//;
	    my $definition = $defs[1];	
	    $dictionary{$concept} = $definition;
	}
	close DICT;
    }
        
    #  set the debug file
    if(defined $debugfile) { 
	if(-e $debugfile) {
	    print "Debug file $debugfile already exists! Overwrite (Y/N)? ";
	    my $reply = <STDIN>;
	    chomp $reply;
	    $reply = uc $reply;
	    exit 0 if ($reply ne "Y");
	}
	
	open(DEBUG, ">$debugfile") || die "Could not open debug file: $debugfile\n";
    }
    
    #  read in the stoplist
    if (defined $stoplist) {
	
	open(STP, "$stoplist")
	    or die("Error: cannot open stop list file ($stoplist).\n");
	
	$stopregex  = "(";
	while(<STP>) {
	    chomp;
	    if($_ ne ""){
        	$_=~s/\///g;
        	$stopregex .= "$_|";
	    }
	}   
	chop $stopregex; $stopregex .= ")";
	close STP;
    }
    
    #  read in the file of compound words
    if(defined $compoundfile) {
	
	#replace the compound words in the definition
	open(LST, "$compoundfile") or die ("Error: cannot open file $compoundfile for input.\n");
	
	# read the compound txt and put them in the hash array. 
	while (my $line = <LST>) {
	    chomp($line);
	    my $lower_case = lc($line);
	    my @string = split('_', $lower_case);
	    my $head = shift(@string);
	    
	    my $rest = join (' ', @string);
	    push (@{$complist{$head}}, $rest);
	}
	close LST;
	
	# sort the compound txt 
	foreach my $h (sort (keys (%complist)) ) {
	    my @sort_list = sort(@{$complist{$h}});
	    for my $i (0..$#sort_list) {
		$complist{$h}[$i] = $sort_list[$i];
	    }
	}
    }

    return $self;
}

###########################################################################
#  sub routine that returns the relatedness score between two concepts
###########################################################################
sub getRelatedness {
    my $self = shift;
    
    return undef if(!defined $self || !ref $self);
    
    my $concept1 = shift;
    my $concept2 = shift;
    
    if(defined $debugfile) {
	print DEBUG "PROCESSING CONCEPTS: $concept1 and $concept2\n";
	print DEBUG "=============================================\n"; 
    }
    
    my $interface = $self->{'interface'};

    #  these are the definition variables
    my $d1 = "";
    my $d2 = "";

    
    ###########################################################################
    #  Get the definitions based on the user defined parameters
    ###########################################################################
    if (!defined $dictfile) {
	if ($concept1 =~ /C[0-9]+/) {	
	    my $defs1 = $interface->getExtendedDefinition($concept1);
	    if(defined $debugfile) {
		print DEBUG "DEFINITIONS FOR CONCEPT 1 $concept1: \n";
	    }
	    my $i = 1;
	    foreach my $def (@{$defs1}) {
		if(defined $debugfile) {
		    print DEBUG "$i. $def\n";
		    $i++;
		}
		$def=~/(C[0-9]+) ([A-Za-z]+) ([A-Za-z0-9]+) ([A-Za-z0-9\.]+) \s*\:\s*(.*?)$/;
		if(defined $5) { 
		    $d1 .= $5 . " ";
		}
	    }
	    
	    #if the definition is empty, return -1
	    if ($d1 eq "") { return -1; }
	}
	if($concept2 =~ /C[0-9]+/) {
	    my $defs2 = $interface->getExtendedDefinition($concept2);
	    if(defined $debugfile) {
		print DEBUG "DEFINITIONS FOR CONCEPT 2 $concept2: \n";
	    }
	    my $i = 1;
	    foreach my $def (@{$defs2}) {
		if(defined $debugfile) {
		    print DEBUG "$i. $def\n";
		    $i++;
		}
		$def=~/(C[0-9]+) ([A-Za-z]+) ([A-Za-z0-9]+) ([A-Za-z0-9\.]+) \s*\:\s*(.*?)$/;
		if(defined $5) { 
		    $d2 .= $5 . " ";
		}
	    }
	    
	    #if the definition is empty, return -1
	    if ($d2 eq "") { return -1; }
	}
    } # end of without --dictfile option 
    
    if (defined $dictfile) {
	my $defs1;
	my $defs2;
	my $term1;
	my $term2;
	my $term1_def = "";
	my $term2_def = "";
	
	my @dictfile_term1;
	my @dictfile_term2;
	
	if(defined $debugfile) { print DEBUG "DEFINITIONS FOR CONCEPT 1: $concept1\n"; }

	# the input format is cui#term	
	if($concept1 =~ /^(C[0-9]+)(\#)(.*?)$/) {
	    my $cui1 = $1;
	    $term1 = $3;
	    
	    $defs1 = $interface->getExtendedDefinition($cui1);
	    $term1_def = $dictionary{$term1} if (defined $dictionary{$term1});
	    
	    my $i = 1;
	    foreach my $extendeddef (@{$defs1}) {
		if (defined $debugfile) {
		    print DEBUG "$i. $extendeddef\n";
		    $i++;
		}
		
		#  seperate definition from the other information 
		#  sent by the getExtendedDefinition function
		$extendeddef=~/(C[0-9]+) ([A-Za-z]+) ([A-Za-z0-9]+) ([A-Za-z0-9\.]+) \s*\:\s*(.*?)$/;

		my $def = $5;
		
		#  store the definition in the string d1
		$d1 .= $def . " "; 
	    }	   
	    
	    $d1 .= $term1_def . " " if $term1_def ne ""; 

	    if(defined $debugfile) { 
		print DEBUG "$i. $term1_def\n" if (defined $term1_def);
	    }
	    
	    #if the definition is empty, return -1
	    if ($d1 eq "")  { return -1; } 
	}
	else {  #the input concept is a term 
	    
	    if (defined $dictionary{$concept1}) {
		$d1 = $dictionary{$concept1};
		if (defined $debugfile) {
		    print DEBUG "$concept1: $d1\n"; 
		}
	    }
	    else{
		if (defined $debugfile) {
		    print DEBUG "$concept1: not defined\n"; 
		}
		return -1; }
	}
	
	if(defined $debugfile) { print DEBUG "DEFINITIONS FOR CONCEPT 2: $concept2\n"; }
	
	if($concept2 =~ /^(C[0-9]+)(\#)(.*?)$/)
	{
	    my $cui2 = $1;
	    $term2 = $3;
	    
	    $defs2 = $interface->getExtendedDefinition($cui2);
	    $term2_def = $dictionary{$term2} if (defined $dictionary{$term2});
	    
	    my $i = 1;
	    foreach my $extendeddef (@{$defs2}) {
		if (defined $debugfile) {
		    print DEBUG "$i. $extendeddef\n";
		    $i++;
		}
		
		#  seperate definition from the other information 
		#  sent by the getExtendedDefinition function
		$extendeddef=~/(C[0-9]+) ([A-Za-z]+) ([A-Za-z0-9]+) ([A-Za-z0-9\.]+) \s*\:\s*(.*?)$/;
		my $def = $5;
		
		#  store the definition in the string d1
		$d2 .= $def . " "; 
	    }	   
	    
	    $d2 .= $term2_def . " " if $term2_def ne ""; 
	    
	    if(defined $debugfile) { 
		print DEBUG "$i. $term2_def\n" if (defined $term2_def);
	    }
	    
	    #if the definition is empty, return -1
	    if ($d2 eq "") { return -1; }
	}
	else { 

	    if (defined $dictionary{$concept2}) {
		$d2 = $dictionary{$concept2};
		if (defined $debugfile) {
		    print DEBUG "$concept2: $d2\n"; }
	    }
	    else {
		if (defined $debugfile) {
		    print DEBUG "$concept2: not defined\n"; 
		}
		return -1; 
	    }
	}
	
    } #end of defined --dictfile option
    
    
    # if define --doubledef option
    if (defined $doubledef) { 
	
	my @def1 = split(/\s/, $d1);	
	my @def2 = split(/\s/, $d2);	
	
	my %unique = (); 

	# for every word, only check its definition once	
	foreach my $w (@def1) { 
	    $unique{$w}++;	
	    if ((defined $ddef{$w}) and ($unique{$w}==1)) { 
		my $def = $ddef{$w}; 
		if (defined $debugfile) { 
		    print DEBUG "ddef1 $w: $def\n"; 
		}
		$d1 .= "$def" . " ";
	    }
	}		
	
	%unique = ();	
	foreach my $w (@def2) { 
	    $unique{$w}++;	
	    if ((defined $ddef{$w}) and ($unique{$w}==1)) { 
		my $def = $ddef{$w}; 
		if (defined $debugfile) { 
		    print DEBUG "ddef2 $w: $def\n"; 
		}
		$d2 .= "$def" . " ";
	    }
	}		
	
	if (defined $debugfile) { 
	    print DEBUG "AFTER --doubledef PROCESSING\n";
	    print DEBUG "  concept 1: $d1\n";
	    print DEBUG "  concept 2: $d2\n";
	}
	
	
    } #end of defined --doubledef option
    
    
    #  if the --defraw option is not set clean up the defintions
    if($defraw_option == 0) {
	$d1 = lc($d1); $d2 = lc($d2);
	
	# remove punctuation doesn't contain '<' and '>' and '_'    
	$d1=~s/[\.\,\?\/\'\"\;\:\[\]\{\}\!\@\#\$\%\^\&\*\(\)\-\+\-\=]//g;
	$d2=~s/[\.\,\?\/\'\"\;\:\[\]\{\}\!\@\#\$\%\^\&\*\(\)\-\+\-\=]//g;
	
	if (defined $debugfile) { 
	    print DEBUG "AFTER --defraw PROCESSING\n";
	    print DEBUG "  concept 1: $d1\n";
	    print DEBUG "  concept 2: $d2\n";
	}
    }
    

    # find compound words
    if(defined $compoundfile) { 
	$d1 = findCompoundWord($d1, \%complist);
	$d2 = findCompoundWord($d2, \%complist);
	if (defined $debugfile) { 
	    print DEBUG "AFTER --compoundfile PROCESSING\n";
	    print DEBUG "  concept 1: $d1\n";
	    print DEBUG "  concept 2: $d2\n";
	}
    }
    
    
    # if --stopword option is set remove stop words
    if (defined $stoplist) { 
	my @def1 = split(/\s/, $d1);	
	my @def2 = split(/\s/, $d2);	
	my @new_def1 = ();
	my @new_def2 = ();
	foreach my $w (@def1) {
	    if (!($w =~ /$stopregex/)) {
		push (@new_def1, $w);}
	}
	foreach my $w (@def2) {
	    if (!($w =~ /$stopregex/)) {
		push (@new_def2, $w);}
	}
	
	$d1 = join (" ", @new_def1);	
	$d2 = join (" ", @new_def2);	
	
	if (defined $debugfile) { 
	    print DEBUG "AFTER --stoplist PROCESSING\n";
	    print DEBUG "  concept 1: $d1\n";
	    print DEBUG "  concept 2: $d2\n";
	}
    } #end of stoplist option
    
    
    if(defined $stem) { 
	my @def_words1 = split(/\s/, $d1);
	my $stemmed_words1 = Lingua::Stem::En::stem({ -words => \@def_words1, -locale => 'en'});
	$d1 = join(" ", @{$stemmed_words1});
	
	my @def_words2 = split(/\s/, $d2);
	my $stemmed_words2 = Lingua::Stem::En::stem({ -words => \@def_words2, -locale => 'en'});
	$d2 = join(" ", @{$stemmed_words2});
	
	if (defined $debugfile) { 
	    print DEBUG "AFTER --stem PROCESSING\n";
	    print DEBUG "  concept 1: $d1\n";
	    print DEBUG "  concept 2: $d2\n";
	}
    }
    
    ###########################################################################
    #  We have the definitions in $d1 and $d2 -- now create the vector
    ###########################################################################
    
    my @defs1 = split(" ", $d1);	
    my @defs2 = split(" ", $d2);	
    
    
    my %index   = ();
    my %d1index = ();
    my %d2index = ();

    foreach my $term (@defs1) { $d1index{$term}++; $index{$term}++; }
    foreach my $term (@defs2) { $d2index{$term}++; $index{$term}++; }
    
    my $vec1 = Math::SparseVector->new;
    my $vec2 = Math::SparseVector->new;
    
    my $counter = 0; 
    foreach my $term (sort keys %index) { 
	if(exists $d1index{$term}) { my $v = $d1index{$term}; $vec1->set($counter,$v); }
	if(exists $d2index{$term}) { my $v = $d2index{$term}; $vec2->set($counter,$v); }
	$counter++;
    }

    $vec1->normalize;
    $vec2->normalize;
    
    my $score = $vec1->dot($vec2);
    
    return $score;
 }

###########################################################################
# Subroutine to identify the compound words in the definition
###########################################################################
sub findCompoundWord {
    my $def = shift;
    my $ref_complist = shift;
    my $new_def = "";
    
    my @words = split(' ', $def);
    my $size_line = @words;
    for (my $i=0; $i<$size_line; $i++) { 
	
	my $w            = $words[$i];
	my $flag_print_w = 0;
	my $flag_comp    = 0;
	
	if(defined $ref_complist->{$w}) { 
	    # get the compound list start with word $w
	    my @comps = @{$ref_complist->{$w}};
	    
	    #compare the rest of the compound word  
	    foreach my $c (@comps) { 
		my @string = split(' ', $c);
		my $count = 1;
		foreach my $s (@string) {
		    if (($i+$count)<$size_line) {
			if ($s eq $words[$i+$count]) {
			    $flag_comp = 1;
			    $count++;
			}
			else {
			    $flag_comp = 0;
			    last;
			}
		    }
		} # test one compound word start by $w           
		
		 # connect the compound word     
		if ($flag_comp==1) {
		    unshift(@string, "$w");
		    my $comp = join('_', @string);
		    $new_def .= "$comp ";
		    if (defined $debugfile) { print DEBUG "compounds: $comp\n"; } 
		    my $skip = @string-1;
		    $i = $i + $skip;
		    last;
		}
	    } # test all the compound word start by $w  
	    
	    # print out the $w if it doesn't match any compound words
	    if (($flag_print_w==0) and ($flag_comp==0)) {
		$new_def .= "$w ";
		$flag_print_w = 1;
	    }
	    
	} # end of defined compound word start by $w
	
	if(!defined $ref_complist->{$w}) {
	    $new_def .= "$w ";
	}
    } # end of one definition 
    
     return $new_def;   
}

1;

__END__

=head1 NAME

UMLS::Similarity::vector - Perl module for computing semantic relatedness
of concepts in the Unified Medical Language System (UMLS) using first order 
vectors 

=head1 SYNOPSIS

  use UMLS::Interface;
  use UMLS::Similarity::vector;

  my $umls = UMLS::Interface->new(); 
  die "Unable to create UMLS::Interface object.\n" if(!$umls);

  my $vector = UMLS::Similarity::vector->new($umls);
  die "Unable to create measure object.\n" if(!$vector);

  my $cui1 = "C0018563";
  my $cui2 = "C0037303";

  $ts1 = $umls->getTermList($cui1);
  my $term1 = pop @{$ts1};

  $ts2 = $umls->getTermList($cui2);
  my $term2 = pop @{$ts2};

  my $value = $vector->getRelatedness($cui1, $cui2);

  print "The similarity between $cui1 ($term1) and $cui2 ($term2) is $value\n";

=head1 DESCRIPTION

--defraw option 

This is a flag for the vector measure. The definitions 
used are 'cleaned'. If the --defraw flag is set they will not be cleaned, 
and it will leave the definitions in their "raw" form. 
If the --defraw and --stem option use together, the --stem option
will cancel the request for "raw" defintion which is set by --defraw.


--dictfile option 

This is a dictionary file for the vector measure. It 
contains the 'definitions' of a concept which would be used in the 
relatedness computation. When this option is set, for the input 
pair, umls-similarity.pl first find the CUIs or terms definition in 
the dictfile. If the --config option is set, umls-similarity.pl will
find the definition in dictfile and in UMLS. And then, the relatedness 
is computed by the combinition of UMLS and dictfile defintions. 

If the --dictfile option is not set, the definiton will only come from the UMLS 
defintion by the --config option. 

The input pair could be the following formats.

    1. cui1/term1 cui2/term2 
       without --dictfile option and without --config option, 
       use the UMLS definition of the default config file. 

    2. cui1/term1 cui2/term2  --dictfile ./sample/dictfile
       --dictfile option is set and without --config option, 
       definitions only come from dictfile. 

    3. cui1/term1 cui2/term2  --config ./sample/vectormeasure.config
       without --dictfile option, --config option is set, 
       definitions only come from UMLS by the config file. 

    4. cui1/term1 cui2/term2  --dictfile ./sample/dictfile --config ./sample/vectormeasure.config
       --dictfile option is set, --config option is set, 
       definitions come from dictfile and UMLS. If the associated term 
       for each CUI is defined in the dictfile, the associated terms' 
       definition are also included.  

Terms in the dictionary file use the delimiter : to seperate the terms and
their definition. It allows multi terms in one concept. Please see the sample 
file at /sample/dictfile.  

--doubledef option 

This a dictionary file for the vector measure. It contains the 
'definitons' of a concept which could be used in the relatedness computation. 
When this option is defined, for each unique word in the definition, it uses the word's 
definition in the doubledef file. 

    For example, the original defintion for 'cat' is, 
    cat: a feline pet, feline 

    And then, the word vector for feline and pet in the doubledef file is: 
    feline: small to medium-sized cats, cougar cheetah
    pet: cat dog bird fish

    The final definition for cat is to combine the original definition for cat, and 
    then add the definition for feline(only add once) and pet. 

    cat: a feline pet small to medium-sized cats cougar cheetah cat dog bird fish

    For every unique word of the final definition, the doubledef finds the vector from the 
    co-occurrence matrix of each word and build the vector for cat.  

Terms in the --doubledef file use the delimiter : to seperate the terms and
their definition. It has the same format with the dictfile. Please see the
sample file at /sample/dictfile. We extract the definition from
the WordNet by glossFinder. For the extraced file, we further parse
each senses of the same word and obtain a complete definition of the
word.

--compoundfile options 

This is a compound word list for the vector or lesk measure. 
It defines the compound words which are treated as one word in the definitions. 
This must be used with the vector or lesk method. When use this option, the 
vectorindex and vectormatrix file must be generated by the corpus which also 
use the same compound words file. 

    For example, the definition for iraq and france are: 

    iraq : saddam hussein
    france : jacques chirac

    In the --compoundfile file, "saddam hussein" and "jacques chirac" are compounds:

    jacques_chirac
    saddam_hussein

    So, the compound words in the definition could be detected:

    iraq : saddam_hussein
    france : jacques_chirac

The program searches the vectors for "saddam_hussein" and "jacques_chirac" in 
the vectorindex and vectormatrix file. The thing need to pay attention is 
the original text must be preprocessed by searching and replacing the compounds. 
find-compounds.pl in the Text-NSP package can help to do that. So, both the vectorindex
and the vectormatrix files are built based on the the same compound words.  

--config option 

This is configure file for the lesk or vector measure. It defines 
the relationship, source and rela relationship. When compute the relatedness
of a pair, umls-similarity.pl find the corresponding relationshps and 
source by the config file.  

--stoplist option 

This is a word list file for the vector measure. The words
in the file should be removed from the definition. In the stop list file, 
each word is in the regular expression format. A stop word sample file 
is under the samples folder which is called stoplist-nsp.regex.

--stem option 

This is a flag for the vector measure. If we the --stem flag
is set, the words of the definition are stemmed by the the Porter Stemming
algorithm. If this option is used, the original text should be stemmed too. 
Otherwise, the stemmed words cannot find the its corresponding index in the 
index file.  

=head1 USAGE

The semantic relatedness modules in this distribution are built as classes
that expose the following methods:
  new()
  getRelatedness()

For the getRelatednes() function, it accepts different combinations of CUIs and 
Terms. The following is the basic logic: 


=head1 TYPICAL USAGE EXAMPLES

To create an object of the vector measure, we would have the following
lines of code in the perl program. 

   use UMLS::Similarity::vector;
   $measure = UMLS::Similarity::vector->new($interface);

The reference of the initialized object is stored in the scalar
variable '$measure'. '$interface' contains an interface object that
should have been created earlier in the program (UMLS-Interface). 

If the 'new' method is unable to create the object, '$measure' would 
be undefined. 

To find the semantic relatedness of the concept 'blood' (C0005767) and
the concept 'cell' (C0007634) using the measure, we would write
the following piece of code:

   $relatedness = $measure->getRelatedness('C0005767', 'C0007634');

=head1 CONFIGURATION OPTION

The UMLS-Interface package takes a configuration file to determine 
which sources and relations to use when obtaining the extended 
definitions. We call the definition used by the measure, the extended 
definition because this may include definitions from related concepts. 

The format of the configuration file is as follows:

SABDEF :: <include|exclude> <source1, source2, ... sourceN>

RELDEF :: <include|exclude> <relation1, relation2, ... relationN>

The possible relations that can be included in RELDEF are:
  1. all of the possible relations in MRREL such as PAR, CHD, ...
  2. CUI which refers the concepts definition
  3. ST which refers to the concepts semantic types definition
  4. TERM which refers to the concepts associated terms

For example, if we wanted to use the definitions from MSH vocabulary 
and we only wanted the definition of the CUI and the definitions of the 
CUIs SIB relation, the configuration file would be:

SABDEF :: include MSH
RELDEF :: include CUI, SIB

Note: RELDEF takes any of MRREL relations and two special 'relations':

      1. CUI which refers to the CUIs definition

      2. TERM which refers to the terms associated with the CUI


If you go to the configuration file directory, there will 
be example configuration files for the different runs that 
you have performed.

For more information about the configuration options please 
see the README.

=head1 SEE ALSO

perl(1), UMLS::Interface

perl(1), UMLS::Similarity

=head1 CONTACT US

  If you have any trouble installing and using UMLS-Similarity, 
  please contact us via the users mailing list :

      umls-similarity@yahoogroups.com

  You can join this group by going to:

      http://tech.groups.yahoo.com/group/umls-similarity/

  You may also contact us directly if you prefer :

      Bridget T. McInnes: bthomson at cs.umn.edu 

      Ted Pedersen : tpederse at d.umn.edu

=head1 AUTHORS

  Bridget T McInnes <bthomson at cs.umn.edu>
  Siddharth Patwardhan <sidd at cs.utah.edu>
  Serguei Pakhomov <pakh0002 at umn.edu>
  Ted Pedersen <tpederse at d.umn.edu>
  Ying Liu <liux0935 at umn.edu> 

=head1 COPYRIGHT AND LICENSE

Copyright 2004-2011 by Bridget T McInnes, Siddharth Patwardhan, 
Serguei Pakhomov, Ying Liu and Ted Pedersen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
