# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006 Craig Meyer, meyercr@gmail.com
# Copyright (C) 2006-2010 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::ImagePlugin::Core;

use strict;
use Error qw( :try );
use Foswiki::OopsException ();

BEGIN {
  # coppied over from TW*k*.pm to cure Item3087
  # Image::Magick seems to override locale usage
  my $useLocale = $Foswiki::cfg{UseLocale};
  my $siteLocale = $Foswiki::cfg{Site}{Locale};
  if ( $useLocale ) {
    $ENV{LC_CTYPE} = $siteLocale;
    require POSIX;
    import POSIX qw( locale_h LC_CTYPE );
    setlocale(&LC_CTYPE, $siteLocale);
  }
};

use constant DEBUG => 0; # toggle me

###############################################################################
# static
sub writeDebug {
  print STDERR "ImagePlugin - $_[0]\n" if DEBUG;
}

###############################################################################
# ImageCore constructor
sub new {
  my ($class, $baseWeb, $baseTopic, $session) = @_;
  my $this = bless({}, $class);

  $session ||= $Foswiki::Plugins::SESSION || $Foswiki::Plugins::SESSION;
  $this->{session} = $session;
  $this->{magnifyIcon} = 
    Foswiki::Func::getPluginPreferencesValue('IMAGEPLUGIN_MAGNIFY_ICON') ||
    '%PUBURLPATH%/%SYSTEMWEB%/ImagePlugin/magnify-clip.png';
  $this->{magnifyWidth} = 15; # TODO: make this configurable/autodetected/irgnored
  $this->{magnifyHeight} = 11; # TODO: make this configurable/autodetected/irgnored

  $this->{thumbSize} = 
    Foswiki::Func::getPreferencesValue('THUMBNAIL_SIZE') || 180;
  $this->{baseWeb} = $baseWeb;
  $this->{baseTopic} = $baseTopic;
  $this->{errorMsg} = ''; # from image mage
  $this->{autoAttachThumbnails} = $Foswiki::cfg{ImagePlugin}{AutoAttachThumbnails};
  $this->{autoAttachExternalImages} = $Foswiki::cfg{ImagePlugin}{AutoAttachExternalImages};

  # Graphics::Magick is less buggy than Image::Magick
  my $impl = 
    $Foswiki::cfg{ImagePlugin}{Impl} || 
    $Foswiki::cfg{ImageGalleryPlugin}{Impl} || 
    'Image::Magick'; 

  #writeDebug("creating new image mage using $impl");
  eval "use $impl";
  die $@ if $@;
  $this->{mage} = new $impl;
  #writeDebug("done");

  return $this;
}

###############################################################################
sub handleREST {
  my ($this, $subject, $verb) = @_;

  #writeDebug("called handleREST($subject, $verb)");

  my $query = Foswiki::Func::getCgiQuery();
  my $theTopic = $query->param('topic') || $this->{session}->{topicName};
  my $theWeb = $query->param('web') || $this->{session}->{webName};
  my ($imgWeb, $imgTopic) = Foswiki::Func::normalizeWebTopicName($theWeb, $theTopic);
  my $imgFile = $query->param('file');
  my $imgPath = $Foswiki::cfg{PubDir}.'/'.$imgWeb.'/'.$imgTopic;
  my $width = $query->param('width') || '';
  my $height = $query->param('height') || '';
  my $size = $query->param('size') || '';
  my $zoom = $query->param('zoom') || 'off';
  my $refresh = $query->param('refresh') || '';
  $refresh = ($refresh =~ /^(on|1|yes|img)$/g)?1:0;

  #writeDebug("processing image");
  my $imgInfo = $this->processImage($imgWeb, $imgTopic, $imgFile, 
    $size, $zoom, $width, $height, $refresh);
  unless ($imgInfo) {
    Foswiki::Func::writeWarning("ImagePlugin - $this->{errorMsg}");
    return '';
  }

  my $pubUrlPath = Foswiki::Func::getPubUrlPath();
  my $urlHost = Foswiki::Func::getUrlHost();
  my $pubUrl = $urlHost.$pubUrlPath;
  my $thumbFileUrl = $pubUrl.'/'.$imgWeb.'/'.$imgTopic.'/'.$imgInfo->{file};
  $thumbFileUrl = urlEncode($thumbFileUrl);

  #writeDebug("redirecting to $thumbFileUrl");
  Foswiki::Func::redirectCgiQuery($query, $thumbFileUrl);
}

