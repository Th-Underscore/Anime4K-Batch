<#
.SYNOPSIS
Batch Track Extractor - Extracts audio or subtitle streams from video files using ffmpeg.

.DESCRIPTION
Scans video files or directories for streams and extracts them into separate files based on specified formatting rules.

.PARAMETER Path
One or more input video file paths or directory paths to process.

.PARAMETER Type
The type of track to extract. Options: 'Subtitle', 'Audio'. Default: 'Subtitle'.

.PARAMETER Format
Output filename format string. Placeholders: SOURCE (base filename), lang (language code), title (stream title/tag), dispo (disposition i.e. 'default', 'forced').
Default: 'SOURCE.lang.title.dispo' (Jellyfin compatible).

.PARAMETER Suffix
Suffix to append *after* the base filename (SOURCE placeholder) but *before* language/title placeholders in the Format string. Default: ''.

.PARAMETER StreamInfoB64
Optional: Base64 encoded JSON string containing ffprobe output for the file.
If provided, the script skips running ffprobe itself to improve performance when called from a parent script.

.PARAMETER Recurse
Process folders recursively.

.PARAMETER Force
Force overwrite existing extracted files.

.PARAMETER FfmpegPath
Path to ffmpeg executable. Auto-detected if not provided.

.PARAMETER FfprobePath
Path to ffprobe executable. Auto-detected if not provided.

.PARAMETER DisableWhereSearch
Disable searching for ffmpeg/ffprobe in PATH using 'where.exe' or 'Get-Command'.

.PARAMETER Concise
Concise output (only progress shown).

.PARAMETER OverrideDefault
Forces the stream with this index to be marked as default in the filename generation.

.EXAMPLE
.\extract-tracks.ps1 -Path "C:\videos\movie.mkv" -Type "Subtitle" -Format "SOURCE.lang"

.EXAMPLE
.\extract-tracks.ps1 -Path "C:\videos\series_folder" -Type "Subtitle" -Recurse -Force -Suffix "_upscaled" -Format "SOURCE.lang.title.dispo"

.NOTES
Requires ffmpeg and ffprobe.
The -Suffix parameter is applied to the base filename *before* the -Format placeholders are processed.
For example, with -Suffix "_UHD" and -Format "SOURCE.lang", input "video.mkv" becomes "video_UHD.eng.srt".
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')] # Possible file creation
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
    [string[]]$Path,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Subtitle', 'Audio')]
    [string]$Type = 'Subtitle',

    [Parameter()]
    [string]$Format = 'SOURCE.lang.title.dispo',

    [Parameter()]
    [string]$Suffix = '',

    [Parameter()]
    [string]$StreamInfoB64 = '',

    [Parameter()]
    [switch]$Recurse,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [string]$FfmpegPath = '',

    [Parameter()]
    [string]$FfprobePath = '',

    [Parameter()]
    [switch]$DisableWhereSearch,

    [Parameter()]
    [switch]$Concise,

    [Parameter()]
    [string]$ConfigPath = '',

    [Parameter()]
    [int]$OverrideDefault = -1
)

