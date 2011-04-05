# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006 Craig Meyer, meyercr@gmail.com
# Copyright (C) 2006-2011 Michael Daum http://michaeldaumconsulting.com
#
# Early version Based on ImgPlugin
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
use Digest::MD5 ();
use URI ();

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
  my ($this, $subject, $verb, $response) = @_;

  #writeDebug("called handleREST($subject, $verb)");

  my $query = Foswiki::Func::getCgiQuery();
  my $theTopic = $query->param('topic') || $this->{session}->{topicName};
  my $theWeb = $query->param('web') || $this->{session}->{webName};
  my ($imgWeb, $imgTopic) = Foswiki::Func::normalizeWebTopicName($theWeb, $theTopic);
  my $imgFile = $query->param('file');
  my $refresh = $query->param('refresh') || '';
  $refresh = ($refresh =~ /^(on|1|yes|img)$/g)?1:0;

  writeDebug("processing image");
  my $imgInfo = $this->processImage($imgWeb, $imgTopic, $imgFile, {
      size => ($query->param('size')||''),
      zoom => ($query->param('zoom')||'off'),
      crop => ($query->param('crop')||'off'),
      width => ($query->param('width')||''),
      height => ($query->param('height')||''),
    } ,$refresh);
  unless ($imgInfo) {
    Foswiki::Func::writeWarning("ImagePlugin - $this->{errorMsg}");
    return '';
  }

  my $image = readImage($imgWeb, $imgTopic, $imgInfo->{file});
  my $mimeType = $this->suffixToMimeType($imgInfo->{file});

  $response->header(
    -'Content-Type' => $mimeType,
    -'Content-Length' => $imgInfo->{filesize}, # overrides wrong length computed by Response
    -'Cache-Control' => 'max-age=36000, public',
    -'Expires' => '+12h',
  );
  $response->print($image);

  return;
}

###############################################################################
sub handleIMAGE {
  my ($this, $params, $theTopic, $theWeb) = @_;

  #writeDebug("called handleIMAGE(params, $theTopic, $theWeb)");

  if($params->{_DEFAULT} && $params->{_DEFAULT} =~ m/^(?:clr|clear)$/io ) { 
    return $this->getTemplate('clear');
  }

  $params->{type} ||= '';

  # read parameters
  $this->parseMediawikiParams($params);

  my $origFile = $params->{_DEFAULT} || $params->{file};
  return '' unless $origFile;

  #writeDebug("origFile=$origFile");

  # default and fix parameters
  $params->{warn} ||= '';
  $params->{width} ||= '';
  $params->{height} ||= '';
  $params->{caption} ||= '';
  $params->{align} ||= 'none';
  $params->{class} ||= '';
  $params->{data} ||= '';
  $params->{footer} ||= '';
  $params->{header} ||= '';
  $params->{id} ||= '';
  $params->{mousein} ||= '';
  $params->{mouseout} ||= '';
  $params->{style} ||= '';
  $params->{zome} ||= 'off';
  $params->{crop} ||= 'off';
  $params->{tooltip} ||= 'off';
  $params->{tooltipcrop} ||= 'off';
  $params->{tooltipwidth} ||= '300';
  $params->{tooltipheight} ||= '300';

  $params->{class} =~ s/'/"/g;
  $params->{data} =~ s/'/"/g;

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

  my $imgWeb = $params->{web} || $theWeb;
  my $imgTopic;
  my $imgPath;
  my $pubDir = $Foswiki::cfg{PubDir};
  my $pubUrlPath = Foswiki::Func::getPubUrlPath();
  my $urlHost = Foswiki::Func::getUrlHost();
  my $pubUrl = URI->new($pubUrlPath, $urlHost);
  my $albumTopic;
  my $query = Foswiki::Func::getCgiQuery();
  my $doRefresh = $query->param('refresh') || 0;
  $doRefresh = ($doRefresh =~ /^(on|1|yes|img)$/g)?1:0;

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
      writeDebug("sanitized filename from $dummy to $origFile");
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
  } elsif ($origFile =~ /(?:\/?pub\/)?(.*)\/(.*?)$/) {
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
    $this->processImage($imgWeb, $imgTopic, $origFile, $params, $doRefresh);

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
        "crop:\"$params->{tooltipcrop}\", ".
        "width:\"$params->{tooltipwidth}\", ".
        "height:\"$params->{tooltipheight}\" ".
        ($params->{data}?", $params->{data}":'').
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
  $result =~ s/\$data/$params->{data}/g;
  $result =~ s/\$id/$params->{id}/g;
  $result =~ s/\$style/$params->{style}/g;
  $result =~ s/\$align/$params->{align}/g;
  $result =~ s/\$alt/<noautolink>$alt<\/noautolink>/g;
  $result =~ s/\$title/<noautolink>$title<\/noautolink>/g;
  $result =~ s/\$desc/<noautolink>$desc<\/noautolink>/g;

  $result =~ s/\$perce?nt/\%/go;
  $result =~ s/\$nop//go;
  $result =~ s/\$n/\n/go;
  $result =~ s/\$dollar/\$/go;

  # recursive call for delayed TML expansion
  $result = Foswiki::Func::expandCommonVariables($result, $theTopic, $theWeb);
  return $result; 
} 

