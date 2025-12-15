[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,    
    [Parameter()]
    [string]$HtmlPath = (Join-Path (Get-Location) "memories_history.html"),

    [switch]$ApplyOverlays,
    [switch]$KeepOriginalFiles,
    [switch]$unlock
)

try {
    # --- paths / globals ---
    . "$PSScriptRoot/lib/functions.ps1"

    if ([System.IO.Path]::IsPathRooted($OutputPath)) {
        $Global:sOutputPath = $OutputPath
    } else {
        $Global:sOutputPath = Join-Path (Get-Location) $OutputPath
    }

    $Global:bApplyOverlays = $ApplyOverlays
    $Global:bKeepFiles     = $KeepOriginalFiles
    $Global:sDownloadPath  = if ($bKeepFiles) { Join-Path $sOutputPath "src" } else { Join-Path $env:TEMP "SEM" }
    $Global:sHtmlPath      = (Resolve-Path $HtmlPath -ErrorAction Stop).Path
    $Global:sJsonPath      = Join-Path (Split-Path $sHtmlPath -Parent) "sem.json"
    $Global:sLogPath       = Join-Path (Split-Path $sHtmlPath -Parent) "sem.log"
    $Global:sExivPath      = Join-Path $PSScriptRoot 'lib\exiv2.exe'
    $sSplashPath           = Join-Path $PSScriptRoot 'lib\splash.txt'
    $sLockPath             = Get-SessionLockPath
    Add-Type -Path (Join-Path $PSScriptRoot 'lib\HtmlAgilityPack.dll')

    # --- lock check ---
    if ( -not $unlock -and (Test-Path -Path $sLockPath) ) {
        throw "Operation already performed on selected HTML file. Use -unlock to override."
    }

    # --- output dir ---
    if (-not (Test-Path -LiteralPath $sOutputPath)) {
        New-Item -ItemType Directory -Path $sOutputPath -ErrorAction Stop | Out-Null
    }

    # --- input html ---
    $DOC = New-Object HtmlAgilityPack.HtmlDocument
    $sHtmlContent = Get-Content -LiteralPath $Global:sHtmlPath -Raw
    $DOC.LoadHtml($sHtmlContent)

    $ghostImg = $DOC.DocumentNode.SelectSingleNode("//img[@class='ghost']")
    if (-not $ghostImg) {
        throw  "Input HTML file is not a valid Snapchat Memories export file"
    }

    $ghostSrc = $ghostImg.GetAttributeValue("src", "")
    if (-not $ghostSrc.StartsWith("data:image/svg+xml;base64,PHN2ZyB4")) {
        throw  "Input HTML file is not a valid Snapchat Memories export file"
    }
    
}
catch {
    Log -Context "$Init" -ErrorRecord $_
    exit 1
}

# START
Write-Host
Get-Content   $sSplashPath | Write-Host
Write-Verbose "Input file: $sHtmlPath"
Write-Verbose "Session file: $sJsonPath"
Write-Verbose "Apply overlays: $bApplyOverlays"
Write-Verbose "Keep originals: $bKeepFiles"
Write-Verbose "Output directory: $sOutputPath"
Write-Verbose "::::::::::::::::::::"

Write-Host
Write-Host "Snapchat Memories HTML file loaded successfully."
Write-Host

if (Test-Path $sJsonPath) {
    $Global:arrMemories = Get-Content $sJsonPath -Raw | ConvertFrom-Json
} else {
    $Global:arrMemories = @()
}

if ($Global:arrMemories.Count -gt 0) {
    $nRestarted = 0
    foreach ($memory in $arrMemories) {

        Restart-MemoryObjects $memory
        $nRestarted++
    }

    Write-Host "Session restored from existing JSON file. Downloads restarted: $nRestarted"

} else {

    Test-SemOutputDirectory $sOutputPath

    $htBody = $DOC.DocumentNode.SelectSingleNode("//tbody")
    $htRows = $htBody.SelectNodes("./tr")

    foreach ($htRow in $htRows) {
        $oMemory = Initialize-MemoryObject $htRow
        $arrMemories += $oMemory
        Write-Host "Found memory: $($oMemory.BaseName)"
    } 

    Write-Host "Total memories found: $($arrMemories.Count)"
}

Save-Session

Write-Host
Write-Host "Starting processing of memories..."
Write-Host

