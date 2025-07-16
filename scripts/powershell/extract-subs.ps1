<#
.SYNOPSIS
Batch Subtitle Extractor - Extracts subtitle streams from video files using ffmpeg.

.DESCRIPTION
Scans video files or directories for subtitle streams and extracts them into separate files based on specified formatting rules.

.PARAMETER Path
One or more input video file paths or directory paths to process.

.PARAMETER Format
Output filename format string. Placeholders: SOURCE (base filename), lang (language code), title (stream title/tag), dispo (disposition i.e. 'default', 'forced').
Default: 'SOURCE.lang.title.dispo' (Jellyfin compatible).

.PARAMETER Suffix
Suffix to append *after* the base filename (SOURCE placeholder) but *before* language/title placeholders in the Format string. Default: ''.

.PARAMETER Recurse
Process folders recursively.

.PARAMETER Force
Force overwrite existing subtitle files.

.PARAMETER FfmpegPath
Path to ffmpeg executable. Auto-detected if not provided.

.PARAMETER FfprobePath
Path to ffprobe executable. Auto-detected if not provided.

.PARAMETER DisableWhereSearch
Disable searching for ffmpeg/ffprobe in PATH using 'where.exe' or 'Get-Command'.

.PARAMETER Concise
Concise output (only progress shown).

.EXAMPLE
.\extract-subs.ps1 -Path "C:\videos\movie.mkv" -Format "SOURCE.lang"

.EXAMPLE
.\extract-subs.ps1 -Path "C:\videos\series_folder" -Recurse -Force -Suffix "_upscaled" -Format "SOURCE.lang.title"