###############################################################################
sub plainify {
  my $text = shift;

  return '' unless $text;

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
  my ($this, $imgWeb, $imgTopic, $imgFile, $params, $doRefresh) = @_;

  my $size = $params->{size} || '';
  my $crop = $params->{crop} || 'off';
  my $zoom = $params->{zoom} || 'off';
  my $width = $params->{width} || '';
  my $height = $params->{height} || '';

  writeDebug("called processImage(web=$imgWeb, topic=$imgTopic, file=$imgFile, size=$size, crop=$crop, width=$width, height=$height, refresh=$doRefresh)");

  $this->{errorMsg} = '';

  my %imgInfo;
  $imgInfo{file} = $imgFile;
  $imgInfo{origFile} = $imgFile;

  my $imgPath = $Foswiki::cfg{PubDir}.'/'.$imgWeb.'/'.$imgTopic;
  my $origImgPath = $imgPath.'/'.$imgFile;

  writeDebug("pinging $imgPath/$imgFile");
  ($imgInfo{origWidth}, $imgInfo{origHeight}, $imgInfo{origFilesize}, $imgInfo{origFormat}) = $this->{mage}->Ping($origImgPath);
  $imgInfo{origWidth} ||= 0;
  $imgInfo{origHeight} ||= 0;

  if ($size || $width || $height || $doRefresh) {
    if (!$size) {
      $size = $width.'x'.$height;
    }
    if ($size !~ /[<>^]$/) {
      if ($zoom eq 'on') {
        $size .= '<';
      } else {
        $size .= '>';
      }
      if ($crop ne 'off') {
        $size .= '^';
      }
    }
    writeDebug("size=$size");

    my $newImgFile = $this->getImageFile($size, $zoom, $crop, $imgFile);
    my $newImgPath = $imgPath.'/'.$newImgFile;
    #writeDebug("checking for $newImgFile");

    # compare file modification times
    $doRefresh = 1 if -f $newImgPath && 
      getModificationTime($origImgPath) > getModificationTime($newImgPath);

    if (-f $newImgPath && !$doRefresh) { # cached
      ($imgInfo{width}, $imgInfo{height}, $imgInfo{filesize}, $imgInfo{format}) = $this->{mage}->Ping($newImgPath);
      $imgInfo{width} ||= 0;
      $imgInfo{height} ||= 0;
      writeDebug("found $newImgFile at $imgWeb.$imgTopic");
    } else { 
      writeDebug("creating $newImgFile");
      
      # read
      my $error = $this->{mage}->Read($origImgPath);
      if ($error =~ /(\d+)/) {
	$this->{errorMsg} = $error;
	return undef if $1 >= 400;
      }

      # scale
      my $geometry = $size;
      # SMELL: As of IM v6.3.8-3 IM now has a new geometry option flag '^' which
      # is used to resize the image based on the smallest fitting dimension.
      if ($crop ne 'off' && $geometry !~ /\^$/) {
        $geometry .= '^';
      }

      writeDebug("resize($geometry)");
      $error = $this->{mage}->Resize(geometry=>$geometry);
      if ($error =~ /(\d+)/) {
        $this->{errorMsg} = $error;
        return undef if $1 >= 400;
      }

      # crop
      if ($crop =~ /^(on|northwest|north|northeast|west|center|east|southwest|south|southeast)$/i) {
        my $gravity = $crop;
        $gravity = "center" if $crop eq 'on';
        writeDebug("Set(Gravity=>$gravity)");
        $error = $this->{mage}->Set(Gravity=>$gravity);
        if ($error =~ /(\d+)/) {
          $this->{errorMsg} = $error;
          return undef if $1 >= 400;
        }

        my $geometry = '';
        if ($size) {
          unless ($size =~ /\d+x\d+/) {
            $size = $size.'x'.$size;
          }
          $geometry = $size.'+0+0';
          $geometry =~ s/[<>^@!]//go;
        } else {
          $geometry = $width.'x'.$height.'+0+0';
        }
 
        writeDebug("crop($geometry)");
        $error = $this->{mage}->Crop($geometry);
        if ($error =~ /(\d+)/) {
          $this->{errorMsg} = $error;
          return undef if $1 >= 400;
        }

        $error = $this->{mage}->Set(page=>'0x0+0+0');
        if ($error =~ /(\d+)/) {
          $this->{errorMsg} = $error;
          return undef if $1 >= 400;
        }
      }


      # write
      $error = $this->{mage}->Write($newImgPath);
      if ($error =~ /(\d+)/) {
	$this->{errorMsg} .= " $error";
	return undef if $1 >= 400;
      }
      ($imgInfo{width}, $imgInfo{height}, $imgInfo{filesize}, $imgInfo{format}) = $this->{mage}->Get('width', 'height', 'filesize', 'format');
      $imgInfo{width} ||= 0;
      $imgInfo{height} ||= 0;

      #writeDebug("old geometry=$imgInfo{origWidth}x$imgInfo{origHeight}, new geometry=$imgInfo{width}x$imgInfo{height}");

#      $this->updateAttachment($imgWeb, $imgTopic, $newImgFile, {path => $imgFile, filesize=>$imgInfo{filesize}})
#        if $this->{autoAttachThumbnails};
    }
    $imgInfo{file} = $newImgFile;
  } else {
    $imgInfo{width} = $imgInfo{origWidth};
    $imgInfo{height} = $imgInfo{origHeight};
    $imgInfo{filesize} = $imgInfo{origFilesize};
    $imgInfo{format} = $imgInfo{origFormat};
  }

  # forget images
  my $mage = $this->{mage};
  @$mage = (); 
  
  return \%imgInfo;
} 

