# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2016-2019 Michael Daum http://michaeldaumconsulting.com
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
package Foswiki::Plugins::ImagePlugin::Filter;

use strict;
use warnings;
use POSIX;

use constant TRACE => 0;    # toggle me

sub writeDebug {
  print STDERR "ImagePlugin::Filter - $_[0]\n" if TRACE;
}

sub new {
  my $class = shift;
  my $core = shift;

  my $this = bless({
      core => $core,
      alias => {
        "negative" => "negate",
        "saturation" => "saturate",
      },
      @_
    },
    $class
  );

  return $this;
}

sub currentImage {
  my ($this, $image) = @_;

  $this->{image} = $image;
}

sub mage {
  my $this = shift;

  return $this->{image} if defined $this->{image};
  return $this->{core}->mage;
}

sub createImage {
  my $this = shift;
  return $this->{core}->createImage(@_);
}

sub apply {
  my $this = shift;
  my $filter = shift;

  return if $filter eq 'none'; # because we can

  $filter = $this->{alias}{$filter} if defined $this->{alias}{$filter};
  my $sub = "filter_".$filter;

  return "unknown filter '$filter'" unless $this->can($sub);

  writeDebug("applying filter='$filter' params=".join(",",@_));

  return $this->$sub(@_);
} 

### low-level filters
sub filter_autogamma {
  my $this = shift;
  return $this->mage->AutoGamma();
}

sub filter_autolevel {
  my $this = shift;
  return $this->mage->AutoLevel();
}

sub filter_background {
  my ($this, $color) = @_;
  $color //= 'none';
  return $this->mage->Set(background => $color);
}

sub filter_blueshift {
  my ($this, $factor) = @_;
  $factor //= 1.5;
  return $this->mage->BlueShift(factor => $factor);
}

sub filter_blur {
  my ($this, $radius, $sigma) = @_;

  my %p = ();
  $p{radius} = $radius if defined $radius && $radius ne '';
  $p{sigma} = $sigma if defined $sigma && $sigma ne '';

  return $this->mage->Blur(%p);
}

sub filter_brightness {
  my ($this, $brightness) = @_;
  $brightness //= 150;
  return $this->mage->Modulate(brightness => $brightness);
}

sub filter_charcoal {
  my ($this, $radius, $sigma) = @_;

  my %p = ();
  $p{radius} = $radius if defined $radius && $radius ne '';
  $p{sigma} = $sigma if defined $sigma && $sigma ne '';

  return $this->mage->Charcoal(%p);
}

sub filter_colorize {
  my ($this, $fill, $blend) = @_;

  $blend //= '50%';

  return $this->mage->Colorize(fill=>$fill, blend=>$blend);
}

sub filter_contrast {
  my ($this, @params) = @_;

  my $contrast = join(",", @params);
  $contrast ||= '5';

  return $this->mage->SigmoidalContrast(geometry=>$contrast);
}

sub filter_emboss {
  my ($this, $radius, $sigma) = @_;

  my %p = ();
  $p{radius} = $radius if defined $radius && $radius ne '';
  $p{sigma} = $sigma if defined $sigma && $sigma ne '';

  return $this->mage->Emboss(%p);
}

sub filter_equalize {
  my ($this, $channel) = @_;
  $channel //= 'all';
  return  $this->mage->Equalize(channel=>$channel);
}

sub filter_gamma {
  my ($this, $gamma) = @_;
  $gamma //= 2.2;
  return $this->mage->Gamma(gamma=>$gamma);
}

sub filter_grayscale {
  my ($this, $factor) = @_;

  $factor //= "100%";

  my $clone = $this->mage->Clone();
  my $error;

  $error = $clone->Grayscale();
  $error = $this->mage->Composite(compose=>'over', image=>$clone, opacity=>$factor) unless $error;

  return $error;
}

sub filter_hue {
  my ($this, $hue) = @_;

  $hue //= "150";
  return $this->mage->Modulate(hue => $hue);
}

sub filter_level {
  my ($this, @params) = @_;

  my $levels = join(",", @params);
 
  writeDebug("filter_level(levels=$levels)");

 
  return $this->mage->Level(levels=>$levels);
}

sub filter_levelcolors {
  my ($this, $color1, $color2, $invert) = @_;

  my %p = ();
  $p{invert} = $invert // 1;
  $p{'black-point'} = $color1 if defined $color1 && $color1 ne "";
  $p{'white-point'} = $color2 if defined $color2 && $color2 ne "";

  writeDebug("filter_levelcolors(".join(", ", map {$_."=".$p{$_}} sort keys %p).")");

  return $this->mage->LevelColors(%p);
}

sub filter_negate {
  my ($this) = @_;

  return $this->mage->Negate();
}

sub filter_noise {
  my ($this, $noise, $attenuate) = @_;

  $noise //= 'Uniform';

  $attenuate //= lc($noise) eq 'uniform' ? 10:1;

  return $this->mage->AddNoise(noise => $noise, attenuate => $attenuate);
}