.NOTES
Requires ffmpeg and ffprobe.
The -Suffix parameter is applied to the base filename *before* the -Format placeholders are processed.
For example, with -Suffix "_UHD" and -Format "SOURCE.lang", input "video.mkv" becomes "video_UHD.eng.srt".
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')] # Possible file creation
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
    [string[]]$Path,

    [Parameter()]
    [string]$Format = 'SOURCE.lang.title.dispo',

    [Parameter()]
    [string]$Suffix = '',

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
        $effectiveConfigPath = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\config\$($MyInvocation.MyCommand.Name -replace '\.ps1$', '-config.json')")
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
        # Only warn if a specific path was given but not found
        if (-not [string]::IsNullOrEmpty($ConfigPath)) {
            Write-Warning "Specified configuration file not found at '$ConfigPath'."
        } else {
            Write-Verbose "Default configuration file '$effectiveConfigPath' not found. Using command-line parameters and script defaults."
        }
    }

    # --- Script Status Tracking ---
    $script:fatalErrorOccurred = $false
    $script:anySubtitlesExtracted = $false
    $script:ffmpegFailureCode = $null

    Write-Verbose "Script Root: $PSScriptRoot"

    # --- Helper Function to Find Executables (Copied from glsl-transcode.ps1 for standalone use) ---
    function Find-Executable {
        param(
            [string]$Name,
            [string]$ExplicitPath,
            [switch]$DisableWhere
        )
        Write-Verbose "Searching for $Name..."
        # 1. Explicit Path
        if (-not [string]::IsNullOrEmpty($ExplicitPath)) {
            if (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) {
                Write-Verbose "Using explicit path: $ExplicitPath"
                return (Get-Item -LiteralPath $ExplicitPath).FullName
            } else {
                Write-Warning "Explicit path for $Name not found: $ExplicitPath"
            }
        }

        # 2. Script Directory (Check parent if running from .\scripts)
        $scriptDir = $PSScriptRoot
        $localPath = Join-Path $scriptDir "$Name.exe"
        if (Test-Path -LiteralPath $localPath -PathType Leaf) {
            Write-Verbose "Found $Name in script directory: $localPath"
            return $localPath
        }
        $parentDir = Split-Path -LiteralPath $scriptDir
        $parentLocalPath = Join-Path $parentDir "$Name.exe"
        if (Test-Path -LiteralPath $parentLocalPath -PathType Leaf) {
            Write-Verbose "Found $Name in parent directory: $parentLocalPath"
            return $parentLocalPath
        }


        # 3. PATH (where.exe / Get-Command)
        if (-not $DisableWhere) {
            try {
                $foundPath = (Get-Command $Name -ErrorAction SilentlyContinue).Source
                if ($foundPath) {
                    Write-Verbose "Found $Name via Get-Command: $foundPath"
                    return $foundPath
                } else {
                    Write-Verbose "$Name not found via Get-Command."
                }
            } catch {
                Write-Verbose "Get-Command failed for ${Name}: $($_.Exception.Message)"
            }
            # Fallback for systems where Get-Command might not work as expected for .exe
            try {
                $whereOutput = where.exe $Name 2>&1
                if ($LASTEXITCODE -eq 0 -and $whereOutput) {
                    $foundPath = $whereOutput | Select-Object -First 1
                    Write-Verbose "Found $Name via where.exe: $foundPath"
                    return $foundPath
                } else {
                    Write-Verbose "$Name not found via where.exe."
                }
            } catch {
                Write-Verbose "where.exe failed for ${Name}: $($_.Exception.Message)"
            }
        } else {
            Write-Verbose "Skipping PATH search for $Name due to -DisableWhereSearch."
        }

        Write-Warning "$Name could not be located."
        return $null
    }

    # --- Locate FFMPEG and FFPROBE ---
    $ffmpeg = Find-Executable -Name 'ffmpeg' -ExplicitPath $FfmpegPath -DisableWhere:$DisableWhereSearch
    $ffprobe = Find-Executable -Name 'ffprobe' -ExplicitPath $FfprobePath -DisableWhere:$DisableWhereSearch

    if (-not $ffmpeg) {
        Write-Error "ffmpeg.exe not found. Please provide the path using -FfmpegPath or ensure it's in the script/parent directory or PATH."
        $script:fatalErrorOccurred = $true
        exit 1
    }
    if (-not $ffprobe) {
        Write-Error "ffprobe.exe not found. Please provide the path using -FfprobePath or ensure it's in the script/parent directory or PATH."
        $script:fatalErrorOccurred = $true
        exit 1
    }
    if (-not $Concise) {
        Write-Host "Using FFMPEG: $ffmpeg"
        Write-Host "Using FFPROBE: $ffprobe"
    }

    # --- Subtitle Codec to Extension Mapping ---
    $codecExtensionMap = @{
        'subrip'             = '.srt'
        'srt'                = '.srt'
        'ass'                = '.ass'
        'ssa'                = '.ass'
        'mov_text'           = '.srt' # Often used in MP4
        'webvtt'             = '.vtt'
        'hdmv_pgs_subtitle'  = '.sup' # Blu-ray image format
        'pgs'                = '.sup'
        'dvd_subtitle'       = '.sub' # VobSub image format (often needs .idx too, ffmpeg might handle)
        'dvbsub'             = '.sub' # DVB image format
        # Add more as needed
    }

    # --- Function to Sanitize Filename Component ---
    function Sanitize-FilenamePart {
        param([string]$Text)
        
        if ([string]::IsNullOrWhiteSpace($Text)) { return "unknown" } # Avoid empty parts

        # Basic replacements for common invalid characters
        $sanitized = $Text -replace '[:\\/\?\*"<>|]', '_' `
                           -replace '\s+', ' ' # Replace whitespace sequences with single space
        $sanitized = $sanitized.Trim('_. ')
        $sanitized = $sanitized -replace '_+', '_'
        

        if ([string]::IsNullOrWhiteSpace($sanitized)) { return "sanitized" }

        return $sanitized
    }

    # --- Function to Process a Single File ---
    function Extract-SubtitlesLogic {
        param(
            [Parameter(Mandatory = $true)]
            [System.IO.FileInfo]$FileInput,

            [Parameter()]
            [string]$OutputFormatString = 'SOURCE.lang.title', # Jellyfin compatible format string
            # Placeholders: SOURCE (base filename), lang (language code), title (stream title/tag)

            [Parameter()]
            [string]$OutputSuffix = '', # Suffix applied to base filename

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
            Write-Host "Processing Subtitles for: $inputFileFullPath"
            Write-Host "Format: '$OutputFormatString', Suffix: '$OutputSuffix', Force: $ForceProcessing"
            Write-Host "-----------------------------------------------------`n"
        }

        # --- Get Subtitle Stream Info (Index, Codec, Language, Title) ---
        if (-not $Concise) { Write-Host "Probing subtitle streams..." }
        $subtitleStreams = @()
        try {
            # Use ffprobe to get info in JSON format for easier parsing
            $ffprobeArgs = @(
                '-v', 'error',
                '-select_streams', 's',
                '-show_streams',
                '-show_entries', 'stream=index,codec_name,disposition:stream_tags=language,title',
                '-of', 'json',
                "`"$inputFileFullPath`""
            )
            Write-Verbose "Running: $ffprobe $($ffprobeArgs -join ' ')"
            $jsonOutput = & $ffprobe @ffprobeArgs 2>&1
            $exitCode = $LASTEXITCODE

            if ($exitCode -ne 0) {
                Write-Warning "ffprobe failed to get subtitle info for '$inputFileFullPath' (Exit Code: $exitCode). Maybe no subtitles?"
                # Write-Verbose "ffprobe output: $jsonOutput" # Uncomment for debugging
                return
            }

            if ([string]::IsNullOrWhiteSpace($jsonOutput)) {
                if (-not $Concise) { Write-Host "No subtitle streams found via ffprobe for '$inputFileFullPath'." }
                return
            }

            # Parse the JSON output
            $probeData = $jsonOutput | ConvertFrom-Json -ErrorAction SilentlyContinue
            if (-not $probeData -or -not $probeData.streams) {
                Write-Warning "Could not parse ffprobe JSON output or no streams found for '$inputFileFullPath'."
                Write-Verbose "Raw ffprobe output: $jsonOutput"
                return
            }

            $subtitleStreams = $probeData.streams

        } catch {
            Write-Error "Error running ffprobe for subtitle info on '$inputFileFullPath': $($_.Exception.Message)"
            $script:fatalErrorOccurred = $true # Consider this potentially fatal
            return
        }

        if ($subtitleStreams.Count -eq 0) {
            if (-not $Concise) { Write-Host "No subtitle streams found to extract in '$inputFileFullPath'." }
            return
        }

        if (-not $Concise) { Write-Host "Found $($subtitleStreams.Count) subtitle stream(s)." }

        # --- Prepare ffmpeg arguments for extraction ---
        $ffmpegArgs = @(
            '-v', 'error', # Less verbose for extraction
            '-y', # Overwrite individual subtitle files if -Force is used (ffmpeg handles this per output)
            '-i', "`"$inputFileFullPath`""
        )
        $extractionNeeded = $false

        # --- Process Each Subtitle Stream ---
        foreach ($stream in $subtitleStreams) {
            $subIndex = $stream.index
            $subCodec = $stream.codec_name
            $subLang = if ($stream.tags -and $stream.tags.language -and $stream.tags.language -ne 'und') { $stream.tags.language } else { 'und' }
            $subTitle = if ($stream.tags -and $stream.tags.title) { $stream.tags.title } else { $null }

            $dispoParts = [System.Collections.Generic.List[string]]@()
            if ($OverrideDefault -ge 0) { # Only set the specified stream as default
                if ($stream.index -eq $OverrideDefault) {
                    $dispoParts.Add('default')
                }

                if ($stream.PSObject.Properties.Name -contains 'disposition' -and $stream.disposition.forced -gt 0) {
                    $dispoParts.Add('forced')
                }
            }
            else {
                if ($stream.PSObject.Properties.Name -contains 'disposition') {
                    if ($stream.disposition.default -gt 0) { $dispoParts.Add('default') }
                    if ($stream.disposition.forced -gt 0) { $dispoParts.Add('forced') }
                }
            }
            $subDispo = $dispoParts -join '.'

            if (-not $Concise) {
                Write-Host " Processing Stream Index: $subIndex"
                Write-Host "   Codec: $subCodec"
                Write-Host "   Lang:  $subLang"
                Write-Host "   Title: $(If ($subTitle) {$subTitle} Else {'<none>'})" # Display title or placeholder
                Write-Host "   Dispo: $(If ($subDispo) {$subDispo} Else {'<none>'})"
            }

            # Determine output extension
            $subExt = $null
            if ($codecExtensionMap.ContainsKey($subCodec)) {
                $subExt = $codecExtensionMap[$subCodec]
            } else {
                Write-Warning "  Unknown subtitle codec '$subCodec' for stream index $subIndex. Cannot determine extension. Skipping extraction for this stream."
                continue # Skip to the next stream
            }
            Write-Verbose "  Determined Extension: $subExt"

            # Determine tag for filename (prefer title, fallback to lang if not 'und', fallback to index)
            $subTag = $null
            if (-not [string]::IsNullOrWhiteSpace($subTitle)) {
                $subTag = $subTitle
            } elseif ($subLang -ne 'und') {
                $subTag = $subLang
            } else {
                $subTag = "stream$subIndex"
            }
            $subTagSafe = Sanitize-FilenamePart -Text $subTag
            Write-Verbose "  Using Tag: '$subTag' (Sanitized: '$subTagSafe')"


            # Construct output filename based on format string
            $formattedName = $OutputFormatString

            $baseNameWithSuffix = $inputName + $OutputSuffix
            $formattedName = $formattedName -replace [regex]::Escape('SOURCE'), $baseNameWithSuffix

            if ($formattedName -match [regex]::Escape('title')) {
                if (-not [string]::IsNullOrWhiteSpace($subTagSafe)) {
                    # Use the sanitized tag derived above (which might be title, lang, or index)
                    $formattedName = $formattedName -replace [regex]::Escape('title'), $subTagSafe
                } else {
                    # Remove placeholder and preceding/following dot if title/tag is missing/empty
                    $formattedName = $formattedName -replace '\.?title\.?', '.'
                }
            }

            if ($formattedName -match [regex]::Escape('lang')) {
                if ($subLang -ne 'und') {
                    $formattedName = $formattedName -replace [regex]::Escape('lang'), $subLang
                } else {
                    # Remove placeholder and preceding/following dot if lang is missing/und
                    $formattedName = $formattedName -replace '\.?lang\.?', '.'
                }
            }

            if ($formattedName -match [regex]::Escape('dispo')) {
                if (-not [string]::IsNullOrWhiteSpace($subDispo)) {
                    $formattedName = $formattedName -replace [regex]::Escape('dispo'), $subDispo
                } else {
                    # Remove placeholder and preceding/following dot if dispo is missing
                    $formattedName = $formattedName -replace '\.?dispo\.?', '.'
                }
            }

            # Clean up potential multiple dots, leading/trailing dots
            while ($formattedName -match '\.\.') { $formattedName = $formattedName -replace '\.\.', '.' }
            $formattedName = $formattedName.Trim('.')

            # Final output path
            $subOutputFile = Join-Path $inputPath ($formattedName + $subExt)
            if (-not $Concise) { Write-Host "   Outputting to: `"$subOutputFile`"" }

            # Check if output exists (respect -f flag)
            if (Test-Path -LiteralPath $subOutputFile -PathType Leaf) {
                if (-not $ForceProcessing) {
                    Write-Warning "   Skipping extraction, output file '$subOutputFile' already exists. Use -Force to overwrite."
                    continue
                } elseif (-not $Concise) {
                    Write-Host "   Output file exists, but -Force is enabled. Will overwrite."
                }
            }

            $ffmpegArgs += '-map', "0:$subIndex", '-c', 'copy', "`"$subOutputFile`""
            $extractionNeeded = $true
            Write-Verbose "   Added map args for stream $subIndex."
        }

        # --- Execute FFMPEG if any streams need extraction ---
        if ($extractionNeeded) {
            if (-not $Concise) { Write-Host "Starting ffmpeg extraction command:`n$ffmpeg $($ffmpegArgs -join ' ')" }

            if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Extract Subtitles")) {
                try {
                    Write-Verbose "Running: $ffmpeg $($ffmpegArgs -join ' ')"
                    & $ffmpeg @ffmpegArgs
                    $exitCode = $LASTEXITCODE
                    if (-not $Concise) { Write-Host "" }

                    if ($exitCode -ne 0) {
                        Write-Error "ffmpeg failed to extract subtitles (Exit Code: $exitCode) for '$inputFileFullPath'."
                        $script:fatalErrorOccurred = $true
                        $script:ffmpegFailureCode = $exitCode
                        # Note: ffmpeg might have created some files before failing. Cleanup is complex.
                    } else {
                        if (-not $Concise) { Write-Host "Successfully finished subtitle extraction process for '$inputFileFullPath'." }
                        $script:anySubtitlesExtracted = $true
                    }
                } catch {
                    Write-Error "Error executing ffmpeg for subtitle extraction on '$inputFileFullPath': $($_.Exception.Message)"
                    $script:fatalErrorOccurred = $true
                }
            } else {
                Write-Warning "Skipping subtitle extraction for '$inputFileFullPath' due to -WhatIf."
                $script:anySubtitlesExtracted = $true
            }
        } elseif (-not $Concise) {
            Write-Host "No subtitle streams required extraction (either none found, unsupported, or already exist without -Force)."
        }

    } # End Function Extract-SubtitlesLogic

} # End Begin block

