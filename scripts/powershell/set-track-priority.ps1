<#
.SYNOPSIS
Batch Default Track Setter - Sets the default audio or subtitle track in video files based on priority.

.DESCRIPTION
Scans video files or directories for audio or subtitle streams, identifies the preferred language based on a priority list,
and remuxes the file (copying all streams) to set the chosen track as the default.

.PARAMETER Path
One or more input video file paths or directory paths to process.

.PARAMETER Type
The type of track to prioritize. Options: 'Audio', 'Subtitle'. Default: 'Audio'.

.PARAMETER Lang
Comma-separated language priority list (3-letter ISO 639-2 codes, e.g., "jpn,eng,kor"). Case-insensitive.
Default for Audio: 'jpn,chi,kor,eng'. Default for Subtitle: 'eng,jpn'.

.PARAMETER Title
Comma-separated title priority list (regex patterns, e.g., "Full,Signs"). Case-insensitive.
Used as a tie-breaker for language matches, or as a primary selector if no language matches are found.

.PARAMETER Suffix
Suffix for the output filename when not using -Replace. Default: '_reordered'. Ignored if -Replace is used.

.PARAMETER StreamInfoB64
Optional: Base64 encoded JSON string containing ffprobe output for the file.
If provided, the script skips running ffprobe itself to improve performance when called from a parent script.

.PARAMETER Recurse
Process folders recursively.

.PARAMETER Force
Force overwrite existing output files (when not using -Replace). Also forces processing even if the target file exists during the -Replace operation's temporary phase.

.PARAMETER Delete
Delete original file after successful processing. Mutually exclusive with -Replace.

.PARAMETER Replace
Replace the original file with the processed version. Mutually exclusive with -Delete. Creates a temporary file during processing.

.PARAMETER FfmpegPath
Path to ffmpeg executable. Auto-detected if not provided.

.PARAMETER FfprobePath
Path to ffprobe executable. Auto-detected if not provided.

.PARAMETER DisableWhereSearch
Disable searching for ffmpeg/ffprobe in PATH using 'where.exe' or 'Get-Command'.

.PARAMETER Concise
Concise output (only progress shown).

.PARAMETER PassThru
Returns the ffmpeg command arguments instead of executing them. Useful for compiling commands for later execution.

.EXAMPLE
.\set-track-priority.ps1 -Path "C:\videos\anime.mkv" -Type "Audio" -Lang "jpn,eng" -Replace

.EXAMPLE
.\set-track-priority.ps1 -Path "C:\videos\movies_folder" -Type "Audio" -Recurse -Lang "eng,spa" -Suffix "_audio_set" -Delete

.EXAMPLE
.\set-track-priority.ps1 -Path "C:\videos\movie.mkv" -Type "Audio" -Lang "jpn" -Title "commentary" -Replace
# This will prioritize the Japanese track. If there are multiple, it will pick one with "commentary" in the title.

.EXAMPLE
.\set-track-priority.ps1 -Path "C:\videos\movie.mkv" -Type "Subtitle" -Lang "eng" -Title "Full.*Doki" -Replace
# This will prioritize the English track. If there are multiple, it will pick one with "Full" and "Doki" in the title.

.NOTES
Requires ffmpeg and ffprobe.
The script remuxes the entire file, copying all video, audio, subtitle, and other streams.
If no audio stream matches the priority list, the file is skipped.
If only one audio stream exists, the file is skipped as no reordering is needed.
The -Replace operation is generally safer as it avoids leaving partial files if interrupted, but uses temporary disk space.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')] # Possible file modification/deletion
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
    [string[]]$Path,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Audio', 'Subtitle')]
    [string]$Type = 'Audio',

    [Parameter()]
    [string]$Lang = '',

    [Parameter()]
    [string]$Title = '',

    [Parameter()]
    [string]$Suffix = '_reordered', # Used only if -Replace is not specified

    [Parameter()]
    [string]$StreamInfoB64 = '',

    [Parameter()]
    [switch]$Recurse,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$Delete,

    [Parameter()]
    [switch]$Replace,

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
    [switch]$PassThru
)

