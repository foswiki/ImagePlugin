# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006 Craig Meyer, meyercr@gmail.com
# Copyright (C) 2006-2020 Michael Daum http://michaeldaumconsulting.com
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
use warnings;

use Foswiki::Plugins ();
use Foswiki::Func ();
use Error qw( :try );
use Foswiki::OopsException ();
use Digest::MD5 ();
use MIME::Base64 ();
use File::Temp ();
use URI ();
use JSON ();
use Encode ();
use Image::Magick ();
use Foswiki::Plugins::JQueryPlugin ();
use Foswiki::Contrib::CacheContrib ();

use constant TRACE => 0;    # toggle me

###############################################################################
# ImageCore constructor
sub new {
  my $class = shift;
  my $session = shift;

  $session ||= $Foswiki::Plugins::SESSION;

  my $this = bless({
      session => $session || $Foswiki::Plugins::SESSION,
      magnifyIcon => $Foswiki::cfg{ImagePlugin}{MagnifyIcon} || '%PUBURLPATH%/%SYSTEMWEB%/ImagePlugin/magnify-clip.png',
      magnifyWidth => $Foswiki::cfg{ImagePlugin}{MagnifyIconWidth} || 15,
      magnifyHeight => $Foswiki::cfg{ImagePlugin}{MagnifyIconHeight} || 11,
      thumbSize => $Foswiki::cfg{ImagePlugin}{DefaultThumbnailSize} || 180,
      autoAttachExternalImages => $Foswiki::cfg{ImagePlugin}{AutoAttachExternalImages} || 0,
      autoAttachInlineImages => $Foswiki::cfg{ImagePlugin}{AutoAttachInlineImages} || 0,
      inlineImageTemplate => $Foswiki::cfg{ImagePlugin}{InlineImageTemplate} || "<img %BEFORE% src='%PUBURLPATH%/%WEB%/%TOPIC%/%ATTACHMENT%' %AFTER% />",
      @_
    },
    $class
  );

  $this->{errorMsg} = '';    # from image mage

  #_writeDebug("done");

  return $this;
}

###############################################################################
sub mage {
  my $this = shift;
  
  $this->{mage} = $this->createImage(@_) unless $this->{mage};

  return $this->{mage};
}

###############################################################################
sub createImage {
  my $this = shift;

  return Image::Magick->new(@_);
}

###############################################################################
sub filter {
  my $this = shift;

  unless ($this->{filter}) {
    require Foswiki::Plugins::ImagePlugin::Filter;
    $this->{filter} = Foswiki::Plugins::ImagePlugin::Filter->new($this);
  }

  return $this->{filter};
}


###############################################################################
sub finishPlugin {
  my $this = shift;

  my $context = Foswiki::Func::getContext();
  $this->clearOutdatedThumbs() if $context->{view};

  undef $this->{json};
  undef $this->{mage};
  undef $this->{filter};
  undef $this->{types};
  undef $this->{imageplugin};
}

###############################################################################
sub handleREST {
  my ($this, $subject, $verb, $response) = @_;

  _writeDebug("called handleREST($subject, $verb)");

  my $query = Foswiki::Func::getRequestObject();
  my $theTopic = $query->param('topic') || $this->{session}->{topicName};
  my $theWeb = $query->param('web') || $this->{session}->{webName};
  my ($imgWeb, $imgTopic) = Foswiki::Func::normalizeWebTopicName($theWeb, $theTopic);
  my $imgFile = $query->param('file');
  my $refresh = $query->param('refresh') || '';
  $refresh = ($refresh =~ /^(on|1|yes|img|image)$/g) ? 1 : 0;

  $this->clearCache() if $refresh;

  $imgFile =~ s/^$Foswiki::cfg{DefaultUrlHost}$Foswiki::cfg{PubUrlPath}//;
  $imgFile =~ s/^$Foswiki::cfg{PubUrlPath}//;
  $imgFile =~ s/^\///;

  if ($imgFile =~ /(?:pub\/)?(?:(.+?)\/)?([^\/]+)\/([^\/]+?)$/) {
    $imgWeb = $1 || $imgWeb;
    $imgTopic = $2;
    $imgFile = $3;
  } 

  _writeDebug("processing image");
  my $imgInfo = $this->processImage(
    $imgWeb, $imgTopic, $imgFile, {
      size => ($query->param('size') || ''),
      zoom => ($query->param('zoom') || 'off'),
      crop => ($query->param('crop') || ''),
      width => ($query->param('width') || ''),
      height => ($query->param('height') || ''),
      filter => ($query->param('filter') || ''),
      rotate => ($query->param('rotate') || ''),
      transparent => ($query->param('transparent') || ''),
      output => ($query->param('output') || ''),
      type => "plain"
    },
    $refresh
  );
  unless ($imgInfo) {
    $imgInfo->{file} = 'pixel.gif';
    $imgInfo->{filesize} = '807';
    $imgWeb = $Foswiki::cfg{SystemWebName};
    $imgTopic = 'ImagePlugin';
  }

  my $url = Foswiki::Func::getPubUrlPath($imgWeb, $imgTopic, $imgInfo->{file});
  Foswiki::Func::redirectCgiQuery($query, $url);

  my $expireHours = $refresh?0:8;
  $response->header(-cache_control => "max-age=".($expireHours * 60 * 60));

  return "";
}

