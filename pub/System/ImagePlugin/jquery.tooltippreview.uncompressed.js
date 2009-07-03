/* helper to display an image preview in a tooltip */
(function($) {
$(function() {
  $(".imageAddTooltip").each(function() {
    var src = $(this).attr('href') || $(this).attr('src') || $(this).find("img").attr('src');
    if (src.match(/jpe?g|gif|png|bmp/i)) {
      var data = $(this).metadata();
      $(this).tooltip({
        delay:350,
        track:true,
        showURL:false,
        bodyHandler: function() { 
          src = foswiki.scriptUrl+"/rest/ImagePlugin/resize?"+
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
});
}(jQuery));