begin {
    # --- Load Configuration from JSON ---
    $config = $null
    $effectiveConfigPath = $ConfigPath
    if ([string]::IsNullOrEmpty($effectiveConfigPath)) {
        # Default to config file named after script in the same directory
        $configType = if ($Type -eq 'Audio') { 'audio' } else { 'subs' }
        $effectiveConfigPath = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\config\set-$configType-priority-config.json")
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
                if ($keyLower -eq 'verbose') {
                    if ($PSBoundParameters.ContainsKey('Verbose') -eq $false) {
                        if ($paramValue -is [bool] -and $paramValue) { $VerbosePreference = 'Continue' }
                    }
                } elseif ($keyLower -eq 'debug') {
                    if ($PSBoundParameters.ContainsKey('Debug') -eq $false) {
                        if ($paramValue -is [bool] -and $paramValue) { $DebugPreference = 'Continue' }
                    }
                }
                elseif ($PSBoundParameters.ContainsKey($key) -eq $false -and $MyInvocation.MyCommand.Parameters.ContainsKey($key)) {
                    Write-Verbose "Overriding `$$key with value from config: '$paramValue'"
                    Set-Variable -Name $key -Value $paramValue -Scope Script
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
    $script:anyTrackSet = $false
    $script:ffmpegFailureCode = $null

    Write-Verbose "Script Root: $PSScriptRoot"

    # --- Parameter Validation ---
    if ($Delete -and $Replace) {
        Write-Error "-Delete and -Replace parameters are mutually exclusive."
        exit 1
    }

    # Set Defaults based on Type if not provided
    if ([string]::IsNullOrWhiteSpace($Lang)) {
        if ($Type -eq 'Audio') { $Lang = 'jpn,chi,kor,eng' }
        else { $Lang = 'eng,jpn' }
    }

    # --- Determine File Action ---
    # 0 = Create new with suffix, 1 = Delete original after creating new, 2 = Replace original
    $FileAction = 0
    if ($Delete) { $FileAction = 1 }
    if ($Replace) { $FileAction = 2 }
    Write-Verbose "File Action Mode: $FileAction (0=Suffix, 1=Delete, 2=Replace)"

    # --- Helper Function to Find Executables ---
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

        # 2. Script Directory (Check parent if running from ./scripts/powershell)
        $scriptDir = $PSScriptRoot
        $localPath = Join-Path $scriptDir "$Name.exe"
        if (Test-Path -LiteralPath $localPath -PathType Leaf) {
            Write-Verbose "Found $Name in script directory: $localPath"
            return $localPath
        }
        $parentDir = Split-Path (Split-Path $scriptDir -Parent) -Parent
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
                } else { Write-Verbose "$Name not found via Get-Command." }
            } catch { Write-Verbose "Get-Command failed for ${Name}: $($_.Exception.Message)" }
            try {
                $whereOutput = where.exe $Name 2>&1
                if ($LASTEXITCODE -eq 0 -and $whereOutput) {
                    $foundPath = $whereOutput | Select-Object -First 1
                    Write-Verbose "Found $Name via where.exe: $foundPath"
                    return $foundPath
                } else { Write-Verbose "$Name not found via where.exe." }
            } catch { Write-Verbose "where.exe failed for ${Name}: $($_.Exception.Message)" }
        } else {
            Write-Verbose "Skipping PATH search for $Name due to -DisableWhereSearch."
        }

        # Only error if ffmpeg is not found
        if ($Name -eq 'ffmpeg') {
            Write-Error "$Name could not be located. Please provide the path using -FfmpegPath or ensure it's in the script/parent directory or PATH."
            return $null # Indicate failure
        } else {
            Write-Warning "$Name could not be located, but may not be essential for this script."
            return $null # Indicate not found, but don't error
        }
    }

    # --- Locate FFMPEG and FFPROBE ---
    $ffmpeg = Find-Executable -Name 'ffmpeg' -ExplicitPath $FfmpegPath -DisableWhere:$DisableWhereSearch
    $ffprobe = Find-Executable -Name 'ffprobe' -ExplicitPath $FfprobePath -DisableWhere:$DisableWhereSearch
    if (-not $ffmpeg) {
        Write-Error "ffmpeg.exe could not be located."
        $script:fatalErrorOccurred = $true
        exit 1
    }

    if (-not $ffprobe -and [string]::IsNullOrEmpty($StreamInfoB64)) {
        Write-Error "ffprobe.exe could not be located and no stream info provided."
        $script:fatalErrorOccurred = $true
        exit 1
    }
    if (-not $Concise) {
        Write-Host "Using FFMPEG: $ffmpeg"
        if ($ffprobe) { Write-Host "Using FFPROBE: $ffprobe" }
    }

    # --- Prepare Priority Lists ---
    $LangPriorityList = $Lang.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if (-not $Concise) { Write-Host "Language Priority: $($LangPriorityList -join ', ')" }

    $TitlePriorityList = @()
    if (-not [string]::IsNullOrWhiteSpace($Title)) {
        $TitlePriorityList = $Title.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if (-not $Concise -and $TitlePriorityList.Count -gt 0) { Write-Host "Title Priority: $($TitlePriorityList -join ', ')" }
    }

    # --- Temporary File Suffix for Replace Mode ---
    $tempSuffix = ".tmp_reorder"

    # --- Generic Helpers ---
    function ConvertFrom-JsonHash {
        param(
            [Parameter(ValueFromPipeline = $true)]
            [string]$json
        )

        if ($PSVersionTable.PSVersion.Major -ge 6) {
            return ($json | ConvertFrom-Json -AsHashtable)
        }
        else {
            if (-not ("System.Web.Script.Serialization.JavaScriptSerializer" -as [type])) {
                Add-Type -AssemblyName System.Web.Extensions
            }
            $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
            $serializer.MaxJsonLength = [int32]::MaxValue
            return $serializer.Deserialize($json, [System.Collections.Hashtable])
        }
    }

    # --- Function to Process a Single File ---
    function Format-TrackPriority {
        param(
            [Parameter(Mandatory = $true)] [System.IO.FileInfo]$FileInput,
            [Parameter(Mandatory = $true)] [string[]]$LanguagePriority,
            [Parameter(Mandatory = $true)][AllowEmptyCollection()] [string[]]$TitlePriority,
            [Parameter(Mandatory = $true)] [int]$CurrentFileAction, # 0, 1, or 2
            [Parameter(Mandatory = $true)] [string]$OutputSuffix, # Used for action 0, 1
            [Parameter()] [switch]$ForceProcessing,
            [Parameter()] [switch]$PassThru
        )

        $inputFileFullPath = $FileInput.FullName
        $inputPath = $FileInput.DirectoryName
        $inputName = $FileInput.BaseName
        $inputExt = $FileInput.Extension

        if (-not $Concise) {
            Write-Host "`n-----------------------------------------------------"
            Write-Host "Processing $Type tracks for: $inputFileFullPath"
            Write-Host "Lang Priority: $($LanguagePriority -join ', ')"
            if ($TitlePriority.Count -gt 0) { Write-Host "Title Priority: $($TitlePriority -join ', ')" }
            Write-Host "Action: $CurrentFileAction (0=Suffix, 1=Delete, 2=Replace)"
            if ($CurrentFileAction -ne 2) { Write-Host "Suffix: $OutputSuffix" }
            Write-Host "Force: $ForceProcessing"
            Write-Host "-----------------------------------------------------`n"
        }

        # --- Determine Output Filename(s) ---
        $finalOutputFile = ''
        $ffmpegTargetFile = ''

        if ($CurrentFileAction -eq 2) { # Replace mode
            $ffmpegTargetFile = Join-Path $inputPath ($inputName + $tempSuffix + $inputExt)
            $finalOutputFile = $inputFileFullPath # Final destination is the original path
            Write-Verbose "Action: Replace original. Temp file: '$ffmpegTargetFile'"
        } else { # Suffix or Delete mode
            $ffmpegTargetFile = Join-Path $inputPath ($inputName + $OutputSuffix + $inputExt)
            $finalOutputFile = $ffmpegTargetFile # Final destination is the new suffixed file
            Write-Verbose "Action: Create new file. Target: '$ffmpegTargetFile'"
        }

        # --- Check if FINAL target exists (respect -f flag, only for non-replace mode) ---
        if ($CurrentFileAction -ne 2 -and (Test-Path -LiteralPath $finalOutputFile -PathType Leaf) -and (-not $ForceProcessing)) {
            Write-Warning "Skipping reorder, output file '$finalOutputFile' already exists. Use -Force to overwrite."
            return
        } elseif ($CurrentFileAction -ne 2 -and (Test-Path -LiteralPath $finalOutputFile -PathType Leaf) -and (-not $Concise)) {
            Write-Host "Output file '$finalOutputFile' exists, but -Force is enabled. Will overwrite."
        }

        # --- Get Stream Info (Index, Language) ---
        $streams = @()
        try {
            $probeData = $null

            # Check if Base64 data was provided
            if (-not [string]::IsNullOrEmpty($StreamInfoB64)) {
                Write-Verbose "Using provided Base64 stream info."
                try {
                    $jsonBytes = [Convert]::FromBase64String($StreamInfoB64)
                    $jsonStr = [Text.Encoding]::UTF8.GetString($jsonBytes)
                    $probeData = $jsonStr | ConvertFrom-JsonHash
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
                if ($LASTEXITCODE -ne 0) { Write-Warning "ffprobe failed (Exit Code: $LASTEXITCODE). Skipping."; return }
                $probeData = [string]$jsonOutput | ConvertFrom-JsonHash
            }

            if (-not $probeData -or -not $probeData.streams) {
                Write-Warning "Could not parse stream info for '$inputFileFullPath'. Skipping."
                return
            }

            # Filter for requested type
            $targetCodecType = if ($Type -eq 'Audio') { 'audio' } else { 'subtitle' }

            $streams = $probeData.streams | Where-Object { $_.codec_type -eq $targetCodecType } | ForEach-Object {
                [PSCustomObject]@{
                    Index     = $_.index
                    Lang      = if ($_.tags -and $_.tags.language) { $_.tags.language.ToLowerInvariant() } else { 'und' }
                    Title     = if ($_.tags -and $_.tags.title) { $_.tags.title } else { '' }
                    IsDefault = $_.disposition -and [System.Convert]::ToInt32($_.disposition.default) -ne 0
                    IsForced = $_.disposition -and [System.Convert]::ToInt32($_.disposition.forced) -ne 0
                }
            }

        } catch {
            Write-Error "Error parsing stream info for '$inputFileFullPath': $($_.Exception.Message)"
            $script:fatalErrorOccurred = $true
            return
        }

        if ($streams.Count -eq 0) {
            if (-not $Concise) { Write-Host "No $Type streams found. Skipping." }
            return
        }
        if ($streams.Count -eq 1) {
            if (-not $Concise) { Write-Host "Only one $Type stream found. No reordering needed. Skipping." }
            return
        }

        if (-not $Concise) {
            Write-Host "Found $($streams.Count) $Type streams:"
            $streams | Format-Table -AutoSize -Wrap
        }

        # --- Find Preferred Stream ---
        $defaultStream = $null

        # 1. Loop through language priorities
        foreach ($lang in $LanguagePriority) {
            $langMatchingStreams = @($streams | Where-Object { $_.Lang -eq $lang })
            if ($langMatchingStreams.Count -eq 0) { Write-Verbose "Language '$lang' not found in audio streams."; continue }

            if (-not $Concise) { Write-Host "Found language '$lang'. Analyzing $($langMatchingStreams.Count) matching stream(s)." }

            if ($langMatchingStreams.Count -eq 1) {
                $defaultStream = $langMatchingStreams[0]
                break
            }

            # Tie-break with Title
            if ($TitlePriority.Count -gt 0) {
                foreach ($title in $TitlePriority) {
                    $foundStream = $langMatchingStreams | Where-Object { $_.Title -and $_.Title -match $title } | Select-Object -First 1
                    if ($foundStream) {
                        $defaultStream = $foundStream
                        if (-not $Concise) { Write-Host "Selected based on title substring '$title'." }
                        break
                    }
                }
                if ($defaultStream) { break }
            }

            # Default to first if no title match
            if (-not $defaultStream) {
                $defaultStream = $langMatchingStreams[0]
                if (-not $Concise) { Write-Host "No title match for language '$lang', or no title priority specified. Defaulting to first stream found at index $($defaultStream.Index)." }
            }
            if ($defaultStream) { break }
        }

        # 2. Fall back to title-only priority
        if (-not $defaultStream -and $TitlePriority.Count -gt 0) {
            foreach ($title in $TitlePriority) {
                Write-Verbose "Testing title regex/substring: $title"
                $foundStream = $streams | Where-Object { $_.Title -and $_.Title -match $title } | Select-Object -First 1
                if ($foundStream) {
                    $defaultStream = $foundStream
                    if (-not $Concise) { Write-Host "Found preferred title pattern '$title' in stream index $($defaultStream.Index) (Title: '$($defaultStream.Title)')." }
                    break
                }
            }
        }

        if (-not $defaultStream) {
            Write-Warning "No $Type stream found matching priorities. Skipping."
            return
        }

        # --- Check if Processing is Actually Needed ---
        $firstStream = ($streams | Sort-Object Index)[0]
        $preferredIsFirst = $defaultStream.Index -eq $firstStream.Index
        $preferredIsDefault = $defaultStream.IsDefault
        $otherStreamIsDefault = $false
        foreach ($stream in $streams) {
            if ($stream.Index -ne $defaultStream.Index -and $stream.IsDefault) {
                $otherStreamIsDefault = $true
                Write-Verbose "Found another audio stream (Index: $($stream.Index)) also marked as default."
                break
            }
        }

        if ($preferredIsFirst -and $preferredIsDefault -and (-not $otherStreamIsDefault)) {
            if (-not $Concise) { Write-Host "File is already correctly configured. Skipping." }
            return
        }

        if (-not $Concise) { Write-Host "Proceeding with ffmpeg remux to set Stream Index $($defaultStream.Index) as default..." }

        # --- Construct FFMPEG Command ---
        $mapArgs = @()

        # We need to explicitly map other streams first to ensure they are copied
        $mapArgs += '-map', '0:v?' # Video
        $mapArgs += '-map', '0:d?' # Data
        $mapArgs += '-map', '0:t?' # Attachments

        # Determine mapping characters based on type
        if ($Type -eq 'Audio') {
             $mapArgs += '-map', '0:s?'
             $targetFlag = 'a'
        } else {
             $mapArgs += '-map', '0:a?'
             $targetFlag = 's'
        }

        # Add the default stream first
        $mapArgs += '-map', "0:$($defaultStream.Index)"
        $mapArgs += "-disposition:$targetFlag`:$0", 'default'

        # Add remaining streams of target type
        $i = 0
        foreach ($stream in $streams) {
            if ($stream.Index -ne $defaultStream.Index) {
                $i += 1
                $mapArgs += '-map', "0:$($stream.Index)"
                $mapArgs += "-disposition:$targetFlag`:$i", $(if ($stream.IsForced) { 'forced' } else { '0' })
            }
        }

        $ffmpegArgs = $mapArgs
        $ffmpegArgs += '-c', 'copy'

        # --- PassThru Mode ---
        if ($PassThru) {
            Write-Verbose "PassThru enabled. Returning ffmpeg arguments."
            return $ffmpegArgs
        }

        # --- Construct Full FFMPEG Command ---
        $fullFfmpegArgs = @('-y', '-stats')
        if ($Concise) { $fullFfmpegArgs += '-v', 'fatal' } else { $fullFfmpegArgs += '-v', 'warning' }
        $fullFfmpegArgs += '-i', "$inputFileFullPath"
        $fullFfmpegArgs += $ffmpegArgs
        $fullFfmpegArgs += "$ffmpegTargetFile"

        # --- Check Temporary File in Replace Mode ---
        if ($CurrentFileAction -eq 2 -and (Test-Path -LiteralPath $ffmpegTargetFile -PathType Leaf) -and (-not $ForceProcessing)) {
            Write-Warning "Temporary file '$ffmpegTargetFile' already exists. Use -Force to overwrite."
            return
        }

        # --- Execute FFMPEG ---
        if (-not $Concise) { Write-Host "Starting ffmpeg..." }

        if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Set default $Type track")) {
            $success = $false
            try {
                Write-Verbose "Running: $ffmpeg $($fullFfmpegArgs -join ' ')"
                & $ffmpeg @fullFfmpegArgs
                $exitCode = $LASTEXITCODE
                if (-not $Concise) { Write-Host "" }

                if ($exitCode -ne 0) {
                    Write-Error "ffmpeg process failed (Exit Code: $exitCode) while processing '$inputFileFullPath'."
                    $script:fatalErrorOccurred = $true
                    $script:ffmpegFailureCode = $exitCode
                } else {
                    if (-not $Concise) { Write-Host "Successfully processed into '$ffmpegTargetFile'." }
                    $success = $true
                    $script:anyTrackSet = $true
                }
            } catch {
                Write-Error "Error executing ffmpeg: $($_.Exception.Message)"
                $script:fatalErrorOccurred = $true
            }

            # --- Post-processing File Actions ---
            if ($success) {
                if ($CurrentFileAction -eq 1) { # Delete Original
                    if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Delete original")) {
                        try { Remove-Item -LiteralPath $inputFileFullPath -Force -ErrorAction Stop }
                        catch { Write-Warning "Failed to delete original: $($_.Exception.Message)" }
                    }
                } elseif ($CurrentFileAction -eq 2) { # Replace Original
                    if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Replace with processed file")) {
                        try {
                            Move-Item -LiteralPath $ffmpegTargetFile -Destination $inputFileFullPath -Force -ErrorAction Stop
                        } catch {
                            Write-Error "Failed to replace original file. Temp file '$ffmpegTargetFile' may still exist."
                        }
                    }
                }
            } else { # ffmpeg failed
                if (Test-Path -LiteralPath $ffmpegTargetFile -PathType Leaf) {
                    Remove-Item -LiteralPath $ffmpegTargetFile -Force -ErrorAction SilentlyContinue
                }
                # TODO: Cleanup
            }
        } else {
            Write-Warning "Skipping ffmpeg execution for '$inputFileFullPath' due to -WhatIf."
            $script:anyTrackSet = $true
        }

    } # End Function Format-TrackPriority

} # End Begin block

