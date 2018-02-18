# dbif.pm version 0.01
# (Updated 08/12/2004 -- Sid)
#
# Package used by WordNet::Similarity::vector module that
# computes semantic relatedness of word senses in WordNet
# using gloss vectors. This module provides a BerkeleyDB
# interface into the word vectors database (BerkeleyDB).
#
# Copyright (c) 2004,
#
# Siddharth Patwardhan, University of Utah, Salt Lake City
# sidd@cs.utah.edu
#
# Ted Pedersen, University of Minnesota, Duluth
# tpederse@d.umn.edu
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

package dbif;

use strict;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use BerkeleyDB;

@ISA = qw(Exporter);

%EXPORT_TAGS = ();

@EXPORT_OK = ();

@EXPORT = ();

$VERSION = '0.01';

sub new
{
    my $className = shift;
    my $dbfile = shift;
    my $subName = shift;
    my $create = shift;
    my $self = {};
    
    return undef if(!defined $dbfile);
    
    if(defined $subName) {
	if(defined $create && $create) {
	    tie %{$self->{'dbHash'}}, "BerkeleyDB::Hash",
	    Filename => "$dbfile",
	    Subname => "$subName",
	    Flags    => DB_CREATE
		or return undef;
	}
	else {
	    tie %{$self->{'dbHash'}}, "BerkeleyDB::Hash",
	    Filename => "$dbfile",
	    Subname => "$subName"
		or return undef;
	}
    }
    else {
	if(defined $create && $create) {
	    tie %{$self->{'dbHash'}}, "BerkeleyDB::Hash",
	    Filename => "$dbfile",
	    Flags    => DB_CREATE
		or return undef;
	}
	else {
	    tie %{$self->{'dbHash'}}, "BerkeleyDB::Hash",
	    Filename => "$dbfile"
		or return undef;
	}
    }
    
    bless($self, $className);
    
    return $self;
}

sub getValue
{
    my $self = shift;
    my $key = shift;

    return undef if(!defined $key);
    if(defined $self->{'dbHash'}->{$key})
    {
	return $self->{'dbHash'}->{$key};
    }
    return undef;
}

sub setValue
{
    my $self = shift;
    my $key = shift;
    my $value = shift;

    return 0 if(!defined $key || !defined $value);
    $self->{'dbHash'}->{$key} = $value;

    return 1;
}

sub getKeys
{
    my $self = shift;
    return keys %{$self->{'dbHash'}};
}

sub finalize
{
    my $self = shift;
    untie %{$self->{'dbHash'}};

    return 1;
}

1;