###############################################################################
# sets type (link,frame,thumb), file, width, height, size, caption
sub parseMediawikiParams {
  my ($this, $params) = @_;

  my $argStr = $params->{_DEFAULT} || '';
  return unless $argStr =~ /\|/g;

  $argStr =~ s/^\[\[//o;
  $argStr =~ s/\]\]$//o;

  my ($file, @args) = split(/\|/, $argStr);
  $params->{type} = 'link' if $file =~ s/^://o;
  $params->{file} = $params->{_DEFAULT} = $file;

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

  writeDebug("called mirrorImage($url, $fileName)");
  return 1 if !$force && -e $fileName;

  require File::Temp;
  my $tempImgFile = new File::Temp();
  writeDebug("fetching $url into $tempImgFile");

  unless ($this->{ua}) {
    require LWP::UserAgent;
    my $ua = LWP::UserAgent->new;
    $ua->timeout(10);

    my $attachLimit = Foswiki::Func::getPreferencesValue('ATTACHFILESIZELIMIT') || 0;
    $attachLimit =~ s/[^\d]//g;
    if ($attachLimit) {
      $attachLimit *= 1024;
      $ua->max_size($attachLimit);
    }

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

  #my $response = $this->{ua}->mirror($url, $tempImgFile);
  my $response = $this->{ua}->get($url, ':content_file' => $tempImgFile->filename);
  my $code = $response->code;
  writeDebug("response code=$code");

  unless ($response->is_success || $response->code == 304) {
    my $status = $response->status_line;
    $this->{errorMsg} = "can't fetch image from <nop>'$url': $status";
    writeDebug("Error: $this->{errorMsg}");
    return 0;
  }

  my $clientAborted = $response->header('client-aborted') || 0;
  if ($clientAborted eq 'max_size') {
    $this->{errorMsg} = "can't fetch image from <nop>'$url': max size exceeded";
    writeDebug("Error: $this->{errorMsg}");
    return 0;
  }
  
  my $filesize = $response->header('content_length');
  writeDebug("filesize=$filesize");
  $this->updateAttachment($web, $topic, $fileName, { path => $url, filesize => $filesize, file => $tempImgFile })
    if $this->{autoAttachExternalImages};

  return 1;
}

###############################################################################
sub getImageFile {
  my ($this, $size, $zoom, $crop, $imgFile) = @_;

  return 'igp_'.Digest::MD5::md5_hex($size, $zoom, $crop).'_'.$imgFile;
}

###############################################################################
sub updateAttachment {
  my ($this, $web, $topic, $filename, $params) = @_;

  writeDebug("called updateAttachment($web, $topic, $filename)");

  my $baseFilename = $filename;
  $baseFilename =~ s/^(.*)[\/\\](.*?)$/$2/;

  my $args = {
    dontlog=>1,
    filedate=> time(),
    #hide=>1,
    minor=>1,
    #notopicchange=>1, # SMELL: does not work
  };
  $args->{file} = $params->{file} if $params->{file};
  $args->{filepath} = $params->{path} if $params->{path};

  # SMELL: this is called size in the meta data, but seems to need a filesize attr for the api
  $args->{size} = $params->{filesize} if $params->{filesize};
  $args->{filesize} = $params->{filesize} if $params->{filesize};

  try {
    Foswiki::Func::saveAttachment($web, $topic, $baseFilename, $args);
  } catch Foswiki::AccessControlException with {
    # ignore
    my $user = Foswiki::Func::getCanonicalUserID();
    writeDebug("$user has no access rights to $web.$topic");
  } catch Foswiki::OopsException with {
    # ignore
    my $e = shift;
    my $message = 'ERROR: ' . $e->stringify();
    writeDebug($message);
    #print STDERR "$message\n";
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

###############################################################################
sub readImage {
  my ($web, $topic, $image) = @_;

  my $imgPath = $Foswiki::cfg{PubDir}.'/'.$web.'/'.$topic.'/'.$image;

  my $data = '';
  my $IN_FILE;
  open( $IN_FILE, '<', $imgPath ) || return '';
  binmode $IN_FILE;

  local $/ = undef;    # set to read to EOF
  $data = <$IN_FILE>;
  close($IN_FILE);

  $data = '' unless $data;    # no undefined
  
  return $data;
}

###############################################################################
sub suffixToMimeType {
  my ($this, $image) = @_;

  my $mimeType = 'image/png';

  if ($image && $image =~ /\.([^.]+)$/) {
    my $suffix = $1;
    unless ($this->{types}) {
      $this->{types} = Foswiki::readFile($Foswiki::cfg{MimeTypesFileName});
    }
    if ($this->{types} =~ /^([^#]\S*).*?\s$suffix(?:\s|$)/im) {
      $mimeType = $1;
    }
  }

  return $mimeType;
}



1;