process {
    $videoExtensions = @(".mkv", ".mp4", ".avi", ".mov", ".wmv", ".flv", ".ts", ".webm", ".mpg", ".mpeg", ".m2ts") # Add more as needed

    foreach ($itemPath in $Path) {
        Write-Verbose "Processing argument: $itemPath"
        if ($script:fatalErrorOccurred) { Write-Warning "A fatal error occurred previously. Stopping further processing."; break }
        try {
            $item = Get-Item -LiteralPath $itemPath -ErrorAction Stop
            if ($item -is [System.IO.DirectoryInfo]) {
                if (-not $Concise) { Write-Host "`nProcessing directory: $($item.FullName) (Recursive: $Recurse)" }
                $allFiles = Get-ChildItem -LiteralPath $item.FullName -Recurse:$Recurse | Where-Object { $videoExtensions -contains $_.Extension }
                $filesToProcess = $allFiles | Where-Object {
                    ($FileAction -ne 2 -or $_.Name -notlike "*$tempSuffix$($_.Extension)") -and `
                    ($FileAction -eq 2 -or $Suffix -eq '' -or $_.BaseName -notlike "*$Suffix")
                }
                $totalFiles = $filesToProcess.Count
                $processedCount = 0

                if ($totalFiles -eq 0) {
                    if (-not $Concise) { Write-Host "No supported video files found (or all are temp/processed) in '$($item.FullName)'." }
                    continue
                }
                if (-not $Concise) { Write-Host "Found $totalFiles video file(s) to process." }

                foreach ($file in $filesToProcess) {
                    $processedCount++
                    Write-Host "Progress: $processedCount / $totalFiles - Setting audio for '$($file.Name)'"
                    if ($FileAction -eq 2 -and $file.Name -like "*$tempSuffix$($file.Extension)") {
                        Write-Verbose "Skipping temporary file: $($file.FullName)"
                        continue
                    }
                    if ($FileAction -ne 2 -and $Suffix -ne '' -and $file.BaseName -like "*$Suffix") {
                        Write-Verbose "Skipping already processed file (suffix match): $($file.FullName)"
                        continue
                    }

                    $result = Format-TrackPriority -FileInput $file `
                                          -LanguagePriority $LangPriorityList `
                                          -TitlePriority $TitlePriorityList `
                                          -CurrentFileAction $FileAction `
                                          -OutputSuffix $Suffix `
                                          -ForceProcessing:$Force `
                                          -PassThru:$PassThru
                    if (-not $script:anyTrackSet) {
                        $script:anyTrackSet = $null -ne $result
                    }
                    if ($PassThru -and $result) {
                        $script:anyTrackSet = $true
                        return $result
                    }
                }

            } elseif ($item -is [System.IO.FileInfo]) {
                if ($videoExtensions -contains $item.Extension) {
                    # Skip temporary files
                    if ($FileAction -eq 2 -and $item.Name -like "*$tempSuffix$($item.Extension)") {
                        Write-Warning "Skipping temporary file provided directly: $($item.FullName)"
                        continue
                    }

                    if ($FileAction -ne 2 -and $Suffix -ne '' -and $item.BaseName -like "*$Suffix") {
                        Write-Warning "Skipping already processed file (suffix match) provided directly: $($item.FullName)"
                        continue
                    }

                    $result = Format-TrackPriority -FileInput $item `
                                        -LanguagePriority $LangPriorityList `
                                        -TitlePriority $TitlePriorityList `
                                        -CurrentFileAction $FileAction `
                                        -OutputSuffix $Suffix `
                                        -ForceProcessing:$Force `
                                        -PassThru:$PassThru
                    if ($PassThru -and $result) {
                        $script:anyTrackSet = $true
                        return $result
                    }
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
    if (-not $Concise) { Write-Host "`nSet track priority script finished." }

    # Determine final exit code
    if ($script:fatalErrorOccurred) {
        if ($null -ne $script:ffmpegFailureCode) {
            Write-Verbose "Exiting with ffmpeg failure code: $script:ffmpegFailureCode."
            exit $script:ffmpegFailureCode
        } else {
            Write-Verbose "Exiting with code 1 (Generic Fatal Error)."
            exit 1
        }
    } elseif ($script:anyTrackSet) {
        Write-Verbose "Exiting with code 0 (Success/Audio Set Attempted)."
        exit 0
    } else {
        Write-Verbose "Exiting with code -2 (No Audio Setting Needed/Performed)."
        exit -2 # Use -2 to indicate nothing needed to be done or no matching streams found
    }
} # End End block