sub filter_normalize {
  my ($this, $channel) = @_;
  $channel //= 'all';
  return $this->mage->Normalize(channel => $channel);
}

sub filter_oilpaint {
  my ($this, $radius) = @_;
  $radius //= 1;
  return $this->mage->OilPaint(radius => $radius);
}

sub filter_posterize {
  my ($this, $levels) = @_;
  $levels //= 1;
  return $this->mage->Posterize(levels => $levels);
}

sub filter_saturate {
  my ($this, $saturation) = @_;
  $saturation //= 150;
  return $this->mage->Modulate(saturation => $saturation);
}

sub filter_sepia {
  my ($this, $factor) = @_;

  $factor //= "100%";

  my $clone = $this->mage->Clone();

  my $error = $clone->Grayscale();
  $error = $clone->SigmoidalContrast(contrast => 3) unless $error;
  $error = $clone->Tint(fill => "wheat") unless $error; 

  $error = $this->mage->Composite(compose=>'over', image=>$clone, opacity=>$factor) unless $error;
  return $error;
}

sub filter_sharpen {
  my ($this, $radius, $sigma) = @_;

  my %p = ();
  $p{radius} = $radius if defined $radius && $radius ne '';
  $p{sigma} = $sigma if defined $sigma && $sigma ne '';

  return $this->mage->Sharpen(%p);
}

sub filter_tint {
  my ($this, $fill) = @_;
  $fill //= 'wheat';
  return $this->mage->Tint(fill => $fill);
}

sub filter_vignette {
  my ($this, $factor, $color) = @_;

  $factor = 1 if !defined($factor) || $factor eq "" || $factor < 1;
  $color //= "black";

  my $error;
  my ($width, $height) = $this->mage->Get('width', 'height');
  my $vignette = $this->createImage(size=>floor($width * $factor).'x'.floor($height * $factor));
  $error = $vignette->Read("radial-gradient:none-$color");
  $error = $vignette->Crop(geometry=>$width.'x'.$height.'!',gravity=>"Center") unless $error;

  $error = $vignette->Level(levels=>"25x100%") unless $error;
  $error = $this->mage->Composite(compose=>'Multiply', image=>$vignette) unless $error;

  return $error;
}

# instagram look-alike filters
sub filter_1977 {
  my ($this, $factor) = @_;

  my $error;
  $factor //= "100%";

  my $clone = $this->mage->Clone();

  my $layer = $this->mage->Clone();
  $error = $layer->Gamma(gamma => "0.6") unless $error;
  $error = $layer->Level(levels=>"25%,100%") unless $error;
  $error = $layer->Tint(fill => "rgb(243, 106, 188)") unless $error; 

  $error = $clone->ContrastStretch(levels=>"110") unless $error;
  $error = $clone->Modulate(saturation=>"130", brightness=>"110") unless $error;
  $error = $clone->Gamma(gamma => "0.6") unless $error;
  $error = $clone->Level(levels=>"-45%,100%") unless $error;

  $error = $clone->Composite(compose=>"Screen", image =>$layer, opacity=>"90%") unless $error;

  $error = $clone->AutoGamma() unless $error;
  $error = $this->mage->Composite(compose=>'over', image=>$clone, opacity=>$factor) unless $error;

  return $error;
}

sub filter_gotham {
  my ($this, $factor) = @_;

  $factor //= "100%";

  my $error;
  my $clone = $this->mage->Clone();

  $error = $clone->Modulate(saturation=>30);
  $error = $clone->Contrast(2) unless $error;
  $error = $clone->Modulate(brightness => 110) unless $error;
  $error = $clone->Grayscale() unless $error;
  $error = $clone->Tint(fill => "#D3CCBD") unless $error; 

  return $error if $error;

  my ($width, $height) = $clone->Get('width', 'height');

  my $noiseLayer = $this->createImage(size=>$width.'x'.$height);
  $noiseLayer->Read("canvas:black"); 
  $error = $noiseLayer->AddNoise(noise => "Gaussian", attenuate=>5) unless $error;
  $error = $noiseLayer->MotionBlur(radius=>10, sigma=>10, angle=>0) unless $error;
  $error = $noiseLayer->Grayscale();
  $clone->Composite(compose=>"Screen", image=>$noiseLayer, opacity => "30%") unless $error;

  $error = $this->mage->Composite(compose=>'over', image=>$clone, opacity=>$factor) unless $error;

  $error = $this->filter_vignette(3) unless $error;

  return $error;
}

sub filter_inkwell {
  my ($this, $factor) = @_;

  $factor //= "100%";

  my $error;

  my $clone = $this->mage->Clone();

  $error = $clone->Contrast() unless $error;
  $error = $clone->Modulate(brightness => "110") unless $error;
  $error = $clone->Gamma(gamma => "0.8") unless $error;
  $error = $clone->Grayscale() unless $error;

  $error = $this->mage->Composite(compose=>'over', image=>$clone, opacity=>$factor) unless $error;

  $error = $this->filter_vignette(2.5) unless $error;

  return $error;
}

