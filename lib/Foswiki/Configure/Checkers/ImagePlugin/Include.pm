# Extension for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2026 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Configure::Checkers::ImagePlugin::Include;

use strict;
use warnings;

use Foswiki::Configure::Checker ();
our @ISA = ('Foswiki::Configure::Checker');

sub check_current_value {
  my ($this, $reporter) = @_;

  if ($Foswiki::cfg{ImagePlugin}{DownloadExternalImages} && $Foswiki::cfg{ImagePlugin}{Include} eq '') {
    $reporter->WARN("Security issue downloading external images unconditionally.");
  }
}

1;
