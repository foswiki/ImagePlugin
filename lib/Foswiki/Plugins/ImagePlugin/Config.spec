# ---+ Extensions
# ---++ ImagePlugin
# This is the configuration used by the <b>ImagePlugin</b>.

# **BOOLEAN LABEL="Download External Images" **
# Turn on/off downloading and mirroring of links to external images, e.g. http://some.external.site/avatar.jpg
$Foswiki::cfg{ImagePlugin}{DownloadExternalImages} = 0;

# **BOOLEAN LABEL="Render External Image Links" DISPLAY_IF="{ImagePlugin}{DownloadExternalImages}" **
# Display external image links such as http://some.external.site/avatar.jpg 
$Foswiki::cfg{ImagePlugin}{RenderExternalImageLinks} = 0;

# **BOOLEAN LABEL="AutoAttach External Images" DISPLAY_IF="{ImagePlugin}{DownloadExternalImages}"**
# Turn on/off attaching a mirrored image to the current topic. If switched on 
# an attachment-record is generated for this image in addition to
# downloading the image. Attachments will be marked as hidden. Note, that any
# auto-attached image will update the topic and with it its timestamp.
$Foswiki::cfg{ImagePlugin}{AutoAttachExternalImages} = 1;

# **STRING LABEL="Include In Mirror" DISPLAY_IF="{ImagePlugin}{DownloadExternalImages}" CHECK="undefok emptyok"**
# regular expession whitelist of image urls allowed to be downloaded
$Foswiki::cfg{ImagePlugin}{Include} = '^none$';

# **STRING LABEL="Exclude From Mirror" DISPLAY_IF="{ImagePlugin}{DownloadExternalImages}" CHECK="undefok emptyok"**
# regular expession blacklist of forbidden image urls 
$Foswiki::cfg{ImagePlugin}{Exclude} = '^https?://(www\.google\.com)';

# **BOOLEAN LABEL="Render Local Images"**
# Activate this flag to process HTML <code>img</code> markup to local images
$Foswiki::cfg{ImagePlugin}{RenderLocalImages} = 0;

# **BOOLEAN LABEL="Secure Inline SVGs"**
# filters inline SVG images and disables any active elements for security reasons
$Foswiki::cfg{ImagePlugin}{SecureInlineSVGs} = 1;

# **BOOLEAN LABEL="AutoAttach Inline Images"**
# Turn on/off automatic extraction of inline image from a topic while being saved and 
# converting them into a proper attachment. This will affect elements such as
# <code>&ltimg src="data:image/jpeg;base64,..." &gt;</code> which will be replaced by 
# appropriate image markup configurable in {InlineImageTemplate}. Note that converting
# inline image data to proper attachments has got a lot of advantages, for one editing
# a topic text in raw format is much more convenient and performant. Keep this under
# consideration when disabling this flag.
$Foswiki::cfg{ImagePlugin}{AutoAttachInlineImages} = 1;

# **STRING LABEL="Inline Image Template" DISPLAY_IF="{ImagePlugin}{AutoAttachInlineImages}"**
# Template to be used when automatically extracting inline images. See {AutoAttachInlineImages}.
$Foswiki::cfg{ImagePlugin}{InlineImageTemplate} = "<img %BEFORE% src='%PUBURLPATH%/%WEB%/%TOPIC%/%ATTACHMENT%' %AFTER% />";

# **BOOLEAN LABEL="Auto-Orient"**
# automatically detect image orientation when querying its geometry. Caution: this could come with an extra performance penalty.
$Foswiki::cfg{ImagePlugin}{AutoOrient} = 0;

1;
