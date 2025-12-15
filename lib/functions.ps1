function Save-Session {
    $sTempPath = "$sJsonPath.tmp"
    try {
        $arrMemories |
            Where-Object { $_.Status -ne 'done' } |
            ConvertTo-Json -Depth 3 -ErrorAction Stop |
            Set-Content -LiteralPath $sTempPath -Encoding UTF8 -ErrorAction Stop

        Move-Item -LiteralPath $sTempPath -Destination $sJsonPath -Force -ErrorAction Stop
    }
    catch {
        if (Test-Path $sTempPath) {
            Remove-Item $sTempPath -Force -ErrorAction SilentlyContinue
        }
        Log -Context "Save-Session" -ErrorRecord $_
    }
}

function Log {
    param(
        [Parameter(Mandatory = $true)][string]$Context,
        [PSCustomObject]$Memory,
        [object]$ErrorRecord
    )

    $sTimestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    $sMsg = if ($ErrorRecord.Exception) {
        $ErrorRecord.Exception.Message.Trim()
    } else {
        $ErrorRecord.ToString().Trim()
    }

    $arrDetails = @()

    if ($ErrorRecord) {

        if ($ErrorRecord.FullyQualifiedErrorId) {
            $arrDetails += "ErrorId: $($ErrorRecord.FullyQualifiedErrorId)"
        }

        if ($ErrorRecord.CategoryInfo) {
            $arrDetails += "Category: $($ErrorRecord.CategoryInfo.Category)"
        }

        if ($ErrorRecord.InvocationInfo) {
            $oInvocation = $ErrorRecord.InvocationInfo
            if ($oInvocation.ScriptName) {
                $arrDetails += "At: $($oInvocation.ScriptName):$($oInvocation.ScriptLineNumber)"
            }
            if ($oInvocation.Line) {
                $arrDetails += "Line: $($oInvocation.Line.Trim())"
            }
        }
    }

    if ($Memory) {
        $sPrefix = "[$Context][$($Memory.BaseName)]"
    } else {
        $sPrefix = "[$sTimestamp][$Context]"
    }

    $logEntry = if ($arrDetails.Count -gt 0) {
        "[$sTimestamp]$sPrefix $sMsg`n  " + ($arrDetails -join "`n  ")
    } else {
        "[$sTimestamp]$sPrefix $sMsg"
    }

    Add-Content -LiteralPath $Global:sLogPath -Value $logEntry -Encoding UTF8
    Write-Verbose "$sPrefix $sMsg"

    Write-Host $ErrorRecord.ToString()
    Write-Host
}

