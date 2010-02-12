jQuery(function($){var defaults={delay:300,track:true,showURL:false};if(!$.browser.msie){$(".jqImageTooltip:not(.jqInitedImageTooltip)").livequery(function(){var $this=$(this);var opts=$.extend({},defaults,$this.metadata());$this.addClass("jqInitedImageTooltip");if(opts.image.match(/jpe?g|gif|png|bmp/i)){$this.tooltip({delay:350,track:true,showURL:false,bodyHandler:function(){var src=foswiki.scriptUrlPath+"/rest/ImagePlugin/resize?"+
"topic="+opts.web+"."+opts.topic+";"+
"file="+opts.image+";"+
"width="+(opts.width||300)+";"+
"height="+(opts.height||300);var img=$("<img/>").attr('src',src);return $("<div class='imgTooltip'></div>").append(img);}});}});}});;
