#!/usr/bin/perl -w
# Standard preamble
BEGIN {
    unshift @INC, split( /:/, $ENV{FOSWIKI_LIBS} );
}

use Foswiki::Contrib::Build;

package BuildBuild;
use base qw( Foswiki::Contrib::Build );

sub new {
    my $class = shift;
    return bless( $class->SUPER::new( "ImagePlugin", "Build" ), $class );
}

package main;

# Create the build object
$build = new BuildBuild();

# Build the target on the command line, or the default target
$build->build($build->{target});