function Get-SessionLockPath {

    $sHtml = Get-Content -LiteralPath $Global:sHtmlPath -Raw
    $sPayload = "$sHtml|$bApplyOverlays"

    $SHA   = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($sPayload)
    $token = ($SHA.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''

    $short = $token.Substring(0, 15)
    return Join-Path $env:TEMP "SEM_$short"
}

function Test-SemOutputDirectory ([string]$sOutputPath) {

    $sRegex = '^\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}_(video\.mp4|image\.jpg)$'

    if (-not (Test-Path -LiteralPath $sOutputPath)) { return }

    $oFile = Get-ChildItem -LiteralPath $sOutputPath -File |
        Where-Object { $_.Name -match $sRegex } |
        Select-Object -First 1

    if (-not $oFile) { return }

    if ($oFile.Extension -eq '.mp4') {

        $sMeta = & ffprobe `
            -v error `
            -show_entries format_tags `
            -of default=noprint_wrappers=1:nokey=0 `
            $oFile.FullName 2>$null
    }
    elseif ($oFile.Extension -eq '.jpg') {

        $sMeta = & $sExivPath -p X $oFile.FullName 2>$null
    }

    if ($sMeta -match 'Exported with Snapchat Export Manager') {
        throw "Output directory contains SEM-exported image: $($oFile.Name)"
    }
}

function Initialize-MemoryObject ($htRow) {
    $htCells = $htRow.SelectNodes("./td")
    if (-not $htCells -or $htCells.Count -lt 4) { continue }

    $sTimestamp  = $htCells[0].InnerText.Trim() -replace "\sUTC$", ""
    $dtTimestamp = [datetime]::Parse($sTimestamp)

    [PSCustomObject]$oMemory = @{
        Status    = "download_pending"
        Retries   = 0
        Format    = $null
        LocalPath = $null
        Timestamp = $dtTimestamp
        MediaType = $htCells[1].InnerText.Trim()
    }
    if ($htCells[2].InnerText.Trim() -match "([-+]?\d+\.\d+),\s*([-+]?\d+\.\d+)" -and $matches[1] -ne 0) {
        $oMemory.Latitude  = [double]$matches[1]
        $oMemory.Longitude = [double]$matches[2]                  
    }
    if ($htCells[3].InnerHtml -match "downloadMemories\('([^']+)','?") {
        $oMemory.DownloadUrl = $matches[1]
    }
    $baseName = "{0:yyyy_MM_dd_HH_mm_ss}_{1}" -f $dtTimestamp, ($oMemory.MediaType.ToLower())
    $oMemory.BaseName = $baseName

    return $oMemory
}

function Restart-MemoryObjects ([PSCustomObject]$memory) {

    $sDownloadPath = $Global:sDownloadPath
    $sBaseName     = $memory.BaseName
    $sLocalPath    = $memory.LocalPath
    $sStatus       = $memory.Status
    $sExt          = $memory.Format

    if ($sStatus -eq 'download_inprogress') {

        if ($sLocalPath -and (Test-Path -LiteralPath $sLocalPath)) {
            Remove-Item -LiteralPath $sLocalPath -Force -ErrorAction SilentlyContinue
        }

        Restart-MemoryDownload $memory
        $nRestarted++
        return
    }

    if ($sStatus -eq 'download_failed') {

        Restart-MemoryDownload $memory
        $nRestarted++
        return
    }

    if ($sStatus -eq 'extract_inprogress') {

        $sZipPath = Join-Path $sDownloadPath "$sBaseName.zip"
        if (Test-Path $sZipPath) {
            Remove-Item -LiteralPath $sZipPath -Force -ErrorAction SilentlyContinue
        }

        Restart-MemoryDownload $memory
        $nRestarted++
        return
    }

    if (($sStatus -eq 'compose_inprogress') -or ($sStatus -eq 'compose_skipping')) {

        if ($sLocalPath -and (Test-Path -LiteralPath $sLocalPath)) {
            Remove-Item -LiteralPath $sLocalPath -Force -ErrorAction SilentlyContinue
        }

        $memory.LocalPath = $null
        $memory.Status = 'extract_done'
        Save-Session
        return
    }

    if ($sStatus -eq 'tagging_inprogress') {

        if ($memory.Format -eq 'mp4') {
            $sTempPath  = Join-Path $sDownloadPath "$sBaseName`_tmp.$sExt"

            if ($sExt -and (Test-Path -LiteralPath $sTempPath)) {
                Remove-Item -LiteralPath $sTempPath -Force -ErrorAction SilentlyContinue 
            }
        }

        $memory.Status = 'compose_done'
        Save-Session
        return
    }

    if ($sStatus -eq 'output_inprogress') {

        if ($sLocalPath -and (Test-Path -LiteralPath $sLocalPath)) {
            Remove-Item -LiteralPath $sLocalPath -Force -ErrorAction SilentlyContinue
        }

        $memory.Status = 'tagging_done'
        $memory.LocalPath = Join-Path $sDownloadPath "$sBaseName.$sExt"
        Save-Session
        return
    }

    if ($sStatus -eq 'cleanup_inprogress') {

        Invoke-Cleanup $memory
        if ($memory.Status -ne 'done') {
            $memory.Status = 'done'
        }
        Save-Session
        return
    }

    $arrAllowedStatus = @(
        'download_pending',
        'extract_done',
        'compose_done',
        'tagging_done',
        'download_done',
        'output_done',
        'done'
    )

    if ($sStatus -notin $arrAllowedStatus) {
        throw "Unrecognized memory status '$sStatus' for memory $($memory.BaseName)"
    }
    
}

function Invoke-MemoryDownload ([PSCustomObject]$memory, [int]$nMaxAttempts = 3) {
    $memory.Status = 'download_inprogress'
    Save-Session

    $sDownloadPath = $Global:sDownloadPath
    $sFileName     = "$($memory.BaseName).tmp"

    if (-not (Test-Path $sDownloadPath)) {
        try {
            $null = New-Item -ItemType Directory -Path $sDownloadPath -Force -ErrorAction Stop
        } catch {
            throw "Unable to create download directory '$sDownloadPath'"
        }
    }

    $sLocalPath = Join-Path $sDownloadPath $sFileName

    if(Get-ChildItem "$($sLocalPath.Substring(0, $sLocalPath.Length - 4)).*") { 
        Write-Host "File '$($memory.BaseName)' already exists. Skipping download."
        
        $memory.Status = 'download_done'
        Save-Session
        return 
    }

    $memory.LocalPath = $sLocalPath

    for ($nRetry = $memory.Retries + 1; $nRetry -le $nMaxAttempts; $nRetry++) {
        $memory.Retries = $nRetry
        Save-Session

        try {
            $response = Invoke-WebRequest -Uri $memory.DownloadUrl -OutFile $sLocalPath -UseBasicParsing -PassThru -ErrorAction Stop

            $memory.Format = Get-FileExtension -response $response
            if ($memory.Format -eq 'unknown') {
                throw "Unrecognized content type for memory download."
            }

            $memory.Status = 'download_done'
            Save-Session
            break
        }
        catch {
            $memory.Status = 'download_failed'
            Save-Session

            if (Test-Path $sLocalPath) { Remove-Item $sLocalPath -Force -ErrorAction SilentlyContinue }

            if ($nRetry -ge $nMaxAttempts) {
                throw "Maximum download attempts reached for memory $($memory.BaseName)"
            }

            Write-Verbose "Retrying download for $($memory.BaseName) (attempt $nRetry of $nMaxAttempts)"
            continue
        }
    }

    $sLocalPath = $memory.LocalPath -replace 'tmp$', $memory.Format
    try {
        Rename-Item -Path $memory.LocalPath -NewName $sLocalPath -Force -ErrorAction Stop
    } catch {
        throw "Failed to finalize download for memory $($memory.BaseName)"
    }

    $memory.LocalPath = $sLocalPath

    Save-Session
}

function Invoke-MemoryExtract ([PSCustomObject]$memory) {
    $memory.Status = "extract_inprogress"
    Save-Session

    $sDownloadPath = $Global:sDownloadPath
    $sZipPath      = $memory.LocalPath
    $sBaseName     = $memory.BaseName

    Get-ChildItem -LiteralPath $sDownloadPath -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "(-main\.jpg|-main\.mp4|-overlay\.png)"  } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }

    try {
        Expand-Archive -Path $sZipPath -DestinationPath $sDownloadPath -Force -ErrorAction Stop
    } catch {
        throw "Failed to extract archive for memory $($memory.BaseName)"
    }

    $arrFiles = Get-ChildItem -Path $sDownloadPath -File | Where-Object {
        $_.Name -like "*-main.*" -or
        $_.Name -like "*-overlay.png"
    }

    if ($arrFiles.Count -eq 2) {
        Remove-Item -LiteralPath $sZipPath -Force
    } else {
        throw "Unexpected number of files extracted from '$sZipPath'."
    }

    foreach ($file in $arrFiles) {

        if ($file.Name -match ".*-main\.(.+)$") {
            $sExt             = $matches[1]
            $memory.Format    = $sExt
            $memory.LocalPath = Join-Path $sDownloadPath "$sBaseName.$sExt"

            $sFileName        = "$sBaseName`_original.$sExt"
        } else {
            $sFileName        = "$sBaseName`_overlay.png" 
        }

        try {
            Rename-Item -LiteralPath $file.FullName -NewName $sFileName -Force -ErrorAction Stop
        } catch {
            throw "Failed to organize extracted files for memory $($memory.BaseName)"
        }
    }

    $memory.Status = 'extract_done'
    Save-Session
}

