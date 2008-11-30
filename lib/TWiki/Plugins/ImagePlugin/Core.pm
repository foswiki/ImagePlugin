# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006 Craig Meyer, meyercr@gmail.com
# Copyright (C) 2006-2008 Michael Daum http://michaeldaumconsulting.com
#
# Based on ImgPlugin
# Copyright (C) 2006 Meredith Lesly, msnomer@spamcop.net
#
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
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
# For licensing info read LICENSE file in the TWiki root.

package TWiki::Plugins::ImagePlugin::Core;

use strict;

BEGIN {
  # coppied over from TWiki.pm to cure Item3087
  # Image::Magick seems to override locale usage
  if ( $TWiki::cfg{UseLocale} ) {
    $ENV{LC_CTYPE} = $TWiki::cfg{Site}{Locale};
    require POSIX;
    import POSIX qw( locale_h LC_CTYPE );
    setlocale(&LC_CTYPE, $TWiki::cfg{Site}{Locale});
  }
};

use vars qw(
  $frameFormat $linkFormat $simpleFormat $plainFormat
  $magnifyFormat $captionFormat $floatFormat
  $clearFormat
);

use constant DEBUG => 0; # toggle me

# SMELL: become plugin preference values
$linkFormat = 
  '<a id="$id" class="imageLink" href="$href" title="$title" style="$style">$text</a>';

$plainFormat = 
  '<img class="imagePlain imagePlain_$align $class" border="0" src="$src" alt="$alt" title="$title" width="$width" height="$height" '.
  'longdesc="$desc" $mousein $mouseout style="$style" align="$align" />';

$simpleFormat = 
  '<a href="$href" id="$id" class="imageHref imageSimple imageSimple_$align $class" title="$title" style="$style">'.
    '<img border="0" src="$src" alt="$alt" width="$width" height="$height" longdesc="$desc" $mousein $mouseout/>'.
  '</a>';
  
$frameFormat = 
  '<div id="$id" class="imageFrame imageFrame_$align $class" style="_width:$framewidthpx;max-width:$framewidthpx;$style">'.
    '<a href="$href" class="imageHref" title="$title">'.
      '<img border="0" src="$src" alt="$alt" width="$width" height="$height" longdesc="$desc" $mousein $mouseout/>'.
    '</a> '.
    '$captionFormat'.
  ' </div>';

$floatFormat = 
  '<div id="$id" class="imageFloat imageFloat_$align $class" style="$style">'.
    '<a href="$href" class="imageHref" title="$title">'.
      '<img border="0" src="$src" alt="$alt" width="$width" height="$height" longdesc="$desc" $mousein $mouseout/>'.
    '</a> '.
    '$captionFormat'.
  ' </div>';

$clearFormat =
  '<br class="imageClear" clear="all" />';
 
# helper formats
$captionFormat =
  '<div class="imageCaption"> $caption </div>';

$magnifyFormat =
  '<div class="imageMagnify">'.
    '<a href="$href" title="Enlarge">'.
      '<img border="0" src="$magnifyIcon" width="$magnifyWidth" height="$magnifyHeight" alt="Enlarge" />'.
    ' </a>'.
  '</div>';

###############################################################################
# static
sub writeDebug {
  print STDERR "ImagePlugin - $_[0]\n" if DEBUG;
}

###############################################################################
# ImageCore constructor
sub new {
  my ($class, $baseWeb, $baseTopic) = @_;
  my $this = bless({}, $class);

  $this->{magnifyIcon} = 
    TWiki::Func::getPluginPreferencesValue('IMAGEPLUGIN_MAGNIFY_ICON') ||
    '%PUBURLPATH%/%SYSTEMWEB%/ImagePlugin/magnify-clip.png';
  $this->{magnifyWidth} = 15; # TODO: make this configurable/autodetected/irgnored
  $this->{magnifyHeight} = 11; # TODO: make this configurable/autodetected/irgnored

  $this->{thumbSize} = 
    TWiki::Func::getPreferencesValue('THUMBNAIL_SIZE') || 180;
  $this->{baseWeb} = $baseWeb;
  $this->{baseTopic} = $baseTopic;
  $this->{errorMsg} = ''; # from image mage

  # Graphics::Magick is less buggy than Image::Magick
  my $impl = 
    $TWiki::cfg{ImagePlugin}{Impl} || 
    $TWiki::cfg{ImageGalleryPlugin}{Impl} || 
    'Image::Magick'; 

  writeDebug("creating new image mage using $impl");
  eval "use $impl";
  die $@ if $@;
  $this->{mage} = new $impl;
  writeDebug("done");

  return $this;
}