process {
    # Define supported video extensions broadly for finding files
    $videoExtensions = @(".mkv", ".mp4", ".avi", ".mov", ".wmv", ".flv", ".ts", ".webm", ".mpg", ".mpeg") # Add more if needed

    foreach ($itemPath in $Path) {
        Write-Verbose "Processing argument: $itemPath"
        if ($script:fatalErrorOccurred) {
            Write-Warning "A fatal error occurred previously. Stopping further processing."
            break
        }
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
                    Write-Host "Progress: $processedCount / $totalFiles - Extracting subs for '$($file.Name)'"
                    Extract-SubtitlesLogic -FileInput $file `
                                           -OutputFormatString $Format `
                                           -OutputSuffix $Suffix `
                                           -ForceProcessing:$Force `
                                           -OverrideDefault $OverrideDefault
                }
            } elseif ($item -is [System.IO.FileInfo]) {
                # Check if the file extension is in our list (basic check)
                if ($videoExtensions -contains $item.Extension) {
                    Write-Host "Progress: 1 / 1 - Extracting subs for '$($item.Name)'"
                    Extract-SubtitlesLogic -FileInput $item `
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
    if (-not $Concise) { Write-Host "`nSubtitle extraction script finished." }

    # Determine final exit code
    if ($script:fatalErrorOccurred) {
        if ($null -ne $script:ffmpegFailureCode) {
            Write-Verbose "Exiting with ffmpeg failure code: $script:ffmpegFailureCode."
            exit $script:ffmpegFailureCode
        } else {
            Write-Verbose "Exiting with code 1 (Generic Fatal Error)."
            exit 1
        }
    } elseif ($script:anySubtitlesExtracted) {
        Write-Verbose "Exiting with code 0 (Success/Extraction Attempted)."
        exit 0
    } else {
        Write-Verbose "Exiting with code -2 (No Subtitles Extracted/Processed)."
        exit -2 # Use -2 to indicate nothing needed to be done or no matching streams found
    }
} # End End block
