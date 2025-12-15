# Snapchat-Export-Manager
SEM lets you download and process your Snapchat Memories so that they're ready to use and share out-the-box.

The format its returned in is pretty raw, they give you a .html file that contains some information about the Memory and a download link. The embedded downloader is pretty bad in on itself, and when you download you find a bare image/video, or an archive with the overlay (text, stickers) in a separate .png image. 

The script mangages download with retries, extraction, composition and EXIF tagging to result in properly formatted media that can be imported into your iTunes/Google gallery.

# Prerequsites
You first need to actually [request your memory export from snapchat](https://help.snapchat.com/hc/en-gb/articles/7012305371156-How-do-I-download-my-data-from-Snapchat) and wait for them to come back with your data. They send you an email with a link to where you can find an archive to download. Said archive should contain a `memories_history.html` file, that is the only needed input for SEM

# Capabilities
- Auto detects memories listed in the snapchat files
- Manages safe download, with mid session pick-up from every point
- Lets you apply overlays automatically (optional)
- Lets you save raw data from the process (optional)
  - keeps overlay when only original image/video saved
  - keeps unmodified original when overlay applied
- Applies the provided GPS and timestamp data into proper EXIF tags

# Dependencies 

Snapchat Export Manager relies on the following third-party tools and libraries:

- **ffmpeg**  
  Used for video processing and metadata read/write.  
  Installed separately by the user*  
  License: GPL  
  https://ffmpeg.org/

- **ImageMagick**  
  Used for image composition and resizing.  
  Installed separately by the user*  
  License: Apache License 2.0  
  https://imagemagick.org/ 

  *winget recommended

- **exiv2**  
  Used for reading and writing EXIF/XMP metadata in images.  
  Bundled binary distribution.  
  - Version: `0.28.7` (MSVC 2022, x64)  
  - Source: https://github.com/Exiv2/exiv2/releases/tag/v0.28.7
  - SHA: `2e5978b2f53eed1c557e5b5dd5c22d8b44348f5ec8183dab05d25398259c2274`
  - License: GPLv2+ (see `NOTICE.md`) 

  Full license text included in `LICENSE-GPLv2.txt`.  
  https://exiv2.org/

- **HtmlAgilityPack**  
  HTML parsing library used to process Snapchat export files.  
  Bundled  
  - Version: `1.12.4`  
  - Source: https://github.com/zzzprojects/html-agility-pack/releases/tag/v1.12.4  
  - License: MIT  

  https://html-agility-pack.net/