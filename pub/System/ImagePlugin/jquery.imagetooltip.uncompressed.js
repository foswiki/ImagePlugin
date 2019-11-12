/*
 * jQuery image tooltip - helper to display an image preview in a tooltip
 *
 * Copyright (c) 2018-2019 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
jQuery(function($) {
  var defaults = {
    width: 300,
    height: 300,
    crop: 'off',
    delay:300,
    track:true,
    showURL:false
  };

  $(".jqImageTooltip:not(.jqInitedImageTooltip)").livequery(function() {
    var $this = $(this),
        opts = $.extend({}, defaults, $this.data(), $this.metadata());

    $this.addClass("jqInitedImageTooltip");

    if (typeof(opts.image) !== 'undefined' && opts.image.match(/\.(jpe?g|gif|png|bmp|svgz?|xcf|psd|tiff?|ico|pdf|psd|ps|mp4|avi|mov|webp)$/i)) { // SMELL: yet another list of webby images
      $this.tooltip({
        show: {
          delay: 350
        },
        track:true,
        tooltipClass:'imageTooltip',
        position: {
          my: "left+15 top+20",
          at: "left bottom",
          collision: "flipfit"
        },
        content: function() {
          var src, img;

          if (/\.svgz?$/.test(opts.image)) {
            src = foswiki.getPubUrlPath(opts.web, opts.topic, opts.image);
            img = $("<img/>").attr({
              'src': src,
              'width': opts.width,
              'height': opts.height
            });
          } else {
            src = foswiki.getScriptUrlPath("rest", "ImagePlugin", "resize", {
                "topic": opts.web+"."+opts.topic,
                "file": opts.image,
                "crop": opts.crop,
                "width": opts.width,
                "height": opts.height
              });
            img = $("<img/>").attr({
              'src': src
            });
          }
          return img;
        }
      });
    }
  });
});
