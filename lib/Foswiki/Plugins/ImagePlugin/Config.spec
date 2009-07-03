# ---+ Extensions
# ---++ ImagePlugin
# This is the configuration used by the <b>ImagePlugin</b>.

# **BOOLEAN**
# Turn on/off downloading and mirroring of links to external images, e.g. http://some.external.site/avatar.jpg
$Foswiki::cfg{ImagePlugin}{RenderExternalImageLinks} = 1;

# **BOOLEAN**
# Turn on/off attaching a mirrored image to the current topic. If switched on 
# an attachment-record is generated for this image in addition to
# downloading the image. Attachments will be marked as hidden. Note, that any
# auto-attached image will update the topic and with it its timestamp.
$Foswiki::cfg{ImagePlugin}{AutoAttachExternalImages} = 1;

# **STRING**
# specifies a regular expession matching those urls that shall not be mirrored. They are
# handled by the core engine the standard way instead.
$Foswiki::cfg{ImagePlugin}{Exclude} = 'http://www.google.com';

# **BOOLEAN**
# Turn on/off attaching generated thumbnails to the current topic. 
$Foswiki::cfg{ImagePlugin}{AutoAttachThumbnails} = 0;

# **SELECT Image::Magick,Graphics::Magick**
# Select the image processing backend. Image::Magick and Graphics::Magick are mostly compatible
# as far as they are used here.
$Foswiki::cfg{ImagePlugin}{Impl} = 'Image::Magick';