###############################################################################
sub handleIMAGE {
  my ($this, $params, $theTopic, $theWeb) = @_;

  #writeDebug("called handleIMAGE(params, $theTopic, $theWeb)");

  if($params->{_DEFAULT} =~ m/^(?:clr|clear)$/io ) { 
    return $this->getTemplate('clear');
  }

  # read parameters
  my $argsStr = $params->{_DEFAULT} || '';
  $argsStr =~ s/^\[\[//o;
  $argsStr =~ s/\]\]$//o;
  $params->{type} ||= '';
  $this->parseWikipediaParams($params, $argsStr);

  # default and fix parameters
  $params->{warn} ||= '';
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
  $params->{zoom} ||= 'off';
  $params->{tooltip} ||= 'off';
  $params->{tooltipwidth} ||= '300';
  $params->{tooltipheight} ||= '300';

  $params->{class} =~ s/'/"/g;

  unless ($params->{size}) {
    $params->{size} = Foswiki::Func::getPreferencesValue("IMAGESIZE");
  }
  $params->{size} ||= '';

  unless ($params->{type}) {
    if ($params->{href} || $params->{width} || $params->{height} || $params->{size}) {
      $params->{type} = 'simple' 
    } else {
      $params->{type} = 'plain' 
    }
  }

  # validate args
  $params->{type} = 'thumb' if $params->{type} eq 'thumbnail';
  if ($params->{type} eq 'thumb' && !$params->{size}) {
    $params->{size} = $this->{thumbSize}
  }

  if ($params->{size} =~ /^(\d+)(px)?x?(\d+)?(px)?$/) {
    $params->{size} = $3?"$1x$3":$1;
  }

  my $origFile = $params->{file} || $params->{_DEFAULT};
  my $imgWeb = $params->{web} || $theWeb;
  my $imgTopic;
  my $imgPath;
  my $pubDir = $Foswiki::cfg{PubDir};
  my $pubUrlPath = Foswiki::Func::getPubUrlPath();
  my $urlHost = Foswiki::Func::getUrlHost();
  my $pubUrl = $urlHost.$pubUrlPath;
  my $albumTopic;
  my $query = Foswiki::Func::getCgiQuery();
  my $doRefresh = $query->param('refresh') || 0;
  $doRefresh = ($doRefresh =~ /^(on|1|yes|img)$/g)?1:0;

  #writeDebug("origFile=$origFile") if $origFile;

  # search image
  if ($origFile =~ /^https?:\/\/.*/) {
    my $url = $origFile;
    my $ext = '';
    if ($url =~ /^.*[\\\/](.*?(\.[a-zA-Z]+))$/) {
      $origFile = $1;
      $ext = $2;
    }

    # sanitize downloaded filename
    my $dummy;
    ($origFile, $dummy) = Foswiki::Sandbox::sanitizeAttachmentName($origFile);
    if ($origFile ne $dummy) {
      #writeDebug("sanitized filename from $dummy to $origFile");
    }

    $imgTopic = $params->{topic} || $theTopic;
    ($imgWeb, $imgTopic) = 
      Foswiki::Func::normalizeWebTopicName($imgWeb, $imgTopic);
    $imgPath = $pubDir.'/'.$imgWeb;
    mkdir($imgPath) unless -d $imgPath;
    $imgPath .= '/'.$imgTopic;
    mkdir($imgPath) unless -d $imgPath;
    $imgPath .= '/'.$origFile;

    unless($this->mirrorImage($imgWeb, $imgTopic, $url, $imgPath, $doRefresh)) {
      return $this->inlineError($params);
    }
  } elsif ($origFile =~ /^(?:$pubUrl|$pubUrlPath)?(.*)\/(.*?)$/) {
    # part of the filename
    $origFile = $2;
    ($imgWeb, $imgTopic) = Foswiki::Func::normalizeWebTopicName($imgWeb, $1);
    $imgPath = $pubDir.'/'.$imgWeb.'/'.$imgTopic.'/'.$origFile;

    #writeDebug("looking for an image file at $imgPath");

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
	Foswiki::Func::normalizeWebTopicName($imgWeb, $imgTopic);
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
	Foswiki::Func::normalizeWebTopicName($imgWeb, $theTopic);
      $imgPath = $pubDir.'/'.$testWeb.'/'.$testTopic.'/'.$origFile;
      unless (-e $imgPath) {
	# no, then look in the album
	$albumTopic = Foswiki::Func::getPreferencesValue('IMAGEALBUM', 
	  ($testWeb eq $theWeb)?undef:$testWeb);
	unless ($albumTopic) {
	  # not found, and no album
	  $this->{errorMsg} = "(3) can't find <nop>$origFile in <nop>$imgWeb";
	  return $this->inlineError($params);
	}
	$albumTopic = 
	  Foswiki::Func::expandCommonVariables($albumTopic, $testTopic, $testWeb);
	($testWeb, $testTopic) =
	  Foswiki::Func::normalizeWebTopicName($imgWeb, $albumTopic);
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

  #writeDebug("origFile=$origFile, imgWeb=$imgWeb, imgTopic=$imgTopic, imgPath=$imgPath");

  my $origFileUrl = $pubUrl.'/'.$imgWeb.'/'.$imgTopic.'/'.$origFile;
  $params->{alt} ||= $origFile;
  $params->{title} ||= $params->{caption} || $origFile;
  $params->{desc} ||= $params->{title};
  $params->{href} ||= $origFileUrl;

  #writeDebug("type=$params->{type}, align=$params->{align}");
  #writeDebug("size=$params->{size}, width=$params->{width}, height=$params->{height}");

  # compute image
  my $imgInfo = 
    $this->processImage($imgWeb, $imgTopic, $origFile, 
      $params->{size}, $params->{zoom}, $params->{width}, $params->{height}, $doRefresh);

  unless ($imgInfo) {
    #Foswiki::Func::writeWarning("ImagePlugin - $this->{errorMsg}");
    return $this->inlineError($params);
  }

  # For compatibility with i18n-characters in file names, encode urls (as Foswiki.pm/viewfile does for attachment names in general)
  my $thumbFileUrl = $pubUrl.'/'.$imgWeb.'/'.$imgTopic.'/'.$imgInfo->{file};
  $thumbFileUrl = urlEncode($thumbFileUrl);

  # format result
  my $result = $params->{format} || '';
  if (!$result) {
    if ($params->{type} eq 'plain') {
      $result = $this->getTemplate('plain');
    } elsif ($params->{type} eq 'simple') {
      $result = $this->getTemplate('simple');
    } elsif ($params->{type} eq 'link') {
      $result = $this->getTemplate('link');
    } elsif ($params->{type} eq 'frame') {
      $result = $this->getTemplate('frame');
      $result =~ s/\$captionFormat/$this->getTemplate('caption')/ge
	if $params->{caption};
    } elsif ($params->{type} eq 'thumb') {
      $result = $this->getTemplate('frame'); 
      my $thumbCaption = $this->getTemplate('magnify').$params->{caption};
      $result =~ s/\$captionFormat/$this->getTemplate('caption')/ge;
      $result =~ s/\$caption/$thumbCaption/g;
    } else {
      $result = $this->getTemplate('float');
      $result =~ s/\$captionFormat/$this->getTemplate('caption')/ge
	if $params->{caption};
    }
  }
  $result =~ s/\s+$//; # strip whitespace at the end

  $result =  $params->{header}.$result.$params->{footer};
  $result =~ s/\$captionFormat//g;

  $result =~ s/\$caption/$params->{caption}/g;
  $result =~ s/\$magnifyFormat/$this->getTemplate('magnify')/ge;
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

  my $context = Foswiki::Func::getContext();
  if ($context->{JQueryPluginEnabled} && $params->{tooltip} eq 'on') {
    Foswiki::Plugins::JQueryPlugin::createPlugin("imagetooltip");
    $params->{class} .= 
      " jqImageTooltip {".
        "web:\"$imgWeb\", ".
        "topic:\"$imgTopic\", ".
        "image:\"$origFile\", ".
        "width:\"$params->{tooltipwidth}\", ".
        "height:\"$params->{tooltipheight}\" ".
      "}";
  }

  #my $thumbFileUrl = $pubUrl.'/'.$imgWeb.'/'.$imgTopic.'/'.$imgInfo->{file};

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
  $result = Foswiki::Func::expandCommonVariables($result, $theTopic, $theWeb);
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
sub processImage {
  my ($this, $imgWeb, $imgTopic, $imgFile, $size, $zoom, $width, $height, $doRefresh) = @_;

  writeDebug("called processImage($imgWeb, $imgTopic, $imgFile, $size, $zoom, $width, $height, $doRefresh)");

  $this->{errorMsg} = '';

  my %imgInfo;
  $imgInfo{file} = $imgFile;
  $imgInfo{origFile} = $imgFile;

  my $imgPath = $Foswiki::cfg{PubDir}.'/'.$imgWeb.'/'.$imgTopic;
  my $origImgPath = $imgPath.'/'.$imgFile;

  writeDebug("pinging $imgPath/$imgFile");
  ($imgInfo{origWidth}, $imgInfo{origHeight}) = $this->{mage}->Ping($origImgPath);
  $imgInfo{origWidth} ||= 0;
  $imgInfo{origHeight} ||= 0;

  if ($size && $size =~ /^\d+$/) {
    if ($zoom ne 'on' && $size > $imgInfo{origHeight} && $size > $imgInfo{origWidth}) {
      writeDebug("not zooming to size $size");
      $size = '';
    }
  }

  if ($size || $width || $height || $doRefresh) {
    # read orig width and height
    if ($width || $height) {

      # keep aspect ratio
      my $aspect = $imgInfo{origWidth} ? $imgInfo{origHeight} / $imgInfo{origWidth} : 0;
      my $newHeight = $imgInfo{origHeight};
      my $newWidth = $imgInfo{origWidth};

      if ($width && $imgInfo{origWidth} > $width) { # scale down width
        $newHeight = $width * $aspect;
        $newWidth = $width;
      }

      if ($height && $newHeight > $height) { # scale down height
        $newWidth = $aspect ? $height / $aspect : 0;
        $newHeight = $height;
      }

      if ($zoom ne 'on' && $newHeight > $imgInfo{origHeight} && $newWidth > $imgInfo{origWidth}) {
        writeDebug("not zooming");
        $newHeight = $imgInfo{origHeight};
        $newWidth = $imgInfo{origWidth};
      }

      $width = int($newWidth+0.5);
      $height = int($newHeight+0.5);
      writeDebug("origWidth=$imgInfo{origWidth} origHeight=$imgInfo{origHeight} aspect=$aspect width=$width height=$height");
    }

    my $newImgFile = $this->getImageFile($width, $height, $size, $imgFile);
    my $newImgPath = $imgPath.'/'.$newImgFile;
    writeDebug("checking for $newImgFile");

    # compare file modification times
    $doRefresh = 1 if -f $newImgPath && 
      getModificationTime($origImgPath) > getModificationTime($newImgPath);

    if (-f $newImgPath && !$doRefresh) { # cached
      ($imgInfo{width}, $imgInfo{height}) = $this->{mage}->Ping($newImgPath);
      $imgInfo{width} ||= 0;
      $imgInfo{height} ||= 0;
      writeDebug("found newImgFile=$newImgFile");
    } else { 
      
      # read
      my $error = $this->{mage}->Read($origImgPath);
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
      $error = $this->{mage}->Write($newImgPath);
      if ($error =~ /(\d+)/) {
	$this->{errorMsg} .= " $error";
	return undef if $1 >= 400;
      }
      ($imgInfo{width}, $imgInfo{height}, $imgInfo{filesize}) = $this->{mage}->Get('width', 'height', 'filesize');
      $imgInfo{width} ||= 0;
      $imgInfo{height} ||= 0;

      $this->updateAttachment($imgWeb, $imgTopic, $newImgFile, {path => $imgFile, filesize=>$imgInfo{filesize}})
        if $this->{autoAttachThumbnails};
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
    } elsif ($arg =~ /^(\d+)(px)?$/i) {
      $params->{size} = $1 unless $params->{size};
    } elsif ($arg =~ /^w(\d+)(px)=$/i) {
      $params->{width} = $1 unless $params->{width};
    } elsif ($arg =~ /^h(\d+)(px)?$/i) {
      $params->{height} = $1 unless $params->{height};
    } else {
      $params->{caption} = $arg unless $params->{caption};
    }
  }
}

###############################################################################
sub inlineError {
  my ($this, $params) = @_;

  return '' if $params && $params->{warn} eq 'off';
  return "<span class=\"foswikiAlert\">Error: $this->{errorMsg}</span>" 
    unless $params && $params->{warn};
  return $params?$params->{warn}:'undefined warning';
}


###############################################################################
# from Foswiki.pm
sub urlEncode {
  my $text = shift;

  $text =~ s/([^0-9a-zA-Z-_.:~!*'\/])/'%'.sprintf('%02x',ord($1))/ge;

  return $text;
}

###############################################################################
# mirrors an image and attach it to the given web.topic
# turns true on success; on false errorMsg is set
sub mirrorImage {
  my ($this, $web, $topic, $url, $fileName, $force) = @_;

  #writeDebug("called mirrorImage($url, $fileName)");
  return 1 if !$force && -e $fileName;

  #writeDebug("fetching $url into $fileName");

  unless ($this->{ua}) {
    require LWP::UserAgent;
    my $ua = LWP::UserAgent->new;
    $ua->timeout(10);

    my $proxy = $Foswiki::cfg{PROXY}{HOST};
    if ($proxy) {
      my $port = $Foswiki::cfg{PROXY}{PORT};
      $proxy .= ':' . $port if $port;
      $ua->proxy([ 'http', 'https' ], $proxy);

      my $proxySkip = $Foswiki::cfg{PROXY}{SkipProxyForDomains};
      if ($proxySkip) {
        my @skipDomains = split(/\s*,\s*/, $proxySkip);
        $ua->no_proxy(@skipDomains);
      }
    }

    $this->{ua} = $ua;
  }

  my $response = $this->{ua}->mirror($url, $fileName);
  my $code = $response->code;

  unless ($response->is_success || $response->code == 304) {
    my $status = $response->status_line;
    $this->{errorMsg} = "can't fetch image from <nop>'$url': $status";
    return 0;
  }

  my $filesize = $response->header('content_length');
  $this->updateAttachment($web, $topic, $fileName, { path => $url, filesize => $filesize })
    if $this->{autoAttachExternalImages};

  return 1;
}

###############################################################################
sub getImageFile {
  my ($this, $width, $height, $size, $imgFile) = @_;

  my @newImgFile;
  $width =~ s/px//go;
  $height =~ s/px//go;
  $size =~ s/px//go;
  $width = int($width+0.5) if $width;
  $height = int($height+0.5) if $height;

  push @newImgFile, $height if $height;
  push @newImgFile, $width if $width;
  push @newImgFile, $size if $size;
  push @newImgFile, $imgFile;

  return 'igp_'.join('_', @newImgFile);
}

###############################################################################
sub updateAttachment {
  my ($this, $web, $topic, $filename, $params) = @_;

  writeDebug("updateAttachment($web, $topic, $filename)");

  try {
    my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
    my $user = Foswiki::Func::getCanonicalUserID();
    unless (Foswiki::Func::checkAccessPermission('CHANGE', $user, $text, $topic, $web, $meta )) {
      writeDebug("$user has no access rights to $web.$topic");
      return;
    }

    Foswiki::Func::setTopicEditLock($web, $topic, 1);
    my $baseFilename = $filename;
    $baseFilename =~ s/^(.*)[\/\\](.*?)$/$2/;
    
    my $attachment = $meta->get('FILEATTACHMENT', $baseFilename);
    my $topicInfo = $meta->get('TOPICINFO');
    $attachment->{name} = $baseFilename;
    $attachment->{attachment} = $baseFilename; # BTW: not documented in System.MetaData 
    $attachment->{date} = time();
    $attachment->{version} ||= 1;
    $attachment->{attr} = 'h';
    $attachment->{user} = $user;
    $attachment->{path} = $params->{path} if $params->{path};
    $attachment->{size} = $params->{filesize} if $params->{filesize};
    $meta->putKeyed('FILEATTACHMENT', $attachment);
    Foswiki::Func::saveTopic($web, $topic, $meta, $text, {minor => 1});
  } 
  catch Foswiki::OopsException with {
    my $e = shift;
    my $message = 'ERROR: ' . $e->stringify();
    writeDebug($message);
  };

  finally {
    Foswiki::Func::setTopicEditLock($web, $topic, 0);
  };
}

###############################################################################
sub getModificationTime {
  my $file = shift;
  return 0 unless $file;
  my @stat = stat($file);
  return $stat[9] || $stat[10] || 0;
}

###############################################################################
sub getTemplate {
  my ($this, $name) = @_;

  return '' unless $name;
  $name = 'image:'.$name;

  unless (defined $this->{$name}) {
    unless (defined $this->{imageplugin}) {
      $this->{imageplugin} = Foswiki::Func::loadTemplate("imageplugin");
    }
    $this->{$name} = Foswiki::Func::expandTemplate($name) || '';
  }

  return $this->{$name};
}

1;
