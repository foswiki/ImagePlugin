#!/usr/bin/perl -w
# Standard preamble
BEGIN {
    unshift @INC, split( /:/, $ENV{FOSWIKI_LIBS} );
}

use TWiki::Contrib::Build;

package BuildBuild;
use base qw( TWiki::Contrib::Build );

sub new {
    my $class = shift;
    return bless( $class->SUPER::new( "ImagePlugin", "Build" ), $class );
}

package main;

# Create the build object
$build = new BuildBuild();

# Build the target on the command line, or the default target
$build->build($build->{target});