###############################################################################
sub handleIMAGE {
  my ($this, $session, $params, $theTopic, $theWeb) = @_;

  writeDebug("called handleIMAGE(params, $theTopic, $theWeb)");

  if($params->{_DEFAULT} =~ m/clr|clear/i ){ # SMELL: non-documented feature
    return $clearFormat;
  }

  # read parameters
  my $argsStr = $params->{_DEFAULT} || '';
  $argsStr =~ s/^\[\[//o;
  $argsStr =~ s/\]\]$//o;
  $params->{type} ||= '';
  $this->parseWikipediaParams($params, $argsStr);

  # default and fix parameters
  $params->{warn} ||= '';
  $params->{size} ||= '';
  $params->{width} ||= '';
  $params->{height} ||= '';
  $params->{caption} ||= '';
  $params->{align} ||= 'none';
  $params->{class} ||= '';
  $params->{footer} ||= '';
  $params->{header} ||= '';
  $params->{id} ||= '';
  $params->{mousein} ||= '';
  $params->{mouseout} ||= '';
  $params->{style} ||= '';

  # validate args
  $params->{type} = 'thumb' if $params->{type} eq 'thumbnail';
  if ($params->{type} eq 'thumb' && !$params->{size}) {
    $params->{size} = $this->{thumbSize}
  }
  $params->{type} = 'plain' unless $params->{type};
  if ($params->{size} =~ /^(\d+)(px)?x?(\d+)?(px)?$/) {
    $params->{size} = $3?"$1x$3":$1;
  }

  my $origFile = $params->{file} || $params->{_DEFAULT};
  my $imgWeb = $params->{web} || $theWeb;
  my $imgTopic;
  my $imgPath;
  my $pubDir = TWiki::Func::getPubDir();
  my $pubUrlPath = TWiki::Func::getPubUrlPath();
  my $urlHost = TWiki::Func::getUrlHost();
  my $pubUrl = $urlHost.$pubUrlPath;
  my $albumTopic;
  my $query = TWiki::Func::getCgiQuery();
  my $doRefresh = $query->param('refresh') || 0;
  $doRefresh = ($doRefresh =~ /^(on|1|yes)$/g)?1:0;

  # search image
  if ($origFile =~ /^https?:\/\/.*/) {
    require LWP::UserAgent;
    require Digest::MD5;
    my $url = $origFile;
    my $ext = '';
    if ($url =~ /(\.[a-zA-Z]+)$/) {
      $ext = $1;
    }
    $origFile = '_img'.Digest::MD5::md5_hex($url).$ext;
    $imgTopic = $params->{topic} || $theTopic;
    ($imgWeb, $imgTopic) = 
      TWiki::Func::normalizeWebTopicName($imgWeb, $imgTopic);
    $imgPath = $pubDir.'/'.$imgWeb;
    mkdir($imgPath) unless -d $imgPath;
    $imgPath .= '/'.$imgTopic;
    mkdir($imgPath) unless -d $imgPath;
    $imgPath .= '/'.$origFile;
    unless (-e $imgPath && !$doRefresh) {
      writeDebug("fetching $url into $imgPath");
      my $ua = LWP::UserAgent->new;
      $ua->timeout(10);
      $ua->env_proxy;
      my $response = $ua->mirror($url, $imgPath);
      unless ($response->is_success) {
        my $status = $response->status_line;
        $this->{errorMsg} = "can't fetch image from <nop>'$url': $status";
        return $this->inlineError($params);
      }
    }
  } elsif ($origFile =~ /^(?:$pubUrl|$pubUrlPath)?(.*)\/(.*?)$/) {
    # part of the filename
    $origFile = $2;
    ($imgWeb, $imgTopic) = TWiki::Func::normalizeWebTopicName($imgWeb, $1);
    $imgPath = $pubDir.'/'.$imgWeb.'/'.$imgTopic.'/'.$origFile;

    writeDebug("looking for an image file at $imgPath");

    # you said so but it still is not there
    unless (-e $imgPath) {
      $this->{errorMsg} = "(1) can't find <nop>$origFile at <nop>$imgWeb.$imgTopic";
      return $this->inlineError($params);
    }
  } else {
    my $testWeb;
    my $testTopic;

    if ($params->{topic}) {
      # topic parameter is known
      $imgTopic = $params->{topic};
      ($testWeb, $testTopic) = 
	TWiki::Func::normalizeWebTopicName($imgWeb, $imgTopic);
      $imgPath = $pubDir.'/'.$testWeb.'/'.$testTopic.'/'.$origFile;

      # you said so but it still is not there
      unless (-e $imgPath) {
	$this->{errorMsg} = "(2) can't find <nop>$origFile at <nop>$testWeb.$testTopic";
	return $this->inlineError($params);
      }
      # found at given web-topic
      $imgWeb = $testWeb;
      $imgTopic = $testTopic;
    } else {
      # check current topic and then the album topic
      ($testWeb, $testTopic) =
	TWiki::Func::normalizeWebTopicName($imgWeb, $theTopic);
      $imgPath = $pubDir.'/'.$testWeb.'/'.$testTopic.'/'.$origFile;
      unless (-e $imgPath) {
	# no, then look in the album
	$albumTopic = TWiki::Func::getPreferencesValue('IMAGEALBUM', 
	  ($testWeb eq $theWeb)?undef:$testWeb);
	unless ($albumTopic) {
	  # not found, and no album
	  $this->{errorMsg} = "(3) can't find <nop>$origFile in <nop>$imgWeb";
	  return $this->inlineError($params);
	}
	$albumTopic = 
	  TWiki::Func::expandCommonVariables($albumTopic, $testTopic, $testWeb);
	($testWeb, $testTopic) =
	  TWiki::Func::normalizeWebTopicName($imgWeb, $albumTopic);
	$imgPath = $pubDir.'/'.$testWeb.'/'.$testTopic.'/'.$origFile;

	# not found in album
	unless (-e $imgPath) {
	  $this->{errorMsg} = "(4) can't find <nop>$origFile in <nop>$testWeb.$testTopic";
	  return $this->inlineError($params);
	}
	# found in album
	$imgWeb = $testWeb;
	$imgTopic = $testTopic;
      } else {
	# found at current topic
	$imgWeb = $testWeb;
	$imgTopic = $testTopic;
      }
    }
  }

  writeDebug("origFile=$origFile, imgWeb=$imgWeb, imgTopic=$imgTopic");

  my $origFileUrl = $pubUrl.'/'.$imgWeb.'/'.$imgTopic.'/'.$origFile;
  $params->{alt} ||= $origFile;
  $params->{title} ||= $params->{caption} || $origFile;
  $params->{desc} ||= $params->{title};
  $params->{href} ||= $origFileUrl;

  writeDebug("type=$params->{type}, align=$params->{align}");
  writeDebug("size=$params->{size}, width=$params->{width}, height=$params->{height}");

  # compute image
  my $imgInfo = 
    $this->getImageInfo($imgWeb, $imgTopic, $origFile, 
      $params->{size}, $params->{width}, $params->{height}, $doRefresh);

  unless ($imgInfo) {
    #TWiki::Func::writeWarning("ImagePlugin - $this->{errorMsg}");
    return $this->inlineError($params);
  }

  # For compatibility with i18n-characters in file names, encode urls (as TWiki.pm/viewfile does for attachment names in general)
  my $thumbFileUrl = $pubUrl.'/'.$imgWeb.'/'.$imgTopic.'/'.$imgInfo->{file};
  $thumbFileUrl = TWiki::urlEncode($thumbFileUrl);

  # format result
  my $result = $params->{format} || '';
  if (!$result) {
    if ($params->{type} eq 'plain') {
      $result = $plainFormat;
    } elsif ($params->{type} eq 'simple') {
      $result = $simpleFormat;
    } elsif ($params->{type} eq 'link') {
      $result = $linkFormat;
    } elsif ($params->{type} eq 'frame') {
      $result = $frameFormat;
      $result =~ s/\$captionFormat/$captionFormat/g 
	if $params->{caption};
    } elsif ($params->{type} eq 'thumb') {
      $result = $frameFormat; 
      my $thumbCaption = $magnifyFormat.$params->{caption};
      $result =~ s/\$captionFormat/$captionFormat/g;
      $result =~ s/\$caption/$thumbCaption/g;
    } else {
      $result = $floatFormat;
      $result =~ s/\$captionFormat/$captionFormat/g 
	if $params->{caption};
    }
  }

  $result =  $params->{header}.$result.$params->{footer};
  $result =~ s/\$captionFormat//g;

  $result =~ s/\$caption/$params->{caption}/g;
  $result =~ s/\$magnifyFormat/$magnifyFormat/g;
  $result =~ s/\$magnifyIcon/$this->{magnifyIcon}/g;
  $result =~ s/\$magnifyWidth/$this->{magnifyWidth}/g;
  $result =~ s/\$magnifyHeight/$this->{magnifyHeight}/g;

  if ($params->{mousein}) {
    $result =~ s/\$mousein/onmouseover="$params->{mousein}"/g;
  } else {
    $result =~ s/\$mousein//go;
  }
  if ($params->{mouseout}) {
    $result =~ s/\$mouseout/onmouseout="$params->{mouseout}"/g;
  } else {
    $result =~ s/\$mouseout//go;
  }
  my $title = plainify($params->{title});
  my $desc = plainify($params->{desc});
  my $alt = plainify($params->{alt});
  my $href = $params->{href};

  $result =~ s/\$href/$href/g;
  $result =~ s/\$src/$thumbFileUrl/g;
  $result =~ s/\$height/$imgInfo->{height}/g;
  $result =~ s/\$width/$imgInfo->{width}/g;
  $result =~ s/\$origsrc/$origFileUrl/g;
  $result =~ s/\$origheight/$imgInfo->{origHeight}/g;
  $result =~ s/\$origwidth/$imgInfo->{origWidth}/g;
  $result =~ s/\$framewidth/($imgInfo->{width}+2)/ge;
  $result =~ s/\$text/$origFile/g;
  $result =~ s/\$class/$params->{class}/g;
  $result =~ s/\$id/$params->{id}/g;
  $result =~ s/\$style/$params->{style}/g;
  $result =~ s/\$align/$params->{align}/g;
  $result =~ s/\$alt/<noautolink>$alt<\/noautolink>/g;
  $result =~ s/\$title/<noautolink>$title<\/noautolink>/g;
  $result =~ s/\$desc/<noautolink>$desc<\/noautolink>/g;

  $result =~ s/\$dollar/\$/go;
  $result =~ s/\$percnt/\%/go;
  $result =~ s/\$n/\n/go;
  $result =~ s/\$nop//go;

  # recursive call for delayed TML expansion
  $result = &TWiki::Func::expandCommonVariables($result, $theTopic, $theWeb);
  return $result; 
} 

