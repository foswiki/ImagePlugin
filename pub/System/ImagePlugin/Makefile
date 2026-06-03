FOSWIKI_ROOT?=~/foswiki/trunk/core
TARGET= build \
	build/imagetooltip.js \
	build/image.css \
	build/imageEditor.js \
	build/imageEditor.css \

EDITOR_JS=lib/cropper.js src/imageEditor.uncompressed.js
EDITOR_CSS=src/imageEditor.uncompressed.css

-include $(FOSWIKI_ROOT)/pub/System/JQueryPlugin/Makefile.include

.PHONY: clean install

install:
	npm install

clean: 
	rm -f build/* 

build:
	@mkdir build

build/imageEditor.js: $(EDITOR_JS)
	@echo generating $@
	@cat $^ > $@

build/pkg.uncompressed.css: $(EDITOR_CSS) 
	@echo generating $@
	@cat $^ > $@

ifneq (,$(wildcard node_modules))
lib/cropper.js: node_modules/cropperjs/dist/cropper.js
	@echo generating $@
	@cp $^ $@
endif