begin {
    # --- Load Configuration from JSON ---
    $config = $null
    $effectiveConfigPath = $ConfigPath
    if ([string]::IsNullOrEmpty($effectiveConfigPath)) {
        # Default to config file named after script in the same directory
        $configType = if ($Type -eq 'Audio') { 'audio' } else { 'subs' }
        $effectiveConfigPath = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\config\extract-$configType-config.json")
        Write-Verbose "No -ConfigPath specified, attempting default: $effectiveConfigPath"
    }

    if (Test-Path -LiteralPath $effectiveConfigPath -PathType Leaf) {
        Write-Verbose "Loading configuration from: $effectiveConfigPath"
        try {
            $jsonContent = (Get-Content -LiteralPath $effectiveConfigPath -Raw) -replace '//.*'
            $config = $jsonContent | ConvertFrom-Json -ErrorAction Stop
            Write-Verbose "Configuration loaded successfully."

            # --- Override Parameters/Preferences with Config Values (if not set via command line) ---
            foreach ($key in $config.PSObject.Properties.Name) {
                $paramValue = $config.$key
                $keyLower = $key.ToLowerInvariant()

                # Handle Common Parameters explicitly
                if ($keyLower -eq 'verbose') {
                    if ($PSBoundParameters.ContainsKey('Verbose') -eq $false) {
                        if ($paramValue -is [bool] -and $paramValue) {
                            $VerbosePreference = 'Continue'
                            Write-Verbose "Setting `$VerbosePreference = 'Continue' based on config."
                        } else {
                            # Optionally set to SilentlyContinue if explicitly false, otherwise default is usually fine
                            # $VerbosePreference = 'SilentlyContinue'
                        }
                    } else { Write-Verbose "Parameter -Verbose was provided via command line, ignoring config value." }
                } elseif ($keyLower -eq 'debug') {
                    if ($PSBoundParameters.ContainsKey('Debug') -eq $false) {
                        if ($paramValue -is [bool] -and $paramValue) {
                            $DebugPreference = 'Continue'
                            Write-Verbose "Setting `$DebugPreference = 'Continue' based on config."
                        } else {
                            # $DebugPreference = 'SilentlyContinue'
                        }
                    } else { Write-Verbose "Parameter -Debug was provided via command line, ignoring config value." }
                }
                # Handle Regular Parameters
                elseif ($PSBoundParameters.ContainsKey($key) -eq $false -and $MyInvocation.MyCommand.Parameters.ContainsKey($key)) {
                    Write-Verbose "Overriding `$$key with value from config: '$paramValue'"
                    Set-Variable -Name $key -Value $paramValue -Scope Script
                } elseif ($PSBoundParameters.ContainsKey($key)) {
                    Write-Verbose "Parameter `$$key was provided via command line, ignoring config value."
                }
            }

        } catch {
            Write-Warning "Failed to load or parse configuration file '$effectiveConfigPath': $($_.Exception.Message)"
        }
    } else {
        if (-not [string]::IsNullOrEmpty($ConfigPath)) {
            Write-Warning "Specified configuration file not found at '$ConfigPath'."
        } else {
            Write-Verbose "Default configuration file '$effectiveConfigPath' not found. Using command-line parameters and script defaults."
        }
    }

    # --- Script Status Tracking ---
    $script:fatalErrorOccurred = $false
    $script:anyTracksExtracted = $false
    $script:ffmpegFailureCode = $null

    Write-Verbose "Script Root: $PSScriptRoot"

    # --- Helper Function to Find Executables ---
    function Find-Executable {
        param(
            [string]$Name,
            [string]$ExplicitPath,
            [switch]$DisableWhere
        )
        Write-Verbose "Searching for $Name..."
        if (-not [string]::IsNullOrEmpty($ExplicitPath)) {
            if (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) {
                Write-Verbose "Using explicit path: $ExplicitPath"
                return (Get-Item -LiteralPath $ExplicitPath).FullName
            }
        }
        $scriptDir = $PSScriptRoot
        $localPath = Join-Path $scriptDir "$Name.exe"
        if (Test-Path -LiteralPath $localPath -PathType Leaf) { return $localPath }

        if (-not $DisableWhere) {
            try { return (Get-Command $Name -ErrorAction SilentlyContinue).Source } catch {}
            try {
                $whereOutput = where.exe $Name 2>&1
                if ($LASTEXITCODE -eq 0) { return ($whereOutput | Select-Object -First 1) }
            } catch {}
        }
        return $null
    }

    # --- Locate FFMPEG and FFPROBE ---
    $ffmpeg = Find-Executable -Name 'ffmpeg' -ExplicitPath $FfmpegPath -DisableWhere:$DisableWhereSearch
    $ffprobe = Find-Executable -Name 'ffprobe' -ExplicitPath $FfprobePath -DisableWhere:$DisableWhereSearch

    if (-not $ffmpeg) { Write-Error "ffmpeg.exe not found."
        $script:fatalErrorOccurred = $true
        exit 1 }

    # We only error on missing ffprobe if we weren't passed base64 data
    if (-not $ffprobe -and [string]::IsNullOrEmpty($StreamInfoB64)) { Write-Error "ffprobe.exe not found and no stream info provided."
        $script:fatalErrorOccurred = $true
        exit 1 }

    if (-not $Concise) {
        Write-Host "Using FFMPEG: $ffmpeg"
        if ($ffprobe) { Write-Host "Using FFPROBE: $ffprobe" }
    }

    # --- Codec to Extension Mapping ---
    $codecExtensionMap = @{
        # Subtitles
        'subrip'='srt'; 'srt'='srt'
        'ass'='ass'; 'ssa'='ass'
        'mov_text'='srt'

        'webvtt'='vtt'
        'hdmv_pgs_subtitle'='sup'; 'pgs'='sup'
        'dvd_subtitle'='sub'; 'dvbsub'='sub'

        # Audio
        'aac'='aac'
        'ac3'='ac3'
        'eac3'='eac3'
        'flac'='flac'
        'mp3'='mp3'

        'opus'='opus'
        'vorbis'='ogg'
        'dts'='dts'
        'truehd'='thd'
        'pcm_s16le'='wav'; 'pcm_s24le'='wav'
    }

    # --- Function to Sanitize Filename Component ---
    function Sanitize-FilenamePart {
        param([string]$Text)
        if ([string]::IsNullOrWhiteSpace($Text)) { return "unknown" }
        $sanitized = $Text -replace '[:\\/\?\*"<>|]', '_' -replace '\s+', ' '
        $sanitized = $sanitized.Trim('_. ') -replace '_+', '_'
        if ([string]::IsNullOrWhiteSpace($sanitized)) { return "sanitized" }
        return $sanitized
    }

    # --- Function to Process a Single File ---
    function Extract-TracksLogic {
        param(
            [Parameter(Mandatory = $true)]
            [System.IO.FileInfo]$FileInput,
            [Parameter()]
            [string]$OutputFormatString = 'SOURCE.lang.title.dispo', # Jellyfin compatible format string
            # Placeholders: SOURCE (base filename), lang (language code), title (stream title/tag), dispo (disposition i.e. 'default', 'forced')
            [Parameter()]
            [string]$OutputSuffix = '',
            [Parameter()]
            [switch]$ForceProcessing,
            [Parameter()]
            [int]$OverrideDefault = -1
        )

        $inputFileFullPath = $FileInput.FullName
        $inputPath = $FileInput.DirectoryName
        $inputName = $FileInput.BaseName

        if (-not $Concise) {
            Write-Host "`n-----------------------------------------------------"
            Write-Host "Processing $Type extraction for: $inputFileFullPath"
            Write-Host "Format: '$OutputFormatString', Suffix: '$OutputSuffix', Force: $ForceProcessing"
            Write-Host "-----------------------------------------------------`n"
        }

        # --- Get Stream Info ---
        $streams = @()
        try {
            $probeData = $null

            # Check if Base64 data was provided
            if (-not [string]::IsNullOrEmpty($StreamInfoB64)) {
                Write-Verbose "Using provided Base64 stream info."
                try {
                    $jsonBytes = [Convert]::FromBase64String($StreamInfoB64)
                    $jsonStr = [Text.Encoding]::UTF8.GetString($jsonBytes)
                    $probeData = $jsonStr | ConvertFrom-Json
                } catch {
                    Write-Warning "Failed to decode provided stream info. Falling back to local ffprobe."
                }
            }

            # If no data yet, run ffprobe locally
            if ($null -eq $probeData) {
                if (-not $Concise) { Write-Host "Probing streams..." }
                $ffprobeArgs = @('-v', 'fatal', '-show_streams', '-print_format', 'json', "$inputFileFullPath")
                Write-Verbose "Running: $ffprobe $($ffprobeArgs -join ' ')"
                $jsonOutput = & $ffprobe @ffprobeArgs 2>&1
                if ($LASTEXITCODE -ne 0) { Write-Warning "ffprobe failed (Exit Code: $LASTEXITCODE)."; return }
                $probeData = $jsonOutput | ConvertFrom-Json
            }

            if (-not $probeData -or -not $probeData.streams) { return }

            # Filter for requested type
            $targetCodecType = if ($Type -eq 'Audio') { 'audio' } else { 'subtitle' }
            $streams = $probeData.streams | Where-Object { $_.codec_type -eq $targetCodecType }

        } catch {
            Write-Error "Error parsing stream info: $($_.Exception.Message)"
            $script:fatalErrorOccurred = $true
            return
        }

        if ($streams.Count -eq 0) {
            if (-not $Concise) { Write-Host "No $Type streams found in '$inputFileFullPath'. Skipping." }
            return
        }

        if (-not $Concise) { Write-Host "Found $($streams.Count) $Type stream(s)." }

        # --- Prepare ffmpeg arguments for extraction ---
        $ffmpegArgs = @('-y', '-stats')
        if ($Concise) { $ffmpegArgs += '-v', 'fatal' } else { $ffmpegArgs += '-v', 'warning' }
        $ffmpegArgs += '-i', "$inputFileFullPath"

        $extractionNeeded = $false

        # --- Process Each Stream ---
        foreach ($stream in $streams) {
            $idx = $stream.index
            $codec = $stream.codec_name
            $lang = if ($stream.tags -and $stream.tags.language -and $stream.tags.language -ne 'und') { $stream.tags.language } else { 'und' }
            $title = if ($stream.tags -and $stream.tags.title) { $stream.tags.title } else { $null }

            # Disposition Logic
            $dispoParts = [System.Collections.Generic.List[string]]@()
            if ($OverrideDefault -ge 0) {
                if ($stream.index -eq $OverrideDefault) { $dispoParts.Add('default') }
                if ($stream.PSObject.Properties.Name -contains 'disposition' -and $stream.disposition.forced -gt 0) { $dispoParts.Add('forced') }
            } else {
                if ($stream.PSObject.Properties.Name -contains 'disposition') {
                    if ($stream.disposition.default -gt 0) { $dispoParts.Add('default') }
                    if ($stream.disposition.forced -gt 0) { $dispoParts.Add('forced') }
                }
            }
            $dispo = $dispoParts -join '.'

            if (-not $Concise) { Write-Host " Processing Stream Index: $idx [$($title -or '<none>')] ($codec, $lang) ($($dispo -or '<none>'))" }

            # Determine extension
            $ext = $null
            if ($codecExtensionMap.ContainsKey($codec)) { $ext = "." + $codecExtensionMap[$codec] }
            else {
                Write-Warning "  Unknown codec '$codec' for stream $idx. Skipping."
                continue
            }

            # Determine tag (Title -> Lang -> Index)
            $tag = if ($title) { $title } elseif ($lang -ne 'und') { $lang } else { "track$idx" }
            $safeTag = Sanitize-FilenamePart -Text $tag

            # Construct Filename
            $formattedName = $OutputFormatString
            $baseNameWithSuffix = $inputName + $OutputSuffix
            $formattedName = $formattedName -replace [regex]::Escape('SOURCE'), $baseNameWithSuffix

            if ($formattedName -match [regex]::Escape('title')) {
                if ($safeTag) { $formattedName = $formattedName -replace [regex]::Escape('title'), $safeTag }
                else { $formattedName = $formattedName -replace '\.?title\.?', '.' }
            }
            if ($formattedName -match [regex]::Escape('lang')) {
                if ($lang -ne 'und') { $formattedName = $formattedName -replace [regex]::Escape('lang'), $lang }
                else { $formattedName = $formattedName -replace '\.?lang\.?', '.' }
            }
            if ($formattedName -match [regex]::Escape('dispo')) {
                if ($dispo) { $formattedName = $formattedName -replace [regex]::Escape('dispo'), $dispo }
                else { $formattedName = $formattedName -replace '\.?dispo\.?', '.' }
            }

            while ($formattedName -match '\.\.') { $formattedName = $formattedName -replace '\.\.', '.' }
            $formattedName = $formattedName.Trim('.')

            $outputFile = Join-Path $inputPath ($formattedName + $ext)

            if (Test-Path -LiteralPath $outputFile -PathType Leaf) {
                if (-not $ForceProcessing) {
                    Write-Warning "   Output file exists. Use -Force to overwrite."
                    continue
                }
            }

            $ffmpegArgs += '-map', "0:$idx", '-c', 'copy', "$outputFile"
            $extractionNeeded = $true
        }

        # --- Execute FFMPEG ---
        if ($extractionNeeded) {
            if (-not $Concise) { Write-Host "Starting ffmpeg extraction..." }

            if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Extract $Type Tracks")) {
                try {
                    Write-Verbose "Running: $ffmpeg $($ffmpegArgs -join ' ')"
                    & $ffmpeg @ffmpegArgs
                    $exitCode = $LASTEXITCODE
                    if (-not $Concise) { Write-Host "" }

                    if ($exitCode -ne 0) {
                        Write-Error "ffmpeg failed (Exit Code: $exitCode)."
                        $script:fatalErrorOccurred = $true
                        $script:ffmpegFailureCode = $exitCode
                        # TODO: Cleanup
                    } else {
                        if (-not $Concise) { Write-Host "Successfully extracted." }
                        $script:anyTracksExtracted = $true
                    }
                } catch {
                    Write-Error "Error executing ffmpeg: $($_.Exception.Message)"
                    $script:fatalErrorOccurred = $true
                }
            } else {
                $script:anyTracksExtracted = $true
            }
        } elseif (-not $Concise) {
            Write-Host "No subtitle streams required extraction (either none found, unsupported, or already exist without -Force)."
        }

    } # End Function Extract-TracksLogic

} # End Begin block

