# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006 Craig Meyer, meyercr@gmail.com
# Copyright (C) 2006-2014 Michael Daum http://michaeldaumconsulting.com
#
# Based on ImgPlugin
# Copyright (C) 2006 Meredith Lesly, msnomer@spamcop.net
#
# and Foswiki Contributors. All Rights Reserved. Foswiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# For licensing info read LICENSE file in the Foswiki root.

package Foswiki::Plugins::ImagePlugin;

use strict;
use warnings;

our $imageCore;
our $baseWeb;
our $baseTopic;

our $VERSION = '3.30';
our $RELEASE = '3.30';
our $NO_PREFS_IN_TOPIC = 1;
our $SHORTDESCRIPTION = 'Image and thumbnail services to display and alignment images using an easy syntax';

use Foswiki::Plugins ();
use Foswiki::Meta ();

###############################################################################
sub initPlugin {
  ($baseTopic, $baseWeb) = @_;

  # check for Plugins.pm versions
  if ($Foswiki::Plugins::VERSION < 1.026) {
    Foswiki::Func::writeWarning("Version mismatch between ImagePlugin and Plugins.pm");
    return 0;
  }

  # init plugin variables
  $imageCore = undef;

  # register the tag handlers
  Foswiki::Func::registerTagHandler(
    'IMAGE',
    sub {
      return getCore($baseWeb, $baseTopic, shift)->handleIMAGE(@_);
    }
  );

  # register rest handler
  Foswiki::Func::registerRESTHandler(
    'resize',
    sub {
      getCore($baseWeb, $baseTopic, shift)->handleREST(@_);
    },
    authenticate => 0
  );

  # register jquery.imagetooltip plugin if jquery is isntalled
  if ($Foswiki::cfg{Plugins}{JQueryPlugin}{Enabled}) {
    require Foswiki::Plugins::JQueryPlugin;
    Foswiki::Plugins::JQueryPlugin::registerPlugin("ImageTooltip", 'Foswiki::Plugins::ImagePlugin::IMAGETOOLTIP');
  }

  # Plugin correctly initialized
  return 1;
}

###############################################################################
# lazy initializer
sub getCore {
  return $imageCore if $imageCore;

  Foswiki::Func::addToZone("head", "IMAGEPLUGIN", <<'HERE');
<link rel="stylesheet" href="%PUBURLPATH%/%SYSTEMWEB%/ImagePlugin/style.css" type="text/css" media="all" />
HERE

  require Foswiki::Plugins::ImagePlugin::Core;
  $imageCore = new Foswiki::Plugins::ImagePlugin::Core(@_);
  return $imageCore;
}

###############################################################################
sub afterRenameHandler {

  getCore($baseWeb, $baseTopic)->afterRenameHandler(@_);
}

###############################################################################
sub commonTagsHandler {

  return unless $Foswiki::cfg{ImagePlugin}{RenderExternalImageLinks};

  # only render an external image link when in view mode
  return unless Foswiki::Func::getContext()->{view};

  my ($text, $topic, $web) = @_;

  #print STDERR "called commonTagsHandler($web, $topic, $included)\n";

  # Have our own _externalLink early enough in the rendering loop
  # so that we know which topic we are rendering the url for. This now
  # happens as part of the macro expansion and not as part of the tml rendering
  # loop.

  my $removed = {};
  $text = takeOutBlocks($text, 'noautolink', $removed);

  $text =~ s/(^|(?<!url)[-*\s(|])
               (https?:
                   ([^\s<>"]+[^\s*.,!?;:)<|][^\s]*\.(?:gif|jpe?g|png|bmp|svg)(?:\?.*)?(?=[^\w])))/
                     renderExternalLink($web, $topic, $1, $2)/geox;
  putBackBlocks(\$text, $removed, 'noautolink', 'noautolink' );

  # restore the text
  $_[0] = $text;
}

###############################################################################
# compatibility wrapper 
sub takeOutBlocks {
  my ($text, $tag, $map) = @_;

  return '' unless $text;

  return Foswiki::takeOutBlocks($text, $tag, $map) if defined &Foswiki::takeOutBlocks;
  return $Foswiki::Plugins::SESSION->renderer->takeOutBlocks($text, $tag, $map);
}

###############################################################################
# compatibility wrapper 
sub putBackBlocks {
  return Foswiki::putBackBlocks(@_) if defined &Foswiki::putBackBlocks;
  return $Foswiki::Plugins::SESSION->renderer->putBackBlocks(@_);
}

###############################################################################
sub renderExternalLink {
  my ($web, $topic, $prefix, $url) = @_;

  #print STDERR "called renderExternalLink($web, $topic, $url)\n";

  my $href = '';
  my $title = $url;

  my $session = $Foswiki::Plugins::SESSION;
  my $pubUrl = $session->getPubUrl(1);

  # skip "external links" to self and to any other excluded url
  my $excludePattern = $Foswiki::cfg{ImagePlugin}{Exclude};
  if ($url !~ /^$pubUrl/ && 
      (!$excludePattern || $url !~ /^$excludePattern()/)) { 

    # untaint url, check above
    $url = Foswiki::Sandbox::untaintUnchecked($url);
    $url =~ s/\?.*$//;

    my $params = {
      _DEFAULT => "$url",
      href => $href,
      title => $title,
      type => 'simple',
      web => $web,
      topic => $topic
    };

    return $prefix.getCore($baseWeb, $baseTopic)->handleIMAGE($params, $topic, $web);
  }

  #print STDERR "normal handling of $url\n";

  # else, return the orig url
  return $prefix.$url;
}

1;