function Invoke-MemoryCompose ([PSCustomObject]$memory) {
    $memory.Status = "compose_inprogress"
    Save-Session

    $sDownloadPath = $Global:sDownloadPath
    $sBaseName     = $memory.BaseName
    $sExt          = $memory.Format

    $sOverlayPath  = Join-Path $sDownloadPath "$sBaseName`_overlay.png"
    $sOriginalPath = Join-Path $sDownloadPath "$sBaseName`_original.$sExt"
    $sFinalPath    = Join-Path $sDownloadPath "$sBaseName.$sExt"

    if (!(Test-Path $sOverlayPath)) {
        $memory.Status = "extract_inprogress"
        Save-Session # on retry will clean up and download again
        throw "No overlay found for image '$sOriginalPath'"
    }

    try {
        switch($memory.MediaType) {
            'Image' {
                $sWidth = (& magick identify -format "%w" $sOriginalPath).Trim()
                $sHeight = (& magick identify -format "%h" $sOriginalPath).Trim()
                & magick `
                    $sOriginalPath `
                    $sOverlayPath `
                    -resize "${sWidth}x${sHeight}!" `
                    -compose over `
                    -composite `
                    $sFinalPath
            }
            'Video' { 
                $sFilter = "[1:v][0:v]scale2ref=w=iw:h=ih[ovr][base];[base][ovr]overlay=0:0"
                & ffmpeg `
                    -y `
                    -loglevel error `
                    -hide_banner `
                    -i $sOriginalPath `
                    -i $sOverlayPath `
                    -filter_complex $sFilter `
                    -c:a copy `
                    $sFinalPath
            }
        }
    } catch {
        throw "Failed to compose overlay for memory $($memory.BaseName)"
    } if ( $LASTEXITCODE -ne 0 ) {
        throw "Overlay composition failed with exit code $LASTEXITCODE."
    }

    if ($memory.LocalPath -ne $sFinalPath) { $memory.LocalPath = $sFinalPath }

    if (-not $Global:bKeepFiles) {
        try {
            Remove-Item -LiteralPath $sOverlayPath -Force -ErrorAction Stop
            Remove-Item -LiteralPath $sOriginalPath -Force -ErrorAction Stop
        } catch {
            throw "Failed to clean up intermediate files for memory $($memory.BaseName)"
        }
    }

    $memory.Status = "compose_done"
    Save-Session
}