sub filter_kelvin {
  my ($this, $factor) = @_;

  $factor //= "100%";

  my $error;

  my $clone = $this->mage->Clone();

  $error = $clone->SigmoidalContrast(geometry=>"7,40%") unless $error;
  $error = $clone->Level(levels=>"10%,100%", channel=>"RGB") unless $error;
  $error = $clone->Level(levels=>"-63%,100%,1.1", channel=>"Red") unless $error;
  $error = $clone->Level(levels=>"-30%,108%,0.8", channel=>"Green") unless $error;
  $error = $clone->Level(levels=>"-80%,130%,0.9", channel=>"Blue") unless $error;

  $error = $clone->Gamma(0.7) unless $error;
  $error = $clone->Modulate(brightness => "110") unless $error;

  $error = $this->mage->Composite(compose=>'over', image=>$clone, opacity=>$factor) unless $error;

  return $error;
}

sub filter_moon {
  my ($this, $factor) = @_;

  $factor //= "100%";

  my $error;

  my $clone = $this->mage->Clone();

  $error = $clone->Grayscale() unless $error;
  $error = $clone->AutoLevel() unless $error;
  $error = $clone->Level(levels=>"25%,80%,1.5") unless $error;
  $error = $clone->LevelColors('black-point' => '#333338', invert=>1) unless $error;

  $error = $this->mage->Composite(compose=>'over', image=>$clone, opacity=>$factor) unless $error;

  return $error;
}

sub filter_lomo {
  my ($this, $factor) = @_;

  $factor //= '100%';

  my $error;
  my $clone = $this->mage->Clone();

  $error = $clone->Level(levels => "30%", channel => 'Red');
  $error = $clone->Level(levels => "30%", channel => 'Green') unless $error;

  $error = $clone->Level(levels => "-20%,90%") unless $error;
  $error = $this->mage->Composite(compose=>'over', image=>$clone, opacity=>$factor) unless $error;

  $error = $this->filter_vignette(2.5) unless $error;

  return $error;
}

sub filter_nashville {
  my ($this, $factor) = @_;

  $factor //= "100%";

  my $error;
  my $clone = $this->mage->Clone();
  my ($width, $height) = $clone->Get('width', 'height');

  my $layer = $this->createImage(size=>$width.'x'.$height);
  $layer->Read("canvas:#ffdaad"); 
  $error = $clone->Composite(compose=>'Multiply', image=>$layer) unless $error;

  $layer = $this->createImage(size=>$width.'x'.$height);
  $layer->Read("canvas:#004696");
  $error = $clone->Composite(compose=>'lighten', image=>$layer, opacity=>"50%") unless $error;

  $error = $clone->Level(levels=>"-25%,90%,0.7") unless $error;

  $error = $this->mage->Composite(compose=>'over', image=>$clone, opacity=>$factor) unless $error;

  $this->mage->Flatten();

  return $error;
}

sub filter_toaster {
  my ($this, $factor) = @_;

  $factor //= "100%";

  my $error;

  my $clone = $this->mage->Clone();

  $error = $clone->SigmoidalContrast(contrast => "1.5");
  $error = $clone->Modulate(brightness => "90") unless $error;
  $error = $clone->Level(levels=>"-15%,100%,0.8") unless $error;

  my ($width, $height) = $clone->Get('width', 'height');
  my $burner = $this->createImage(size=>floor($width*2.5).'x'.floor($height*2.5));
  $error = $burner->Read("radial-gradient:#F1C47C-#3b003b");
  $error = $burner->Crop(geometry=>$width.'x'.$height.'!',gravity=>"Center") unless $error;

  $error = $clone->Composite(compose=>'Overlay', image=>$burner) unless $error;
  $error = $this->mage->Composite(compose=>'over', image=>$clone, opacity=>$factor) unless $error;

  return $error;
}

sub filter_hudson {
  my ($this, $factor) = @_;

  $factor //= "100%";

  my $error;

  my $clone = $this->mage->Clone();

  $error = $clone->Level(levels=>"-25%,100%", channel=>"RGB") unless $error;
  $error = $clone->Level(levels=>"-25%,100%", channel=>"Red") unless $error;
  $error = $clone->SigmoidalContrast(geometry=>"5,65%", channel=>"Red") unless $error;
  $error = $clone->SigmoidalContrast(geometry=>"5,55%", channel=>"Green") unless $error;
  $error = $clone->SigmoidalContrast(geometry=>"3,45%", channel=>"Blue") unless $error;

  my ($width, $height) = $this->mage->Get('width', 'height');
  my $vignette = $this->createImage(size=>$width.'x'.$height);
  $error = $vignette->Read("radial-gradient:#8099BE-#525162");
  $error = $clone->Composite(compose=>'overlay', image=>$vignette, opacity=>"80%") unless $error;

  $error = $this->mage->Composite(compose=>'over', image=>$clone, opacity=>$factor) unless $error;

  $this->mage->Flatten();

  return $error;
}

1;
