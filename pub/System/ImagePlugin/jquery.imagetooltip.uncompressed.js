/* helper to display an image preview in a tooltip */
jQuery(function($) {
  var defaults = {
    delay:300,
    track:true,
    showURL:false
  };
  $(".jqImageTooltip:not(.jqInitedImageTooltip)").livequery(function() {
    var $this = $(this);
    var opts = $.extend({}, defaults, $this.metadata());
    $this.addClass("jqInitedImageTooltip");
    if (opts.image.match(/jpe?g|gif|png|bmp|svg/i)) {
      $this.tooltip({
        delay:350,
        track:true,
        showURL:false,
        bodyHandler: function() { 
          var src = foswiki.getPreference("SCRIPTURLPATH")+"/rest/ImagePlugin/resize?"+
            "topic="+opts.web+"."+opts.topic+";"+
            "file="+opts.image+";"+
            "crop="+(opts.crop||'off')+";"+
            "width="+(opts.width||300)+";"+
            "height="+(opts.height||300);
          var img = $("<img/>").attr('src', src);
          return $("<div class='imgTooltip'></div>").append(img);
        }
      });
    }
  });
});