function Skip-MemoryCompose ([PSCustomObject]$memory) {
    $memory.Status = "compose_skipping"
    Save-Session

    $sDownloadPath = $Global:sDownloadPath
    $sBaseName     = $memory.BaseName
    $sExt          = $memory.Format

    $sOriginalPath = Join-Path $sDownloadPath "$sBaseName`_original.$sExt"
    $sFinalPath    = Join-Path $sDownloadPath "$sBaseName.$sExt"

    try {
        Copy-Item -LiteralPath $sOriginalPath -Destination $sFinalPath -Force -ErrorAction Stop
    } catch {
        throw "Failed to copy original file for memory $($memory.BaseName)"
    }

    $memory.LocalPath = $sFinalPath
    $memory.Status    = "compose_done"
    Save-Session
}

function Invoke-ApplyExifTags ([PSCustomObject]$memory) {
    $memory.Status = "tagging_inprogress"
    Save-Session

    $sExivPath     = $Global:sExivPath
    $sDownloadPath = $Global:sDownloadPath

    $sBaseName     = $memory.BaseName
    $sLocalPath    = $memory.LocalPath
    $sExt          = $memory.Format
    $sLat          = $memory.Latitude
    $sLon          = $memory.Longitude


    $sLatAbs       = [math]::Abs($sLat)
    $sLonAbs       = [math]::Abs($sLon)
    $dmsLat        = Convert-ToDms -fValue $sLatAbs
    $dmsLon        = Convert-ToDms -fValue $sLonAbs
    $arrLatRef     = if ($sLat -ge 0) { @("N", "+") } else { @("S", "-") }
    $arrLonRef     = if ($sLon -ge 0) { @("E", "+") } else { @("W", "-") }

    try {
        switch ($sExt) {
            'jpg' {
                $sTimestamp  = $memory.Timestamp.ToString("yyyy:MM:dd HH:mm:ss")

                & $sExivPath `
                    -M"set Exif.Photo.DateTimeOriginal $sTimestamp" `
                    -M"set Exif.Photo.DateTimeDigitized $sTimestamp" `
                    -M"set Exif.Image.Software Snapchat" `
                    -M"set Exif.Image.DateTime $sTimestamp" `
                    -M"set Exif.GPSInfo.GPSLatitude $dmsLat" `
                    -M"set Exif.GPSInfo.GPSLongitude $dmsLon" `
                    -M"set Exif.GPSInfo.GPSLatitudeRef $($arrLatRef[0])" `
                    -M"set Exif.GPSInfo.GPSLongitudeRef $($arrLonRef[0])" `
                    -M"set Xmp.xmp.CreatorTool Snapchat Export Manager" `
                    -M"set Xmp.dc.source Snapchat" `
                    $sLocalPath
            }
            'mp4' {
                $sTempPath  = Join-Path $sDownloadPath "$sBaseName`_tmp.$sExt"
                $sTimestamp = $memory.Timestamp.ToString("yyyy-MM-ddTHH:mm:ssZ")
                $sLocation  = "{0}{1}{2}{3}/" -f $arrLatRef[1], $sLatAbs, $arrLonRef[1], $sLonAbs

                & ffmpeg `
                    -y `
                    -loglevel error `
                    -hide_banner `
                    -i $sLocalPath `
                    -metadata "creation_time=$sTimestamp" `
                    -metadata "location=$sLocation" `
                    -metadata "comment=Source: Snapchat" `
                    -metadata "description=Exported with Snapchat Export Manager" `
                    -codec copy `
                    $sTempPath

                if ($LASTEXITCODE -eq 0) {
                    Move-Item -Force -LiteralPath $sTempPath -Destination $sLocalPath -ErrorAction Stop
                }
            }
        }
    } catch {
        throw "Failed to apply metadata for memory $($memory.BaseName)"
    } if ($LASTEXITCODE -ne 0) {
        throw "Exif tagging returned exit code $LASTEXITCODE."
    }

    $memory.Status = "tagging_done"
    Save-Session
}

