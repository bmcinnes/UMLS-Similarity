 #!/usr/bin/perl

my $compoundfile = shift; 
my $textfile = shift; 
	
#replace the compound words 
open(LST, "$compoundfile") or 
    die ("Error: cannot open file $compoundfile for input.\n");
	
# read the compound txt and put them in the hash array. 
my %complist = (); 

while (my $line = <LST>)
{
    chomp($line);
    my $lower_case = lc($line);
    my @string = split/\s+/, $lower_case; 
    my $head = shift(@string);
    
    my $rest = join (' ', @string);
    push (@{$complist{$head}}, $rest);
}
close LST;

# sort the compound txt 
foreach my $h (sort (keys (%complist)) )
{
    my @sort_list = sort(@{$complist{$h}});
    for my $i (0..$#sort_list)
    {
	$complist{$h}[$i] = $sort_list[$i];
    }
}

open(FILE, $textfile) || die "Could not open file ($textfile)\n";
while(<FILE>) { 
    chomp; 
    my $line = findCompoundWord($_, \%complist);
    print "$line\n";
}
    
close FILE;

sub findCompoundWord {
    
    my $def = shift;
    my $ref_complist = shift;
    my $new_def = "";
    
    my @words = split(' ', $def);
    my $size_line = @words;
    for (my $i=0; $i<$size_line; $i++)
    {
        my $w = $words[$i];
        my $flag_print_w = 0;
        my $flag_comp = 0;
        if(defined $ref_complist->{$w})
        {
            # get the compound list start with word $w
            my @comps = @{$ref_complist->{$w}};
            foreach my $c (@comps)
            {
                #compare the rest of the compound word
                my @string = split(' ', $c);
                my $count = 1;
                foreach my $s (@string)
                {
                    if (($i+$count)<$size_line)
                    {
                        if ($s eq $words[$i+$count])
                        {
                            $flag_comp = 1;
                            $count++;
                        }
                        else
                        {
                            $flag_comp = 0;
                            last;
                        }
                    }
                } # test one compound word start by $w
                # connect the compound word
                if ($flag_comp==1)
                {
                    unshift(@string, "$w");
		    
                    my $comp = join('_', @string);
                    $new_def .= "$comp ";
		    if (defined $debugfile)
                    {
                        print DEBUG "compounds: $comp\n";
                    }
                    my $skip = @string-1;
                    $i = $i + $skip;
                    last;
                }
            } # test all the compound word start by $w
	    
            # print out the $w if it doesn't match any compound words
            if (($flag_print_w==0) and ($flag_comp==0))
            {
                $new_def .= "$w ";
                $flag_print_w = 1;
            }
	    
        } # end of defined compound word start by $w
	
        if(!defined $ref_complist->{$w})
        {
            $new_def .= "$w ";
        }
    } # end of one definition
    
    return $new_def;
}


    
