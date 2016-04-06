# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006 Craig Meyer, meyercr@gmail.com
# Copyright (C) 2006-2016 Michael Daum http://michaeldaumconsulting.com
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

use Foswiki::Func ();
use Foswiki::Plugins ();

our $VERSION = '7.20';
our $RELEASE = '06 Apr 2016';
our $NO_PREFS_IN_TOPIC = 1;
our $SHORTDESCRIPTION = 'Image and thumbnail services to display and alignment images using an easy syntax';
our $core;

###############################################################################
sub initPlugin {

  # check for Plugins.pm versions
  if ($Foswiki::Plugins::VERSION < 1.026) {
    Foswiki::Func::writeWarning("Version mismatch between ImagePlugin and Plugins.pm");
    return 0;
  }

  # init plugin variables
  $core = undef;

  # register the tag handlers
  Foswiki::Func::registerTagHandler(
    'IMAGE',
    sub {
      return getCore(shift)->handleIMAGE(@_);
    }
  );

  # register rest handler
  Foswiki::Func::registerRESTHandler(
    'resize',
    sub {
      getCore(shift)->handleREST(@_);
    },
    authenticate => 0,
    validate => 0,
    http_allow => 'GET,POST',
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
  return $core if $core;

  Foswiki::Func::addToZone("head", "IMAGEPLUGIN", <<'HERE');
<link rel="stylesheet" href="%PUBURLPATH%/%SYSTEMWEB%/ImagePlugin/style.css" type="text/css" media="all" />
HERE

  require Foswiki::Plugins::ImagePlugin::Core;
  $core = Foswiki::Plugins::ImagePlugin::Core->new(@_);
  return $core;
}

###############################################################################
sub finishPlugin {
  $core->finishPlugin if defined $core;
}

###############################################################################
sub afterRenameHandler {

  getCore->afterRenameHandler(@_);
}

###############################################################################
sub beforeSaveHandler {
  #my ($text, $topic, $web, $meta) = @_;

  getCore->beforeSaveHandler(@_);
}

###############################################################################
sub completePageHandler {
  #my $text = $_[0];

  return unless $Foswiki::cfg{ImagePlugin}{ConvertInlineSVG};

  getCore->completePageHandler(@_);
}


###############################################################################
sub commonTagsHandler {

  return unless Foswiki::Func::getContext()->{view};
  return unless $Foswiki::cfg{ImagePlugin}{RenderExternalImageLinks} || $Foswiki::cfg{ImagePlugin}{RenderLocalImages};

  my ($text, $topic, $web) = @_;

  my $removed = {};
  $text = takeOutBlocks($text, 'noautolink', $removed);

  if ($Foswiki::cfg{ImagePlugin}{RenderExternalImageLinks}) {
    $text =~ s/(^|(?<!url)[-*\s(|])
                 (https?:
                     ([^\s<>"]+[^\s*.,!?;:)<|][^\s]*\.(?:gif|jpe?g|png|bmp|svg)(?:\?.*)?(?=[^\w\-])))/
                       renderExternalImage($web, $topic, $1, $2)/gieox;

  }

  if ($Foswiki::cfg{ImagePlugin}{RenderLocalImages}) {
    $text =~ s/(<img ([^>]+)?\/>)/renderLocalImage($web, $topic, $1)/ge;
  }

  putBackBlocks(\$text, $removed, 'noautolink', 'noautolink');

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
sub renderLocalImage {
  my ($web, $topic, $text) = @_;

  #print STDERR "renderLocalImage at $web.$topic from $text\n";

  my @args = ();

  my $file;
  my $imgWeb;
  my $imgTopic;

  my $defaultUrlHost = $Foswiki::cfg{DefaultUrlHost};
  $defaultUrlHost =~ s/^http:/https?:/;

  foreach my $attr (qw(src width height title align style class alt)) {
    if ($text =~ /$attr=["']([^"']+)["']/) {
      my $val = $1;

      if ($attr eq 'src') {
        if ($val =~ /^(?:$defaultUrlHost)?$Foswiki::cfg{PubUrlPath}\/(.*)\/([^\/]+)$/) {
          ($imgWeb, $imgTopic) = Foswiki::Func::normalizeWebTopicName(undef, $1);
          $file = $2;
          if ($imgWeb ne $web || $imgTopic ne $topic) {
            #print STDERR "excluding image at $imgWeb.$imgTopic\n" if $imgWeb ne $Foswiki::cfg{SystemWebName};
            return $text;
          }
          push @args, "topic=\"$imgWeb.$imgTopic\"" if $imgWeb ne $web || $imgTopic ne $topic;
        } else {
          # not a local image -> return original text
          #print STDERR "not a local image: $val\n";
          return $text;
        }
      } elsif (($attr eq 'width' || $attr eq 'height') && $val !~ /^\d+(px)?$/) {
        return $text; # this is not a px unit ... keep the img as it is
      } else {
        push @args, "$attr=\"$val\"";
      }
    }
  }

  return $text unless defined $file; # oh well ... can't extract src

  push @args, 'type="plain"';

  my $result = "%IMAGE{\"$file\" ".join(" ", @args)."}%";

  #print STDERR "result=$result\n";

  return $result;
}

###############################################################################
sub renderExternalImage {
  my ($web, $topic, $prefix, $url) = @_;

  my $href = '';
  my $title = $url;

  my $pubUrl = getPubUrl();

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

    return $prefix.getCore()->handleIMAGE($params, $topic, $web);
  }

  #print STDERR "normal handling of $url\n";

  # else, return the orig url
  return $prefix.$url;
}

###############################################################################
sub getPubUrl {
  my $session = $Foswiki::Plugins::SESSION;

  if ($session->can("getPubUrl")) {
    # pre 1.2
    return $session->getPubUrl(1);
  } 

  # post 1.2
  return Foswiki::Func::getPubUrlPath(absolute=>1);
}

1;

