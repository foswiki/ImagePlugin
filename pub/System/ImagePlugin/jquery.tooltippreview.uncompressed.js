/* helper to display an image preview in a tooltip */
(function($) {
$(function() {
  if (!$.browser.msie) { /* IE6 and IE7 are too buggy for this feature */
    $(".imageAddTooltip").each(function() {
      var data = $(this).metadata();
      var src = data.image;
      if (src.match(/jpe?g|gif|png|bmp/i)) {
        $(this).tooltip({
          delay:350,
          track:true,
          showURL:false,
          bodyHandler: function() { 
            src = foswiki.scriptUrlPath+"/rest/ImagePlugin/resize?"+
              "topic="+data.web+"."+data.topic+";"+
              "file="+data.image+";"+
              "width="+(data.width||300)+";"+
              "height="+(data.height||300);
            var img = $("<img/>").attr('src', src);
            return $("<div class='imgTooltip'></div>").append(img);
          }
        });
      }
    });
  }
});
}(jQuery));