$nProcessed = 0
ForEach ($memory in $arrMemories) {
    $nProcessed++

    Write-Host ":::::::::::::::::::::::::::::"
    Write-Host

    Write-Host "Processing memory $nProcessed of $($arrMemories.Count): $($memory.BaseName)"

    if ( $memory.Status -eq 'done' ) {
        if (Test-Path $memory.LocalPath) {
            Write-Host "   Memory already processed. Skipping."
            Write-Host
            continue
        } else {
            Write-Host "   Memory marked as done but file not found. Restarting processing."
            Write-Host
            Restart-MemoryDownload  $memory
        }
    } 

    if ( $memory.Status -eq 'download_pending' ) { 
        Write-Host     "-> Downloading..."

        try {
            Invoke-MemoryDownload $memory
            if ($memory.Status -ne 'download_done') {
                throw  "   Download failed for memory $($memory.BaseName)"
            }
        } catch {
            Log -Memory $memory -Context "$nProcessed`:Download" -ErrorRecord $_
            continue
        }

        Write-Host     "   Downloaded $($memory.Format) file."
    } 
    
    if ( $memory.Status -eq 'download_done' -and $memory.Format -eq 'zip' ) {
        Write-Host     "-> Extracting..."

        try { 
            Invoke-MemoryExtract $memory
            if ($memory.Status -ne 'extract_done') {
                throw  "   Extraction failed for memory $($memory.BaseName)"
            }
        } catch {
            Log -Memory $memory -Context "$nProcessed`:Extraction" -ErrorRecord $_
            continue
        }

        Write-Host     "   Extracted $($memory.Format) file."
    }

    if ( $memory.Status -eq 'extract_done' -and $memory.Format -ne 'zip' ) {
        try {
            if ( $bApplyOverlays ) {
            Write-Host "-> Applying overlays..."    
 
            Invoke-MemoryCompose $memory
            $sMsg = "applied"

        } else {
            Write-Host "-> Skipping overlays..."

            Skip-MemoryCompose $memory
            $sMsg = "skipped"
        }
            if ($memory.Status -ne 'compose_done') {
                throw  "   Overlay application failed for memory $($memory.BaseName)"
            }
        } catch {
            Log -Memory $memory -Context "$nProcessed`:Overlay" -ErrorRecord $_
            continue
        }

        Write-Host     "   Overlays $sMsg."
    }

    if (($memory.Status -eq 'download_done' -and $memory.Format -ne 'zip' ) -or $memory.Status -eq 'compose_done' ) {
        Write-Host     "-> Applying EXIF tags..."

        try {
            Invoke-ApplyExifTags $memory
            if ($memory.Status -ne 'tagging_done') {
                throw  "   EXIF tagging failed for memory $($memory.BaseName)"
            }
        } catch {
            Log -Memory $memory -Context "$nProcessed`:Tagging" -ErrorRecord $_
            continue
        }

        Write-Host     "   EXIF tags applied."
    }

    if ( $memory.Status -eq 'tagging_done' ) {
        Write-Host     "-> Copying to ouput..."

        try {
            Invoke-CopyToOutput $memory
            if ($memory.Status -ne 'output_done') {
                throw  "   Copy to output failed for memory $($memory.BaseName)"
            }
        } catch {
            Log -Memory $memory -Context "$nProcessed`:Copy" -ErrorRecord $_
            continue
        }

        Write-Host     "   Output ready."
    }

    if ( $memory.Status -eq 'output_done' ) {
        Write-Host     "-> Final cleanup..."

        try {
            Invoke-Cleanup $memory
            if ($memory.Status -ne 'done') {
                throw "   Cleanup failed for memory $($memory.BaseName)"
            }
        } catch {
            Log -Memory $memory -Context "$nProcessed`:Cleanup" -ErrorRecord $_
            continue
        }
            
        Write-Host     "   Export finalized."
    }

    Write-Host "Memory processed successfully."
    Write-Host
}   

$arrFailedMemories = @( $arrMemories | Where-Object { $_.Status -ne 'done' } )

Write-Host ":::::::::::::::::::::::::::::"
Write-Host

if ($arrFailedMemories.Count -gt 0) {
    Write-Host "Some memories failed to process: $($arrFailedMemories.Count) out of $($arrMemories.Count)"

    foreach ($memory in $arrFailedMemories) {
        Write-Host " - $($memory.BaseName): Status = $($memory.Status)"
    }

    $Global:arrMemories = $arrFailedMemories
    Save-Session
    
} else {

    Write-Host "All memories processed successfully."

    if (Test-Path -LiteralPath $sJsonPath) {
        Remove-Item -LiteralPath $Global:sJsonPath -Force
    }

    New-Item -ItemType File -Path $sLockPath -Force | Out-Null
}