###############################################################################
sub plainify {
  my $text = shift;

  $text =~ s/<!--.*?-->//gs;          # remove all HTML comments
  $text =~ s/\&[a-z]+;/ /g;           # remove entities
  $text =~ s/\[\[([^\]]*\]\[)(.*?)\]\]/$2/g;
  $text =~ s/<[^>]*>//g;              # remove all HTML tags
  $text =~ s/[\[\]\*\|=_\&\<\>]/ /g;  # remove Wiki formatting chars
  $text =~ s/^\-\-\-+\+*\s*\!*/ /gm;  # remove heading formatting and hbar
  $text =~ s/^\s+//o;                  # remove leading whitespace
  $text =~ s/\s+$//o;                  # remove trailing whitespace
  $text =~ s/"/ /o;

  return $text;
}

###############################################################################
# get info about the image and its thumbnail cousin, resize source image if
# a $size was specified, returns a pointer to a hash with the following entries:
#    * file: the name of the source file or its thumbnail 
#    * width: width of the imgInfo{file}
#    * heith: heith of the imgInfo{file}
#    * origFile: the name of the source image
#    * origWidth: width of the source image
#    * origHeight: height of the source image
# returns undef on error
sub getImageInfo {
  my ($this, $imgWeb, $imgTopic, $imgFile, $size, $width, $height, $doRefresh) = @_;

  writeDebug("called getImageInfo($imgWeb, $imgTopic, $imgFile, $size, $width, $height, $doRefresh)");

  $this->{errorMsg} = '';

  my %imgInfo;
  $imgInfo{file} = $imgFile;
  $imgInfo{origFile} = $imgFile;

  my $imgPath = TWiki::Func::getPubDir().'/'.$imgWeb.'/'.$imgTopic;

  writeDebug("pinging $imgPath/$imgFile");
  ($imgInfo{origWidth}, $imgInfo{origHeight}) = $this->{mage}->Ping($imgPath.'/'.$imgFile);

  if ($size || $width || $height || $doRefresh) {
    my $newImgFile = "_${size}_${width}_${height}_$imgFile";

    if (-f $imgPath.'/'.$newImgFile && !$doRefresh) { # cached
      ($imgInfo{width}, $imgInfo{height}) = $this->{mage}->Ping($imgPath.'/'.$newImgFile);
    } else { 
      
      # read
      my $error = $this->{mage}->Read($imgPath.'/'.$imgFile);
      if ($error =~ /(\d+)/) {
	$this->{errorMsg} = $error;
	return undef if $1 >= 400;
      }
      
      # scale
      my %args;
      $args{geometry} = $size if $size;
      $args{width} = $width if $width;
      $args{height} = $height if $height;
      $error = $this->{mage}->Resize(%args);
      if ($error =~ /(\d+)/) {
	$this->{errorMsg} = $error;
	return undef if $1 >= 400;
      }
      
      # write
      $error = $this->{mage}->Write($imgPath.'/'.$newImgFile);
      if ($error =~ /(\d+)/) {
	$this->{errorMsg} .= " $error";
	return undef if $1 >= 400;
      }
      ($imgInfo{width}, $imgInfo{height}) = $this->{mage}->Get('width', 'height');

    }
    $imgInfo{file} = $newImgFile;
  } else {
    $imgInfo{width} = $imgInfo{origWidth};
    $imgInfo{height} = $imgInfo{origHeight};
  }

  # forget images
  my $mage = $this->{mage};
  @$mage = (); 
  
  return \%imgInfo;
} 

