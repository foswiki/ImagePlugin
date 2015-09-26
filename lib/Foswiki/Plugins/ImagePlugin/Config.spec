# ---+ Extensions
# ---++ ImagePlugin
# This is the configuration used by the <b>ImagePlugin</b>.

# **BOOLEAN**
# Turn on/off downloading and mirroring of links to external images, e.g. http://some.external.site/avatar.jpg
$Foswiki::cfg{ImagePlugin}{RenderExternalImageLinks} = 1;

# **BOOLEAN**
# Activate this flag to process HTML <code>img</code> markup to local images
$Foswiki::cfg{ImagePlugin}{RenderLocalImages} = 1;

# **BOOLEAN**
# Activate this flag to convert inline-svg to png
$Foswiki::cfg{ImagePlugin}{ConvertInlineSVG} = 0;

# **BOOLEAN**
# Turn on/off attaching a mirrored image to the current topic. If switched on 
# an attachment-record is generated for this image in addition to
# downloading the image. Attachments will be marked as hidden. Note, that any
# auto-attached image will update the topic and with it its timestamp.
$Foswiki::cfg{ImagePlugin}{AutoAttachExternalImages} = 1;

# **BOOLEAN**
# Turn on/off automatic extraction of inline image from a topic while being saved and 
# converting them into a proper attachment. This will affect elements such as
# <code>&ltimg src="data:image/jpeg;base64,..." &gt;</code> which will be replaced by 
# appropriate image markup configurable in {InlineImageTemplate}. Note that converting
# inline image data to proper attachments has got a lot of advantages, for one editing
# a topic text in raw format is much more convenient and performant. Keep this under
# consideration when disabling this flag.
$Foswiki::cfg{ImagePlugin}{AutoAttachInlineImages} = 1;

# **STRING**
# Template to be used when automatically extracting inline images. See {AutoAttachInlineImages}.
$Foswiki::cfg{ImagePlugin}{InlineImageTemplate} = "<img %BEFORE% src='%PUBURLPATH%/%WEB%/%TOPIC%/%ATTACHMENT%' %AFTER% />";

# **SELECT none,X-Sendfile,X-LIGHTTPD-send-file,X-Accel-Redirect**
# Enable efficient delivery of resized images 
# using the xsendfile feature available in apache, nginx and lighttpd.
# Use <ul>
# <li>X-Sendfile for Apache2 </li>
# <li>X-LIGHTTPD-send-file for Lighttpd<l/i>
# <li>X-Accel-Redirect for Nginx</li>
# </ul>
# Note that you will need to configure your http server accordingly.
# If you installed <a href="http://foswiki.org/Extensions/XSendFileContrib">XSendFileContrib</a> as well, its {XSendFileContrib}{Header}
# will be used instead of this one here.
$Foswiki::cfg{ImagePlugin}{XSendFileHeader} = 'none';

# **STRING**
# specifies a regular expession matching those urls that shall not be mirrored. They are
# handled by the core engine the standard way instead.
$Foswiki::cfg{ImagePlugin}{Exclude} = 'http://www.google.com';

# **SELECT Image::Magick,Graphics::Magick**
# Select the image processing backend. Image::Magick and Graphics::Magick are mostly compatible
# as far as they are used here.
$Foswiki::cfg{ImagePlugin}{Impl} = 'Image::Magick';

1;