function Invoke-CopyToOutput ([PSCustomObject]$memory) {
    $memory.Status    = "output_inprogress"
    Save-Session

    $bApplyOverlays = $Global:bApplyOverlays
    $sOutputPath    = $Global:sOutputPath

    $sLocalPath     = $memory.LocalPath
    $sBaseName      = $memory.BaseName
    $sExt           = $memory.Format
    $sFinalPath     = Join-Path $sOutputPath "$sBaseName.$sExt"

    try {
        Copy-Item -Path $sLocalPath -Destination $sFinalPath -Force -ErrorAction Stop
    } catch {
        throw "Failed to copy memory $($memory.BaseName) to output"
    }

    $memory.LocalPath = $sFinalPath
    $memory.Status    = "output_done"
    Save-Session
}

function Invoke-Cleanup ([PSCustomObject]$memory) {
    $memory.Status    = "cleanup_inprogress"
    Save-Session

    $sDownloadPath  = $Global:sDownloadPath
    $bKeepFiles     = $Global:bKeepFiles
    
    $sExt           = $memory.Format
    $sBaseName      = $memory.BaseName

    $sSrcPath      = Join-Path $sDownloadPath "$sBaseName.$sExt"
    $sOriginalPath = Join-Path $sDownloadPath "$sBaseName`_original.$sExt"
    $sOverlayPath  = Join-Path $sDownloadPath "$sBaseName`_overlay.png"

    try {
        if (Test-Path $sSrcPath) {
            Remove-Item -Path $sSrcPath -Force -ErrorAction Stop
        }

        if ($bApplyOverlays) {
            if (Test-Path $sOverlayPath)  { Remove-Item -Path $sOverlayPath -Force -ErrorAction Stop }
        } else {
            if (Test-Path $sOriginalPath) { Remove-Item -Path $sOriginalPath -Force -ErrorAction Stop }
        }

        $memory.Status = "done"
        Save-Session
    } catch {
        throw "Failed to clean up temporary files for memory $($memory.BaseName)"
    }
}

function Restart-MemoryDownload ([PSCustomObject]$memory) {
    $memory.Status  = "download_pending"
    $memory.Retries = 0
    $memory.Format  = $null
    $memory.LocalPath = $null
    Save-Session
}

function Get-FileExtension {
    param($response)

    $sType = $response.Headers.'Content-Type'

    switch ($sType) {
        'image/jpg'          { return 'jpg' }
        'video/mp4'          { return 'mp4' }
        'application/zip'    { return 'zip' }
        default              { return 'unknown' }
    }
}

function Convert-ToDms {
    param ([double]$fValue)

    $nDeg = [math]::Floor($fValue)
    $fMin = ($fValue - $nDeg) * 60
    $nMin = [math]::Floor($fMin)
    $nSec = ($fMin - $nMin) * 60

    "{0}/1 {1}/1 {2}/1" -f $nDeg, $nMin, [math]::Round($nSec)
}