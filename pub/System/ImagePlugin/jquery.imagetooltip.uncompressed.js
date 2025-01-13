/*
 * jQuery image tooltip - helper to display an image preview in a tooltip
 *
 * Copyright (c) 2018-2025 Michael Daum http://michaeldaumconsulting.com
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

  $(".jqImageTooltip:not(.inited)").livequery(function() {
    var $this = $(this),
        opts = $.extend({}, defaults, $this.data());

    $this.addClass("inited");

    if (typeof(opts.image) !== 'undefined' && opts.image.match(/\.(avif|jpe?g|gif|png|bmp|svgz?|xcf|psd|tiff?|ico|pdf|psd|ps|mp4|avi|mov|webp|heic|heif)$/i)) { // SMELL: yet another list of webby images
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
          var src, img, params;

          params = {
            "topic": opts.web+"."+opts.topic,
            "file": encodeURIComponent(opts.image),
            "crop": opts.crop,
            "width": opts.width,
            "height": opts.height
          };

          if (/\.svgz?$/.test(opts.image)) {
            params.output = "png";
          }

          src = foswiki.getScriptUrlPath("rest", "ImagePlugin", "process", params);
          img = $("<img/>").attr({
            'src': src
          });

          return img;
        }
      });
    }
  });
});
