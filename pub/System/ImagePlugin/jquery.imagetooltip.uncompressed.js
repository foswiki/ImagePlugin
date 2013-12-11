/* helper to display an image preview in a tooltip */
jQuery(function($) {
  var defaults = {
    delay:300,
    track:true,
    showURL:false
  };
  $(".jqImageTooltip:not(.jqInitedImageTooltip)").livequery(function() {
    var $this = $(this),
        opts = $.extend({}, defaults, $this.metadata());

    $this.addClass("jqInitedImageTooltip");

    if (typeof(opts.image) !== 'undefined' && opts.image.match(/jpe?g|gif|png|bmp|svg/i)) {
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
