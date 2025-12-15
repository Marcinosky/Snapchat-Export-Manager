# WARNING - WIP
Tested on my data and script works E2E, pickup works from my random testing, i intend to build a proper test suite before releasing to winget. 

## Snapchat-Export-Manager
Snapchat sends your memories in a .html file with information about your memories with individual links for every single one of them. For some users with their media count going over 30k thats simply unfeasable to handle by the included javascript downloader, and that still leaves you with raw images, videos and overlays, that actually have no means of identification or even indexing.

SEM lets you download and process your Snapchat Memories so that they're ready to use and share out-the-box.

The script mangages download with retries, extraction, composition and EXIF tagging to result in properly formatted media that can be imported into your iTunes/Google gallery.

### Capabilities
- Auto detects memories listed in the snapchat files
- Manages safe download, with mid session pick-up from every point
- Combines the original image/video with the with the actual text, stickers, etc.
- Lets you save the unedited original image next to the snapchat memory
- Also lets you save just the original and overlay separately
- Applies the provided GPS and timestamp data into proper EXIF tags

### Prerequsites
You first need to actually [request your memory export from snapchat](https://help.snapchat.com/hc/en-gb/articles/7012305371156-How-do-I-download-my-data-from-Snapchat) and wait for them to come back with your data. They send you an email with a link to where you can find an archive to download. Said archive should contain a `memories_history.html` file, that is the only needed input for SEM

## Use

Basic invocation

 >.\SEM.ps1 `<OutputDirectory>` `<MemoriesHtmlPath>` `[options]`

Required arguments

- `OutputDirectory`
Target directory where processed media will be written
- `MemoriesHtmlPath`
Path to the Snapchat memories_history.html export file

Optional switches

- `-ApplyOverlays`
Applies text and sticker overlays to images and videos

- `-KeepOriginalFiles`
Prevents cleanup if you want to apply overlays but wish to keep the original media

- `-Unlock`
Lets rerun script with same arguments after complete export

Example

>.\SEM.ps1 C:\SEM\OUT "C:\SEM\memories_history.html" -ApplyOverlays -KeepOriginalFiles

### Session handling and resume

A session file (sem.json) is created alongside the input html, and is used to pick up the session where it left off. The script performs cleaning of unfinished artifacts, and if needed download the memory again, then resumes processing. On a succesful run a lock file is created in TEMP to prevent subsequent runs with the same parameters, it can be bypassed by the -unlock argument and will resolve after reboot. 

### Failure and retry behavior

If processing fails for a memory, its skipped and will be retried when the command is run again. Each fail is logged to a file (sem.log) alongside the input html. The script should in theory download the zip again, but i haven't had the chance to test it properly. In doubt download manually, fixes planned.

#### Notes

ffmpeg and ImageMagick must be available in PATH.  
Large exports may take more time depending on media size and enabled options.  
The tool is designed to be restart-safe; rerunning it is expected.

## Dependencies 

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
