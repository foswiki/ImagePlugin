/*
 * Copyright (c) 2026 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL licenses http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function($) {
  var defaults = {
    initCenter: "none",
    initSelection: {
      width: null,
      height: null,
    },
    selectionDynamic: false,
    selectionOutlined: false,
  };

  var ext2Mime = {
    'jpeg': 'image/jpeg',
    'jpg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/png',
    'avif': 'image/avif',
    'tiff': 'image/tiff',
    'webp': 'image/webp',
  };

  // import Cropper
  Cropper = Cropper.default;

  // The actual plugin constructor
  function ImageEditor(elem, opts) {
    var self = this;

    self.elem = $(elem);
    self.opts = $.extend({}, defaults, self.elem.data(), opts);

    const style = document.createElement("style");
    document.head.appendChild(style);

    self.opts.container = self.opts.container || self.elem[0];
    self.id = self.elem.attr("id");

    if (!self.id) {
      self.id = "cropper_".foswiki.getUniqueID();
      self.elem.attr("id", self.id);
    }

    if (self.opts.height) {
      style.sheet.insertRule(
        `#${self.id} cropper-canvas {
          height:${self.opts.height};
        }`,  style.sheet.cssRules.length
      );
    }

    if (self.opts.width) {
      style.sheet.insertRule(
        `#${self.id} cropper-canvas {
          width:${self.opts.width};
        }`,  style.sheet.cssRules.length
      );
    }

    self.img = new Image();
    self.img.src = self.opts.src || self.elem.src;
    self.cropper = new Cropper(self.img, self.opts);

    self.selection().dynamic = self.opts.selectionDynamic;
    self.selection().zoomable = self.opts.selectionDynamic;
    self.selection().outlined = self.opts.selectionOutlined;

    /*
    self.elem.find("cropper-image").on("transform", function(ev) {
      const scaleH = ev.detail.matrix[0];
      const scaleV = ev.detail.matrix[3];
      const canvasRect = self.canvas().getBoundingClientRect();

      if (scaleH > 1 || 
          scaleV > 1 || 
          self.img.naturalWidth * scaleV > (canvasRect.width + 50) || 
          self.img.naturalHeight * scaleH > (canvasRect.height + 50) 
        ) {
        //console.log("blocking transform");
        ev.preventDefault();
        return false;
      }
    });*/

    self.image().$ready(function() {
      self._initialTransform = self.image().$getTransform();

      $(self.opts.cropperWidthInput).on("change", function() {
        var val = parseInt($(this).val(), 10), 
            sel = self.selection();
        self.selection().$change(sel.x, sel.y, val, sel.height);
      });

      $(self.opts.cropperHeightInput).on("change", function() {
        var val = parseInt($(this).val(), 10), 
            sel = self.selection();
        self.selection().$change(sel.x, sel.y, sel.width, val);
      });

      if (self.opts.initCenter === "none") {
        self.image().$resetTransform();
        self.image().$center("none");
      } else {
        self.image().$center(self.opts.initCenter);
      }

      self.init();
    });

    self.selection().addEventListener("change", function(ev) {
      const sel = ev.detail;

      $(self.opts.cropperWidthInput).each(function() {
        $(this).val(sel.width);
      });
      $(self.opts.cropperHeightInput).each(function() {
        $(this).val(sel.height);
      });
    });


    self.handle().addEventListener("dblclick", function() {
      this.action = this.action === 'move' ? 'select' : 'move';
    });
  };

  // get the CropperImage
  ImageEditor.prototype.image = function() {
    return this.cropper.getCropperImage();
  };

  // get the CropperCanvas
  ImageEditor.prototype.canvas = function() {
    return this.cropper.getCropperCanvas();
  };

  // get the CropperSelection
  ImageEditor.prototype.selection = function() {
    return this.cropper.getCropperSelection();
  };

  ImageEditor.prototype.shade = function() {
    var self = this;
    // return this.cropper.getShade() ... n/a

    return self.elem.find("cropper-shade")[0];
  };

  ImageEditor.prototype.handle = function() {
    var self = this;
    // return this.cropper.getShade() ... n/a

    return self.elem.find("cropper-handle")[0];
  };

  ImageEditor.prototype.init = function() {
    var self = this;

    self.image().$setTransform(self._initialTransform); // SMELL: without, rotation won't reset
    self.image().$resetTransform();
    self.image().$center(self.opts.initCenter);

    const canvasRect = self.canvas().getBoundingClientRect();
    const imageRect = self.image().getBoundingClientRect();

    self.selection().x = 0;
    self.selection().y = 0;
    self.selection().width = self.opts.initSelection.width || Math.min(imageRect.width, canvasRect.width);
    self.selection().height = self.opts.initSelection.height || Math.min(imageRect.height, canvasRect.height);
    self.selection().$center();
  };

  ImageEditor.prototype.preview = function(opts) {
    var self = this;

    self.selection().$toCanvas().then(function(canvas) {
      const base64String = canvas.toDataURL();
      if (opts.display) {
        $(opts.display).css("background-image", "url("+base64String+")");
      }
    });
  };

  ImageEditor.prototype.save = function(opts) {
    var self = this;

    self.selection().$toCanvas().then(function(canvas) {
      var fileName, ext, mimeType, quality;

      const id = foswiki.getUniqueID();

      if (opts.fileName) {
        fileName = opts.fileName;
        ext = fileName.replace(/^.*\./, "");
        mimeType = ext2Mime[ext] || 'image/png';
      } else {
        fileName = id + ".png";
        mimeType = 'image/png';
      }

      if (/jpeg|webp/.test(mimeType)) {
        quality = 0.75;
      } else if (/avif/.test(mimeType)) {
        quality = 0.5;
      }

      canvas.toBlob(function(blob) {
        if (!blob) {
          console.error('Failed to create blob');
          return;
        }

        const file = new File([blob], fileName, { type: mimeType, lastModified: Date.now() });

        self.elem.find("[name=filepath]").remove();
        const $fileUpload = $("<input />")
          .addClass("foswikiHidden")
          .attr("type", "file")
          .attr("name", "filepath")
          .attr("id", id);

        $fileUpload.prependTo(self.elem);

        var dt = new DataTransfer();
        dt.items.add(file);
        $fileUpload[0].files = dt.files;

        self.elem.find("[name=filecomment]").remove();
        $("<input />")
          .addClass("foswikiHidden")
          .attr("type", "hidden")
          .attr("name", "filecomment")
          .val(opts.fileComment)
          .prependTo(self.elem);

        self.elem.submit();
      }, mimeType, quality);

    });
  };

  // register to jQuery
  $.fn.imageEditor = function (opts) {
    return this.each(function () {
      if (!$.data(this, "imageEditor")) {
        $.data(this, "imageEditor", new ImageEditor(this, opts));
      }
    });
  };

  // image editor widget
  $(function() {
    $(".imageEditor").livequery(function() {
      $(this).imageEditor();
    });
  });

  // save dialog
  $(document).on("click", ".imageEditorSaveButton", function() {
    var $dialog = $(this).parents(".ui-dialog:first"),
      opts = $dialog.find(".foswikiFormSteps").data(),
      editor = $(opts.imageEditor).data("imageEditor"),
      fileName = $dialog.find("[name=filename]").val(),
      fileComment = $dialog.find("[name=filecomment]").val();

    opts.fileName = fileName;
    opts.fileComment = fileComment;

    editor.save(opts);
    return false;
  });

  // image cropper buttons
  $(document).on("click", ".imageEditorButton", function(ev) {
    var opts = $(this).data(),
      editor = $(opts.imageEditor).data("imageEditor");

    switch(opts.action) {
        case "zoom-in":
          editor.image().$zoom(0.05);
          break;
        case "zoom-out":
          editor.image().$zoom(-0.05);
          break;
        case "rotate-left":
          editor.image().$rotate("-90deg");
          break;
        case "rotate-right":
          editor.image().$rotate("90deg");
          break;
        case "flip-vertical":
          editor.image().$scale(1, -1);
          break;
        case "flip-horizontal":
          editor.image().$scale(-1, 1);
          break;
        case "reset":
          editor.init();
          break;
        case "save":
          editor.save(opts);
          break;
        case "preview":
          editor.preview(opts);
          break;
        default:
          console.error("unknown editor action ",opts.action);
    }
    ev.preventDefault();
    return false;
  });

})(jQuery);