###############################################################################
sub handleIMAGE {
  my ($this, $params, $theTopic, $theWeb) = @_;

  _writeDebug("called handleIMAGE(params, $theTopic, $theWeb)");

  if ($params->{_DEFAULT} && $params->{_DEFAULT} =~ m/^(?:clr|clear)$/io) {
    return $this->getTemplate('clear');
  }

  $params->{type} ||= '';

  # read parameters
  $this->parseMediawikiParams($params);

  my $origFile = $params->{_DEFAULT} || $params->{file} || $params->{src};
  return '' unless $origFile;

  $origFile =~ s/^\s+//;
  $origFile =~ s/\s+$//;

  _writeDebug("origFile=$origFile");

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
  $params->{zome} ||= 'off';
  $params->{crop} ||= '';
  $params->{tooltip} ||= 'off';
  $params->{tooltipcrop} ||= 'off';
  $params->{tooltipwidth} ||= '300';
  $params->{tooltipheight} ||= '300';
  $params->{lazyload} = Foswiki::Func::isTrue($params->{lazyload}, 0);

  $params->{class} =~ s/'/"/g;

  unless ($params->{size}) {
    $params->{size} = Foswiki::Func::getPreferencesValue("IMAGESIZE");
  }
  $params->{size} ||= '';

  unless ($params->{type}) {
    if ($params->{href} || $params->{width} || $params->{height} || $params->{size}) {
      $params->{type} = 'simple';
    } else {
      $params->{type} = 'plain';
    }
  }

  # validate args
  $params->{type} = 'thumb' if $params->{type} eq 'thumbnail';
  if ($params->{type} eq 'thumb' && !$params->{size}) {
    $params->{size} = Foswiki::Func::getPreferencesValue('THUMBNAIL_SIZE') || $this->{thumbSize};
  }

  if ($params->{size} =~ /^(\d+)(px)?x?(\d+)?(px)?$/) {
    $params->{size} = $3 ? "$1x$3" : $1;
  }

  $params->{height} =~ s/px$//;
  $params->{width} =~ s/px$//;

  my $imgWeb = $params->{web} || $theWeb;
  my $imgTopic;
  my $imgPath;
  my $pubDir = $Foswiki::cfg{PubDir};
  my $pubUrlPath = Foswiki::Func::getPubUrlPath();
  my $urlHost = Foswiki::Func::getUrlHost();
  my $pubUrl = URI->new($pubUrlPath, $urlHost);
  my $albumTopic;
  my $query = Foswiki::Func::getRequestObject();
  my $doRefresh = $query->param('refresh') || 0;
  $doRefresh = ($doRefresh =~ /^(on|1|yes|img)$/g) ? 1 : 0;

  $this->clearCache() if $doRefresh;

  # strip off prefix pointing to self
  my $selfUrl = $Foswiki::cfg{DefaultUrlHost} . $Foswiki::cfg{PubUrlPath};
  $selfUrl =~ s/^https?:\/\///;
  $origFile =~ s/^https?:\/\/$selfUrl\/?//;
  $origFile =~ s/^$Foswiki::cfg{PubUrlPath}//;
  $origFile =~ s/^\///;

  # search image
  if ($origFile =~ /^https?:\/\/.*/) {
    my $url = URI->new($origFile);
    $origFile = $url->path();
    $origFile =~ s/^.*[\\\/](.*?\.[a-zA-Z]+)/$1/;
    my $suffix = '';
    if ($origFile =~ /^(.*)\.(.*?)$/) {
      $origFile = $1;
      $suffix = $2;
    }
    my $mimeType = $this->suffixToMimeType($suffix);
    $suffix = "png" unless $mimeType =~ /^image\//; # SMELL: guessing png
    $origFile .= ".$suffix";

    # sanitize downloaded filename
    $origFile = _sanitizeAttachmentName($origFile);

    _writeDebug("sanizized to $origFile");

    $imgTopic = $params->{topic} || $theTopic;
    ($imgWeb, $imgTopic) = Foswiki::Func::normalizeWebTopicName($imgWeb, $imgTopic);
    $imgPath = $pubDir . '/' . $imgWeb;
    mkdir($imgPath) unless -d $imgPath;
    $imgPath .= '/' . $imgTopic;
    mkdir($imgPath) unless -d $imgPath;
    $imgPath .= '/' . $origFile;

    #_writeDebug("imgPath=$imgPath, url=$url");
    unless ($this->mirrorImage($imgWeb, $imgTopic, $url, $imgPath, $doRefresh)) {
      return $this->inlineError($params);
    }
  } elsif ($origFile =~ /(?:pub\/)?(?:(.+?)\/)?([^\/]+)\/([^\/]+?)$/) {
    $imgWeb = $1 || $theWeb;
    $imgTopic = $2;
    $origFile = $3;

    ($imgWeb, $imgTopic) = Foswiki::Func::normalizeWebTopicName($imgWeb, $imgTopic);
    $imgPath = $pubDir . '/' . $imgWeb . '/' . $imgTopic . '/' . $origFile;

    _writeDebug("looking for an image file at $imgPath");

    # you said so but it still is not there
    unless (-e $imgPath) {
      _writeDebug(" ... not found");
      $this->{errorMsg} = "(1) can't find <nop>$origFile at <nop>$imgWeb.$imgTopic";
      return $this->inlineError($params);
    }
  } else {
    my $testWeb;
    my $testTopic;

    if ($params->{topic}) {
      # topic parameter is known
      $imgTopic = $params->{topic};
      ($testWeb, $testTopic) = Foswiki::Func::normalizeWebTopicName($imgWeb, $imgTopic);
      $imgPath = $pubDir . '/' . $testWeb . '/' . $testTopic . '/' . $origFile;

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
      ($testWeb, $testTopic) = Foswiki::Func::normalizeWebTopicName($imgWeb, $theTopic);
      $imgPath = $pubDir . '/' . $testWeb . '/' . $testTopic . '/' . $origFile;

      unless (-e $imgPath) {
        # no, then look in the album
        $albumTopic = Foswiki::Func::getPreferencesValue('IMAGEALBUM', ($testWeb eq $theWeb) ? undef : $testWeb);
        unless ($albumTopic) {
          # not found, and no album
          $this->{errorMsg} = "(3) can't find <nop>$origFile in <nop>$imgWeb";
          return $this->inlineError($params);
        }
        $albumTopic = Foswiki::Func::expandCommonVariables($albumTopic, $testTopic, $testWeb) if $albumTopic =~ /%/;
        ($testWeb, $testTopic) = Foswiki::Func::normalizeWebTopicName($imgWeb, $albumTopic);
        $imgPath = $pubDir . '/' . $testWeb . '/' . $testTopic . '/' . $origFile;

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

  #_writeDebug("origFile=$origFile, imgWeb=$imgWeb, imgTopic=$imgTopic, imgPath=$imgPath");

  my $origFileUrl = $pubUrl . '/' . $imgWeb . '/' . $imgTopic . '/' . $origFile;

  $params->{alt} ||= $origFile unless defined $params->{alt};
  $params->{title} ||= $params->{caption} || $origFile unless defined $params->{title};
  $params->{desc} ||= $params->{title} unless defined $params->{desc};
  $params->{href} ||= Foswiki::Func::getScriptUrlPath("ImagePlugin", "process", "rest", 
    topic => $imgWeb.'.'.$imgTopic,
    file => $origFile,
    filter => $params->{filter},
    refresh => $doRefresh?"img":"",
  ) if defined $params->{filter};
  $params->{href} ||= $origFileUrl;

  #_writeDebug("type=$params->{type}, align=$params->{align}");
  #_writeDebug("size=$params->{size}, width=$params->{width}, height=$params->{height}");

  # compute image
  my $imgInfo = $this->processImage($imgWeb, $imgTopic, $origFile, $params, $doRefresh);

  unless ($imgInfo) {
    #Foswiki::Func::writeWarning("ImagePlugin - $this->{errorMsg}");
    return $this->inlineError($params);
  }

  # format result
  my $result = $params->{format};
  $result = $this->getTemplate($params->{type}) unless defined $result;
  $result ||= '';

  $result =~ s/\s+$//;    # strip whitespace at the end
  $result = $params->{header} . $result . $params->{footer};

  $result =~ s/\$caption/$this->getTemplate('caption')/ge if $params->{caption};
  $result =~ s/\$caption/$params->{caption}/g;
  $result =~ s/\$magnifyFormat/$this->getTemplate('magnify')/ge;
  $result =~ s/\$magnifyIcon/$this->{magnifyIcon}/g;
  $result =~ s/\$magnifyWidth/$this->{magnifyWidth}/g;
  $result =~ s/\$magnifyHeight/$this->{magnifyHeight}/g;
  $result =~ s/\$topic/$imgTopic/g;
  $result =~ s/\$web/$imgWeb/g;

  if ($params->{mousein}) {
    $result =~ s/\$mousein/onmouseover="$params->{mousein}"/g;
  } else {
    $result =~ s/\$mousein//g;
  }
  if ($params->{mouseout}) {
    $result =~ s/\$mouseout/onmouseout="$params->{mouseout}"/g;
  } else {
    $result =~ s/\$mouseout//g;
  }

  my $context = Foswiki::Func::getContext();
  my @html5Data =();
  if ($context->{JQueryPluginEnabled} && $params->{tooltip} eq 'on') {
    Foswiki::Plugins::JQueryPlugin::createPlugin("imagetooltip");
    $params->{class} .= " jqImageTooltip";
    push @html5Data, $this->formatHtml5Data("web", $imgWeb);
    push @html5Data, $this->formatHtml5Data("topic", $imgTopic);
    push @html5Data, $this->formatHtml5Data("image", $origFile);
    push @html5Data, $this->formatHtml5Data("crop", $params->{tooltipcrop});
    push @html5Data, $this->formatHtml5Data("width", $params->{tooltipwidth});
    push @html5Data, $this->formatHtml5Data("height", $params->{tooltipheight});
  }

  foreach my $key (keys %$params) {
    next unless $key =~ /^data_(.*)$/;
    my $val = $params->{$key};
    push @html5Data, $this->formatHtml5Data("data-$1", $params->{$key}) if $val ne "";
  }

  my $thumbFileUrl = $pubUrl . '/' . $imgWeb . '/' . $imgTopic . '/' . $imgInfo->{file};
  $thumbFileUrl = _urlEncode($thumbFileUrl);

  my $baseTopic = $this->{session}{topicName};
  my $absolute = ($context->{'command_line'} || $context->{'rss'} || $context->{'absolute_urls'} || $baseTopic =~ /^(WebRss|WebAtom)/);

  if ($absolute) {
    $params->{href} = $this->{session}{urlHost} . $params->{href} unless $params->{href} =~ /^[a-z]+:/;
    $thumbFileUrl = $this->{session}{urlHost} . $thumbFileUrl unless $thumbFileUrl =~ /^[a-z]+:/;
  }

  my $html5Data = join(" ", @html5Data);
  $result =~ s/\$data/$html5Data/g;
  $result =~ s/\$class/ $params->{class}/g;
  $result =~ s/\$href/$params->{href}/g;
  $result =~ s/\$src/$thumbFileUrl/g;
  $result =~ s/\$thumbfile/$imgInfo->{file}/g;
  $result =~ s/\$width/($this->pingImage($imgInfo))[0]/ge;
  $result =~ s/\$height/($this->pingImage($imgInfo))[1]/ge;
  $result =~ s/\$framewidth/($this->pingImage($imgInfo))[0]-1/ge;
  $result =~ s/\$origsrc/$origFileUrl/g;
  $result =~ s/\$origwidth/(pingOrigImage($this, $imgInfo))[0]/ge;
  $result =~ s/\$origheight/(pingOrigImage($this, $imgInfo))[1]/ge;
  $result =~ s/\$text/$origFile/g;
  $result =~ s/\$id/$params->{id}/g;
  $result =~ s/\$style/$params->{style}/g;
  $result =~ s/\$align/$params->{align}/g;
  $result =~ s/\$alt/_plainify($params->{alt})/ge;
  $result =~ s/\$title/_plainify($params->{title})/ge;
  $result =~ s/\$desc/_plainify($params->{desc})/ge;
  $result =~ s/\$lazyload/$params->{lazyload}?"loading='lazy' ":""/ge;

  $result =~ s/\$perce?nt/\%/g;
  $result =~ s/\$nop//g;
  $result =~ s/\$n/\n/g;
  $result =~ s/\$dollar/\$/g;

  # clean up empty 
  $result =~ s/(style|width|height|class|alt|id)=''//g;

  # recursive call for delayed TML expansion
  return '<noautolink>'.$result.'</noautolink>';
}

###############################################################################
sub pingImage {
  my ($this, $imgInfo) = @_;

  unless (defined $imgInfo->{width}) {
    _writeDebug("pinging $imgInfo->{imgPath}");
    ($imgInfo->{width}, $imgInfo->{height}, $imgInfo->{filesize}, $imgInfo->{format}) = $this->pingCached($imgInfo->{imgPath});
    $imgInfo->{width} ||= 0;
    $imgInfo->{height} ||= 0;
  }

  return ($imgInfo->{width}, $imgInfo->{height}, $imgInfo->{filesize}, $imgInfo->{format});
}

###############################################################################
sub pingOrigImage {
  my ($this, $imgInfo) = @_;

  unless (defined $imgInfo->{origWidth}) {
    if (_isFramish($imgInfo->{origImgPath})) {
      _writeDebug("not pinging $imgInfo->{origImgPath} ... potentially large files consisting of frames");
    } else {
      _writeDebug("pinging orig $imgInfo->{origImgPath}");
      ($imgInfo->{origWidth}, $imgInfo->{origHeight}, $imgInfo->{origFilesize}, $imgInfo->{origFormat}) = $this->pingCached($imgInfo->{origImgPath});
    }
    $imgInfo->{origWidth} ||= 0;
    $imgInfo->{origHeight} ||= 0;
  }

  return ($imgInfo->{origWidth}, $imgInfo->{origHeight}, $imgInfo->{origFilesize}, $imgInfo->{origFormat});
}

###############################################################################
sub pingCached {
  my ($this, $imgPath) = @_;

  my $width;
  my $height;
  my $size;
  my $format;
  my $cache = Foswiki::Contrib::CacheContrib::getCache("ImagePlugin");
  my $entry = $cache->get($imgPath);

  #print STDERR "looking up cache for $imgPath\n";

  if ($entry && $entry =~ /^(.*)::(.*)::(.*)::(.*)$/) {
    $width = $1;
    $height = $2;
    $size = $3;
    $format = $4;
    #print STDERR "... found. width=$width, height=$height, size=$size, format=$format\n";
  } else {
    ($width, $height, $size, $format) = $this->mage->Ping($imgPath);
    $entry = $width.'::'.$height.'::'.$size.'::'.$format;
    $cache->set($imgPath, $entry);
    #print STDERR "... pinging image. width=$width, height=$height, size=$size, format=$format\n";
  }

  return ($width, $height, $size, $format);
}

###############################################################################
sub clearCache {
  my $this = shift;
  return Foswiki::Contrib::CacheContrib::clearCache("ImagePlugin");
}

###############################################################################
sub processImage {
  my ($this, $imgWeb, $imgTopic, $imgFile, $params, $doRefresh) = @_;

  my $size = $params->{size} || '';
  my $crop = $params->{crop} || 'off';
  my $zoom = $params->{zoom} || 'off';
  my $width = $params->{width} || '';
  my $height = $params->{height} || '';
  my $output = $params->{output} || '';
  my $rotate = $params->{rotate} || '';
  my $filter = $params->{filter} || '';
  my $transparent = $params->{transparent} || '';

  _writeDebug("called processImage(web=$imgWeb, topic=$imgTopic, file=$imgFile, size=$size, crop=$crop, width=$width, height=$height, rotate=$rotate, refresh=$doRefresh, output=$output, transparent=$transparent)");

  $this->{errorMsg} = '';

  my %imgInfo = (
    imgWeb => $imgWeb,
    imgTopic => $imgTopic,
    origFile => $imgFile,
    origImgPath => $Foswiki::cfg{PubDir} . '/' . $imgWeb . '/' . $imgTopic . '/' . $imgFile,
    file => undef,
    imgPath => undef,
  );

  my $frame;
  if (defined $params->{layer}) {
    $frame = $params->{layer};
  } elsif (defined $params->{frame}) {
    $frame = $params->{frame};
  } else {
    $frame = '0' if _isFramish($imgInfo{origImgPath}) || 
      ($imgInfo{origImgPath} =~ /\.gif$/ && (!$params->{type} || $width || $height || $size)); # let's extract frame 0 for gifs as well
  }
  if (defined $frame) {
    $frame =~ s/^.*?(\d+).*$/$1/g;
    $frame = 1000 if $frame > 1000;    # for security
    $frame = 0 if $frame < 0;
    $frame = '[' . $frame . ']';
  } else {
    $frame = '';
  }

  if ($size || ($crop && $crop ne 'off') || $width || $height || $rotate || $doRefresh || !_isWebby($imgFile) || $output || $filter || ($frame && $frame ne '') || $transparent) {
    if (!$size) {
      if ($width || $height) {
        $size = $width . 'x' . $height;
      }
    }
    if ($size && $size !~ /[<>^]$/) {
      if ($zoom eq 'on') {
        $size .= '<';
      } else {
        $size .= '>';
      }
      if ($crop ne 'off') {
        $size .= '^';
      }
    }
    #_writeDebug("size=$size");

    $imgInfo{file} = $this->getImageFile(
      $imgWeb, $imgTopic, $imgFile, {
        size => $size, 
        zoom => $zoom, 
        crop => $crop, 
        rotate => $rotate, 
        frame => $frame, 
        output => $output, 
        filter => $filter
      }
    );
    unless ($imgInfo{file}) {
      $this->{errorMsg} = "(5) can't find <nop>$imgFile at <nop>$imgWeb.$imgTopic";
      return;
    }
    $imgInfo{imgPath} = $Foswiki::cfg{PubDir} . '/' . $imgWeb . '/' . $imgTopic . '/' . $imgInfo{file};

    $imgInfo{oldImgPath} = $Foswiki::cfg{PubDir} . '/' . $imgWeb . '/' . $imgTopic . '/_' . $imgInfo{file};

    #_writeDebug("checking for $imgInfo{imgFile}");

    # compare file modification times
    $doRefresh = 1
      if (-f $imgInfo{imgPath} && _getModificationTime($imgInfo{origImgPath}) > _getModificationTime($imgInfo{imgPath})) ||
         (-f $imgInfo{oldImgPath} && _getModificationTime($imgInfo{origImgPath}) > _getModificationTime($imgInfo{oldImgPath}));

    if (-f $imgInfo{oldImgPath} && !$doRefresh) {    # cached
      _writeDebug("found old thumbnail for $imgInfo{file} at $imgWeb.$imgTopic");
      rename $imgInfo{oldImgPath}, $imgInfo{imgPath};
      $imgInfo{filesize} = -s $imgInfo{imgPath};
    } elsif (-f $imgInfo{imgPath} && !$doRefresh) {    # cached
      _writeDebug("found thumbnail $imgInfo{file} at $imgWeb.$imgTopic");
      $imgInfo{filesize} = -s $imgInfo{imgPath};
    } else {
      _writeDebug("creating $imgInfo{file}");

      my $source = $imgInfo{origImgPath} . $frame;

      # read
      _writeDebug("reading $source");
      my $error = $this->mage->Read($source);
      if ($error =~ /(\d+)/) {
        $this->{errorMsg} = $error;
        return if $1 >= 400;
      }

      # set density in case we have an svg
      if ($imgFile =~ /\.svgz?/i) {
        _writeDebug("upping the density to 200");
        $error = $this->mage->Set(density => 200);
        if ($error =~ /(\d+)/) {
          $this->{errorMsg} = $error;
          _writeDebug("Error: $error");
          return if $1 >= 400;
        }
      }

      # merge layers
      if ($imgFile =~ /\.(xcf|psd)$/i) {
        _writeDebug("merge");
        $this->{mage} = $this->mage->Layers(method => 'merge');
      }

      # scale
      if ($size) {
        _writeDebug("scale");
        my $geometry = $size;
        # SMELL: As of IM v6.3.8-3 IM now has a new geometry option flag '^' which
        # is used to resize the image based on the smallest fitting dimension.
        if ($crop ne 'off' && $geometry !~ /\^/) {
          $geometry .= '^';
        }

        _writeDebug("resize($geometry)");
        $error = $this->mage->Resize(geometry => $geometry);
        if ($error =~ /(\d+)/) {
          $this->{errorMsg} = $error;
          return if $1 >= 400;
        }

        # gravity
        if ($crop =~ /^(on|northwest|north|northeast|west|center|east|southwest|south|southeast)$/i) {
          $crop = "center" if $crop eq 'on';
          _writeDebug("Set(Gravity=>$crop)");
          $error = $this->mage->Set(Gravity => "$crop");
          if ($error =~ /(\d+)/) {
            $this->{errorMsg} = $error;
            _writeDebug("Error: $error");
            return if $1 >= 400;
          }

          my $geometry = '';
          if ($size) {
            unless ($size =~ /\d+x\d+/) {
              $size = $size . 'x' . $size;
            }
            $geometry = $size . '+0+0';
            $geometry =~ s/[<>^@!]//g;
          } else {
            $geometry = $width . 'x' . $height . '+0+0';
          }

          # new method
          _writeDebug("extent(geometry=>$geometry)");
          $error = $this->mage->Extent($geometry);
          if ($error =~ /(\d+)/) {
            $this->{errorMsg} = $error;
            _writeDebug("Error: $error");
            return if $1 >= 400;
          }
        }
      } elsif ($crop =~ /^\d+x\d+[\+\-]\d+[\+\-]\d+$/) {
        $error = $this->mage->Crop(geometry => $crop);
        if ($error =~ /(\d+)/) {
          $this->{errorMsg} = $error;
          _writeDebug("Error: $error");
          return if $1 >= 400;
        }
        # SMELL: is repaging needed?
        #$this->mage->Set(page => "0x0+0+0"); 
      }

      # auto orient
      _writeDebug("auto orient");
      $error = $this->mage->AutoOrient();
      if ($error =~ /(\d+)/) {
        $this->{errorMsg} = $error;
        _writeDebug("Error: $error");
        return if $1 >= 400;
      }

      # strip of profiles and comments
      _writeDebug("strip");
      $error = $this->mage->Strip();
      if ($error =~ /(\d+)/) {
        $this->{errorMsg} = $error;
        _writeDebug("Error: $error");
        return if $1 >= 400;
      }

      # rotate
      if ($rotate) {
        _writeDebug("rotate");
        $error = $this->mage->Rotate(degrees => $rotate);
        if ($error =~ /(\d+)/) {
          $this->{errorMsg} = $error;
          _writeDebug("Error: $error");
          return if $1 >= 400;
        }
      }

      # filter
      if ($filter) {
        _writeDebug("filter=$filter");

        $filter =~ s/^\s+|\s+$//g;
        while ($filter =~ /\s*\b(\w+)(?:\(\s*(.*?)\s*\))?\s*(?:;|$)/g) {
          my $f = $1;
          my @params = split(/\s*,\s*/, $2 || '');

          $error = $this->filter->apply($f, @params);

          if ($error) {
            $this->{errorMsg} = $error;
            _writeDebug("Error: $this->{errorMsg}");
            return;
          }
        }
      }

      # transparent background
      if ($transparent) {
        my $fuzz = 100;
        _writeDebug("fuzz=$fuzz");
        $error = $this->mage->Set(fuzz => $fuzz);
        if ($error =~ /(\d+)/) {
          $this->{errorMsg} = $error;
          _writeDebug("Error: $error");
          return if $1 >= 400;
        }
        _writeDebug("transparent=$transparent");
        $error = $this->mage->Transparent(color => $transparent);
        if ($error =~ /(\d+)/) {
          $this->{errorMsg} = $error;
          _writeDebug("Error: $error");
          return if $1 >= 400;
        }
      }


      # write
      _writeDebug("writing to $imgInfo{imgPath}");
      $error = $this->mage->Write($imgInfo{imgPath});
      if ($error =~ /(\d+)/) {
        $this->{errorMsg} .= " $error";
        _writeDebug("Error: $error");
        return if $1 >= 400;
      }

      # fix file perms
      chmod($Foswiki::cfg{Store}{filePermission}, $imgInfo{imgPath});

      ($imgInfo{width}, $imgInfo{height}, $imgInfo{filesize}, $imgInfo{format}) = $this->mage->Get('width', 'height', 'filesize', 'format');
      $imgInfo{width} ||= 0;
      $imgInfo{height} ||= 0;
    }
  } else {
    $imgInfo{file} = $imgInfo{origFile};
    $imgInfo{imgPath} = $imgInfo{origImgPath};
  }
  _writeDebug("done");

  # unload images
  my $mage = $this->mage;
  @$mage = ();

  return \%imgInfo;
}

###############################################################################
sub beforeSaveHandler {
  my ($this, undef, $topic, $web, $meta) = @_;

  # clear all thumbs on save
  $this->flagThumbsForDeletion($web, $topic);

  return unless $this->{autoAttachInlineImages};

  _writeDebug("called beforeSaveHandler");

  my $wikiName = Foswiki::Func::getWikiName();
  return unless Foswiki::Func::checkAccessPermission("CHANGE", $wikiName, undef, $topic, $web);

  $meta = Foswiki::Func::readTopic($web, $topic) unless defined $meta;
  my $text = $meta->text() // '';

  my $i = 0;
  my @images = ();

  while ($text =~ s/<img\s+([^>]*?)\s*src=["']data:([a-z]+\/[a-z\-\.\+]+)?(;[a-z\-]+\=[a-z\-]+)?;base64,(.*?)["']\s*([^>]*?)\s*\/?>/_IMAGE_$i/i) {

    my $before = $1 || '';
    my $mimeType = $2;
    my $charset = $3 || '';
    my $data = MIME::Base64::decode_base64($4);
    my $after = $5 || '';

    my $suffix;
    if (defined $mimeType) {
      $suffix = $this->mimeTypeToSuffix($mimeType);
    } else {
      (undef, undef, undef, $suffix) = $this->mage->Ping(blob=>$data);
      $suffix = lc($suffix);
      $suffix =~ s/(bmp)\d/$1/g; # SMELL: rewrite some
    }
    my $size = do { use bytes; length $data };
    my $attachment = Digest::MD5::md5_hex($data) . '.' . $suffix;

    my $fh = File::Temp->new();
    my $filename = $fh->filename;
    binmode($fh);

    my $offset = 0;
    my $r = $size;
    while ($r) {
      my $w = syswrite($fh, $data, $r, $offset);
      die "system write error: $!\n" unless defined $w;
      $offset += $w;
      $r -= $w;
    }

    $meta->attach(
      name => $attachment,
      file => $filename,
      filesize => $size,
      minor => 1,
      dontlog => 1,
      comment => 'Auto-attached by ImagePlugin',
    );

    my $image = $this->{inlineImageTemplate};
    $image =~ s/%WEB%/$web/g;
    $image =~ s/%TOPIC%/$topic/g;
    $image =~ s/%ATTACHMENT%/$attachment/g;
    $image =~ s/%BEFORE%/$before/;
    $image =~ s/%AFTER%/$after/;

    push @images, $image;
    $i++;
  }

  $i = 0;

  # patch in the markup
  foreach my $image (@images) {
    $text =~ s/_IMAGE_$i/$image/ or print STDERR "WOOPS not found\n";
    $i++;
  }

  $meta->text($text) if $i;
}

###############################################################################
sub afterRenameHandler {
  my ($this, $oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment) = @_;

  # print STDERR "afterRename(oldWeb=$oldWeb, oldTopic=$oldTopic, oldAttachment=".
  #   ($oldAttachment||'undef').", newWeb=".
  #   ($newWeb||'undef').", newTopic=".
  #   ($newTopic||'undef').", newAttachment=".
  #   ($newAttachment||'undef').")\n";

  return unless defined $oldAttachment;
  return unless defined $newAttachment;
  return
       if $oldAttachment eq $newAttachment
    && $oldWeb eq $newWeb
    && $oldTopic eq $newTopic;

  _writeDebug("called afterRenameHandler");

  # attachment has been renamed, delete old thumbnails
  $this->flagThumbsForDeletion($oldWeb, $oldTopic, $oldAttachment);
}

###############################################################################
sub flagThumbsForDeletion {
  my ($this, $web, $topic, $attachment) = @_;

  if (defined $attachment) {
    $attachment = quotemeta($attachment);
  } else {
    $attachment = ".*";
  }

  opendir(my $dh, $Foswiki::cfg{PubDir} . '/' . $web . '/' . $topic . '/') || return;
  my @thumbs = grep { /^igp_[0-9a-f]{32}_$attachment$/ } readdir $dh;
  closedir $dh;

  _writeDebug("renaming ".scalar(@thumbs)." thumbs");

  foreach my $file (@thumbs) {
    my $oldPath = $web . '/' . $topic . '/' . $file;
    $oldPath = Foswiki::Sandbox::untaint($oldPath, \&Foswiki::Sandbox::validateAttachmentName);
    my $newPath = $web . '/' . $topic . '/_' . $file;
    $newPath = Foswiki::Sandbox::untaint($newPath, \&Foswiki::Sandbox::validateAttachmentName);
    _writeDebug("flagging thumbnail $file for deletion");
    rename $Foswiki::cfg{PubDir} . '/' . $oldPath, $Foswiki::cfg{PubDir} . '/' . $newPath;
  }
}

###############################################################################
sub clearAllThumbs {
  my ($this, $web, $topic, $attachment) = @_;

  if (defined $attachment) {
    $attachment = quotemeta($attachment);
  } else {
    $attachment = ".*";
  }
  return $this->clearMatchingThumbs($web, $topic, $attachment, "igp_[0-9a-f]{32}_$attachment");
}

###############################################################################
sub clearOutdatedThumbs {
  my ($this, $web, $topic, $attachment) = @_;

  if (defined $attachment) {
    $attachment = quotemeta($attachment);
  } else {
    $attachment = ".*";
  }
  return $this->clearMatchingThumbs($web, $topic, $attachment, "_igp_[0-9a-f]{32}_$attachment");
}

###############################################################################
sub clearMatchingThumbs {
  my ($this, $web, $topic, $attachment, $pattern) = @_;

  $web //= $this->{session}{webName};
  $topic //= $this->{session}{topicName};
  if (defined $attachment) {
    $attachment = quotemeta($attachment);
  } else {
    $attachment = ".*";
  }
  $pattern //= 'igp_[0-9a-f]{32}_'.$attachment;

  opendir(my $dh, $Foswiki::cfg{PubDir} . '/' . $web . '/' . $topic . '/') || return;
  my @thumbs = grep { /^$pattern$/ } readdir $dh;
  closedir $dh;

  _writeDebug("deleting ".scalar(@thumbs)." thumbs at $web.$topic");

  foreach my $file (@thumbs) {
    my $thumbPath = $web . '/' . $topic . '/' . $file;
    $thumbPath = Foswiki::Sandbox::untaint($thumbPath, \&Foswiki::Sandbox::validateAttachmentName);
    _writeDebug("deleting thumbnail $file");
    unlink $Foswiki::cfg{PubDir} . '/' . $thumbPath;
  }
}

###############################################################################
sub takeOutSVG {
  my $this = shift;
  #my $text = $_[0];

  $_[0] =~ s/(<svg.*?<\/svg>)/$this->processInlineSvg($1)/geims;
}

###############################################################################
sub processInlineSvg {
  my ($this, $data) = @_;

  my $imgWeb = $this->{session}{webName};
  my $imgTopic = $this->{session}{topicName};
  my $topicPath = $Foswiki::cfg{PubDir} . '/' . $imgWeb . '/' . $imgTopic;

  my $digest = Digest::MD5::md5_hex($data);
  my $svgFile = $digest.'.svg';
  my $svgPath = $topicPath . '/' . $svgFile;

  unless (-e $svgPath) {
    mkdir($topicPath) unless -d $topicPath;
    Foswiki::Func::saveFile($svgPath, $data);
  }

  my $imgFile = $this->getImageFile(
    $imgWeb, $imgTopic, $svgFile, {
      zoom => 'off', 
      crop => 'off', 
      rotate => '', 
      frame => '', 
    }
  );

  my $imgPath = $topicPath . '/' . $imgFile;

  my ($topicDate) = Foswiki::Func::getRevisionInfo($imgWeb, $imgTopic);
  my $imgDate = -e $imgPath ? _getModificationTime($imgPath) : 0;

  my $imgInfo;

  #print STDERR "svgPath=$svgPath, imgPath=$imgPath, imgFile=$imgFile\n";

  if ($topicDate > $imgDate) {
    #print STDERR "generating fresh png from svg\n";


    $imgInfo = $this->processImage(
      $imgWeb, $imgTopic, $svgFile, {
        size => '',
        zoom => 'off',
        crop => 'off',
        width => '',
        height => '',
      },
      1
    );

    return $this->inlineError unless $imgInfo;

  } else {
    #print STDERR "png is up-to-date\n";
    $imgInfo = {
      file => $imgFile,
      imgPath => $imgPath,
    };
  }

  my $pubUrlPath = Foswiki::Func::getPubUrlPath();
  my $urlHost = Foswiki::Func::getUrlHost();
  my $pubUrl = URI->new($pubUrlPath, $urlHost);
  my $thumbFileUrl = $pubUrl . '/' . $imgWeb . '/' . $imgTopic . '/' . $imgInfo->{file};
  $thumbFileUrl = _urlEncode($thumbFileUrl);

  my $result = $this->getTemplate("plain");

  $result =~ s/\$src/$thumbFileUrl/g;
  $result =~ s/\$width/($this->pingImage($imgInfo))[0]/ge;
  $result =~ s/\$height/($this->pingImage($imgInfo))[1]/ge;
  $result =~ s/\$framewidth/($this->pingImage($$imgInfo))[0]-1/ge;
  $result =~ s/\$class//g;
  $result =~ s/\$data//g;
  $result =~ s/\$id//g;
  $result =~ s/\$style//g;
  $result =~ s/\$align/none/g;
  $result =~ s/\$alt//g;
  $result =~ s/\$title/auto-converted from inline svg/g;
  $result =~ s/\$desc//g;
  $result =~ s/\$mousein//g;
  $result =~ s/\$mouseout//g;

  $result =~ s/\$perce?nt/\%/g;
  $result =~ s/\$nop//g;
  $result =~ s/\$n/\n/g;
  $result =~ s/\$dollar/\$/g;

  # clean up empty 
  $result =~ s/(style|width|height|class|alt|id)=''//g;

  unlink ($svgPath);

  return $result;
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
    if ($arg =~ /^(right|left|center|none)$/i) {
      $params->{align} = $1 unless $params->{align};
    } elsif ($arg =~ /^frame$/i) {
      $params->{type} = 'frame';
    } elsif ($arg =~ m/^thumb(nail)?$/i) {
      $params->{type} = 'thumb' unless $params->{type};
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
    if !$params || $params->{warn} eq 'on' || $params->{warn} eq '';
  return $params ? $params->{warn} : 'undefined warning';
}

###############################################################################
# mirrors an image and attach it to the given web.topic
# turns true on success; on false errorMsg is set
sub mirrorImage {
  my ($this, $web, $topic, $url, $fileName, $force) = @_;

  _writeDebug("called mirrorImage($url, $fileName, $force)");
  return 1 if !$force && -e "$fileName";

  _writeDebug("didn't find $fileName");

  my $downloadFileName;

  if ($this->{autoAttachExternalImages}) {
    my $tempImgFile = new File::Temp();
    $downloadFileName = $tempImgFile->filename;
  } else {

    # we still need to download it as we can't resize it otherwise
    $downloadFileName = $fileName;
  }

  _writeDebug("fetching $url into $downloadFileName");

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
      $ua->proxy(['http', 'https'], $proxy);

      my $proxySkip = $Foswiki::cfg{PROXY}{NoProxy};
      if ($proxySkip) {
        my @skipDomains = split(/\s*,\s*/, $proxySkip);
        $ua->no_proxy(@skipDomains);
      }
    }

    $this->{ua} = $ua;
  }

  my $response = $this->{ua}->get($url, ':content_file' => $downloadFileName);
  my $code = $response->code;
  _writeDebug("response code=$code");

  unless ($response->is_success || $response->code == 304) {
    my $status = $response->status_line;
    $this->{errorMsg} = "can't fetch image from '$url': $status";
    _writeDebug("Error: $this->{errorMsg}");
    return 0;
  }

  my $contentType = $response->header('content-type') || '';
  _writeDebug("contentType=$contentType");
  unless ($contentType =~ /^image/) {
    $this->{errorMsg} = "not an image at '$url'";
    _writeDebug("Error: $this->{errorMsg}");
    unlink $downloadFileName;
    return 0;
  }

  my $clientAborted = $response->header('client-aborted') || 0;
  if ($clientAborted eq 'max_size') {
    $this->{errorMsg} = "can't fetch image from '$url': max size exceeded";
    _writeDebug("Error: $this->{errorMsg}");
    unlink $downloadFileName;
    return 0;
  }

  my $filesize = $response->header('content_length') || 0;
  _writeDebug("filesize=$filesize");

  # properly register the file to the store
  $this->updateAttachment($web, $topic, $fileName, {path => $url, filesize => $filesize, file => $downloadFileName})
    if $this->{autoAttachExternalImages};

  return 1;
}

###############################################################################
sub getImageFile {
  my ($this, $web, $topic, $file, $params) = @_;

  $params //= {};

  my $imgPath = $Foswiki::cfg{PubDir} . '/' . $web . '/' . $topic . '/' . $file;
  my $fileSize = -s $imgPath;
  return unless defined $fileSize;    # not found


  my $digest = Digest::MD5->new();
  foreach my $key (sort keys %$params) {
    next if $key =~ /^(web|topic|output)$/;
    $digest->add("$key=$params->{$key}") 
  }

  $digest->add($fileSize);
  $digest = $digest->hexdigest;

  # force conversion of some non-webby image formats
  $file =~ s/\.(.*?)$/\.png/g unless _isWebby($file);

  # switch manually specified output format
  if ($params->{output} && $file =~ /^(.+)\.([^\.]+)$/) {
    $file = $1 . '.' . $params->{output};
  }

  if ($file =~ /^(.*)\/(.+?)$/) {
    return $1 . "/igp_" . $digest . "_" . _sanitizeAttachmentName($2);
  } else {
    return "igp_" . $digest . "_" . _sanitizeAttachmentName($file);
  }
}

###############################################################################
sub updateAttachment {
  my ($this, $web, $topic, $filename, $params) = @_;

  return unless Foswiki::Func::topicExists($web, $topic);

  _writeDebug("called updateAttachment($web, $topic, $filename)");

  my $baseFilename = $filename;
  $baseFilename =~ s/^(.*)[\/\\](.*?)$/$2/;

  my $args = {
    comment => 'Auto-attached by ImagePlugin',
    dontlog => 1,
    filedate => time(),
    #hide=>1,
    minor => 1,
    #notopicchange=>1, # SMELL: does not work
  };
  $args->{file} = $params->{file} if $params->{file};
  $args->{filepath} = $params->{path} if $params->{path};

  # SMELL: this is called size in the meta data, but seems to need a filesize attr for the api
  $args->{size} = $params->{filesize} if $params->{filesize};
  $args->{filesize} = $params->{filesize} if $params->{filesize};

  try {
    Foswiki::Func::saveAttachment($web, $topic, $baseFilename, $args);
  }
  catch Foswiki::AccessControlException with {
    # ignore
    my $user = Foswiki::Func::getCanonicalUserID();
    _writeDebug("$user has no access rights to $web.$topic");
  }
  catch Foswiki::OopsException with {
    # ignore
    my $e = shift;
    my $message = 'ERROR: ' . $e->stringify();
    _writeDebug($message);
    #print STDERR "$message\n";
  };
}

###############################################################################
sub getTemplate {
  my ($this, $name) = @_;

  return '' unless $name;
  $name = 'image:' . $name;

  unless (defined $this->{$name}) {
    unless (defined $this->{imageplugin}) {
      $this->{imageplugin} = Foswiki::Func::loadTemplate("imageplugin");
    }
    $this->{$name} = Foswiki::Func::expandTemplate($name) || '';
  }

  return $this->{$name};
}

###############################################################################
sub readMimeTypes {
  my $this = shift;

  unless ($this->{types}) {
    $this->{types} = Foswiki::readFile($Foswiki::cfg{MimeTypesFileName});
  }

  return $this->{types};
}

###############################################################################
sub mimeTypeToSuffix {
  my ($this, $mimeType) = @_;

  my $suffix = '';
  if ($mimeType =~ /.*\/(.*)/) {
    $suffix = $1;             # fallback
  }

  $this->readMimeTypes();

  if ($this->{types} =~ /^$mimeType\s*(\S*)(?:\s|$)/im) {
    $suffix = $1;
  }

  return $suffix;
}

###############################################################################
sub suffixToMimeType {
  my ($this, $suffix) = @_;

  my $mimeType;
  $suffix =~ s/^.*\.(.*?)$/$1/;

  $this->readMimeTypes();

  if ($this->{types} =~ /^(.*?)\s+.*\b$suffix\b/im) {
    $mimeType = $1;
  }

  return $mimeType;
}

##############################################################################
# static functions

###############################################################################
# returns true if image can be displayed as is,
# returns false if we want to force conversion to png
sub _isWebby {
  my $file = shift;

  return 1 if $file =~ /\.(png|jpe?g|gif|bmp|webp|svgz?)$/i;
  return 0;
}

###############################################################################
# returns true if file format may contain more than one frame and thus
# we default to extracting the first one 
sub _isFramish {
  my $file = shift;

  return 1 if _isVideo($file) || $file =~ /\.(tiff?|pdf|ps|psd|pptx?|docx?|odt|xlsx?)$/i;
  return 0;
}

###############################################################################
sub _isVideo {
  my $file = shift;

  return 1 if $file =~ /\.(mp4|mpe?g|mpe|m4v|ogv|qt|mov|flv|asf|asx|avi|wmv|wm|wmx|wvx|movie|swf|webm)$/;
  return 0;
}

###############################################################################
sub _plainify {
  my $text = shift;

  return '' unless $text;

  $text =~ s/<!--.*?-->//gs;    # remove all HTML comments
  $text =~ s/\&[a-z]+;/ /g;     # remove entities
  $text =~ s/\[\[([^\]]*\]\[)(.*?)\]\]/$2/g;
  $text =~ s/<[^>]*>//g;        # remove all HTML tags
  $text =~ s/[\[\]\*\|=_\&\<\>]/ /g;    # remove Wiki formatting chars
  $text =~ s/^\-\-\-+\+*\s*\!*/ /gm;    # remove heading formatting and hbar
  $text =~ s/^\s+//o;                   # remove leading whitespace
  $text =~ s/\s+$//o;                   # remove trailing whitespace
  $text =~ s/"/ /o;

  return $text;
}

###############################################################################
# from Foswiki.pm
sub _urlEncode {
  my $text = shift;

  $text = Encode::encode_utf8($text) if $Foswiki::UNICODE;
  $text =~ s/([^0-9a-zA-Z-_.:~!*'\/])/sprintf('%%%02x',ord($1))/ge;

  return $text;
}

###############################################################################
sub _getModificationTime {
  my $file = shift;
  return 0 unless $file;
  my @stat = stat($file);
  return $stat[9] || $stat[10] || 0;
}

##############################################################################
sub _sanitizeAttachmentName {
  my $fileName = shift;

  my $origFileName = $fileName;

  my $filter = 
    $Foswiki::cfg{AttachmentNameFilter}  ||
    $Foswiki::cfg{NameFilter} ||
    '[^[:alnum:]\. _-]';

  $fileName =~ s{[\\/]+$}{};    # Get rid of trailing slash/backslash (unlikely)
  $fileName =~ s!^.*[\\/]!!;    # Get rid of leading directory components
  $fileName =~ s/$filter+//g;
  $fileName =~ s/[{},\(\)]/_/g;    # some more

  return Foswiki::Sandbox::untaintUnchecked($fileName);
}

###############################################################################
sub _writeDebug {
  print STDERR "ImagePlugin - $_[0]\n" if TRACE;
}

###############################################################################
sub json {
  my $this = shift;

  unless (defined $this->{json}) {
    $this->{json} = JSON->new->allow_nonref(1);
  }

  return $this->{json};
}

###############################################################################
sub formatHtml5Data {
  my ($this, $key, $val) = @_;

  if (ref($val)) {
    $val = $this->_json->encode($val);
  } else {
    $val = Foswiki::entityEncode($val);
  }
  return "data-$key='$val'";
}

1;
