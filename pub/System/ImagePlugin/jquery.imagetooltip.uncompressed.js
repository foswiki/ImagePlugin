/* helper to display an image preview in a tooltip */
"use strict";
jQuery(function($) {
  var defaults = {
    delay:300,
    track:true,
    showURL:false
  };
  $(".jqImageTooltip:not(.jqInitedImageTooltip)").livequery(function() {
    var $this = $(this),
        opts = $.extend({}, defaults, $this.data(), $this.metadata());

    $this.addClass("jqInitedImageTooltip");

    if (typeof(opts.image) !== 'undefined' && opts.image.match(/\.(jpe?g|gif|png|bmp|svgz?|xcf|psd|tiff?|ico|pdf|psd|ps|mp4|avi|mov)$/i)) { // SMELL: yet another list of webby images
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
          var src = foswiki.getPreference("SCRIPTURLPATH")+"/rest/ImagePlugin/resize?"+
            "topic="+opts.web+"."+opts.topic+";"+
            "file="+opts.image+";"+
            "crop="+(opts.crop||'off')+";"+
            "width="+(opts.width||300)+";"+
            "height="+(opts.height||300),
            img = $("<img/>").attr('src', src);
          return img;
        }
      });
    }
  });
});
