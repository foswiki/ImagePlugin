# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2026 Michael Daum, http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::ImagePlugin::IMAGEEDITOR;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins::JQueryPlugin::Plugin ();
use Foswiki::Plugins::ImagePlugin ();
our @ISA = qw( Foswiki::Plugins::JQueryPlugin::Plugin );

sub new {
  my $class = shift;

  my $this = bless(
    $class->SUPER::new(
      name => 'ImageEditor',
      version => $Foswiki::Plugins::ImagePlugin::VERSION,
      author => 'Michael Daum',
      homepage => 'http://foswiki.org/Extensions/ImagePlugin',
      puburl => '%PUBURLPATH%/%SYSTEMWEB%/ImagePlugin/build',
      documentation => "$Foswiki::cfg{SystemWebName}.ImagePlugin",
      javascript => ['imageEditor.js'],
      css => ['imageEditor.css'],
      dependencies => ['foswiki', 'ui', 'ui::dialog'],
    ),
    $class
  );

  return $this;
}

1;