process {
    $videoExtensions = @(".mkv", ".mp4", ".avi", ".mov", ".wmv", ".flv", ".ts", ".webm", ".mpg", ".mpeg") # Add more if needed

    foreach ($itemPath in $Path) {
        Write-Verbose "Processing argument: $itemPath"
        if ($script:fatalErrorOccurred) { Write-Warning "A fatal error occurred previously. Stopping further processing."; break }
        try {
            $item = Get-Item -LiteralPath $itemPath -ErrorAction Stop
            if ($item -is [System.IO.DirectoryInfo]) {
                if (-not $Concise) { Write-Host "`nProcessing directory: $($item.FullName) (Recursive: $Recurse)" }
                $filesToProcess = Get-ChildItem -LiteralPath $item.FullName -Recurse:$Recurse | Where-Object { $videoExtensions -contains $_.Extension }
                $totalFiles = $filesToProcess.Count
                $processedCount = 0

                if ($totalFiles -eq 0) {
                    if (-not $Concise) { Write-Host "No supported video files found in '$($item.FullName)'." }
                    continue
                }
                if (-not $Concise) { Write-Host "Found $totalFiles video file(s) to process." }

                foreach ($file in $filesToProcess) {
                    $processedCount++
                    Write-Host "Progress: $processedCount / $totalFiles - Extracting tracks for '$($file.Name)'"
                    Extract-TracksLogic -FileInput $file `
                                        -OutputFormatString $Format `
                                        -OutputSuffix $Suffix `
                                        -ForceProcessing:$Force `
                                        -OverrideDefault $OverrideDefault
                }
            } elseif ($item -is [System.IO.FileInfo]) {
                if ($videoExtensions -contains $item.Extension) {
                    Extract-TracksLogic -FileInput $item `
                                           -OutputFormatString $Format `
                                           -OutputSuffix $Suffix `
                                           -ForceProcessing:$Force `
                                           -OverrideDefault $OverrideDefault
                } else {
                    Write-Warning "Skipping file '$($item.FullName)' as its extension '$($item.Extension)' is not in the recognized list of video formats."
                }
            } else {
                Write-Warning "Path '$itemPath' is not a file or directory. Skipping."
            }
        } catch {
            Write-Error "Error processing path '$itemPath': $($_.Exception.Message)"
            $script:fatalErrorOccurred = $true
        }
    }
} # End Process block

end {
    if (-not $Concise) { Write-Host "`nTrack extraction script finished." }

    # Determine final exit code
    if ($script:fatalErrorOccurred) {
        if ($null -ne $script:ffmpegFailureCode) {
            Write-Verbose "Exiting with ffmpeg failure code: $script:ffmpegFailureCode."
            exit $script:ffmpegFailureCode
        } else {
            Write-Verbose "Exiting with code 1 (Generic Fatal Error)."
            exit 1
        }
    } elseif ($script:anyTracksExtracted) {
        Write-Verbose "Exiting with code 0 (Success/Extraction Attempted)."
        exit 0
    } else {
        Write-Verbose "Exiting with code -2 (No Subtitles Extracted/Processed)."
        exit -2 # Use -2 to indicate nothing needed to be done or no matching streams found
    }
} # End End block