###############################################################################
# sets type (link,frame,thumb), file, width, height, size, caption
sub parseWikipediaParams {
  my ($this, $params, $argStr) = @_;

  return unless $argStr =~ /\|/g;

  my ($file, @args) = split(/\|/, $argStr);
  $params->{type} = 'link' if $file =~ s/^://o;
  $params->{file} = $file;

  foreach my $arg (@args) {
    $arg =~ s/^\s+//o;
    $arg =~ s/\s+$//o;
    if ($arg =~ /^(right|left|center|none)$/i ) {
      $params->{align} = $1 unless $params->{align};
    } elsif ($arg =~ /^frame$/i) {
      $params->{type} = 'frame';
    } elsif ($arg =~ m/^thumb(nail)?$/i) {
      $params->{type}= 'thumb' unless $params->{type};
    } elsif ($arg =~ /^(\d+)px$/i) {
      $params->{size} = $1 unless $params->{size};
    } elsif ($arg =~ /^w(\d+)px$/i) {
      $params->{width} = $1 unless $params->{width};
    } elsif ($arg =~ /^h(\d+)px$/i) {
      $params->{height} = $1 unless $params->{height};
    } else {
      $params->{caption} = $arg unless $params->{caption};
    }
  }
}

###############################################################################
sub inlineError {
  my ($this, $params) = @_;

  return '' if $params->{warn} eq 'off';
  return "<span class=\"foswikiAlert\">Error: $this->{errorMsg}</span>" unless $params->{warn};
  return $params->{warn};
}


###############################################################################
1;
