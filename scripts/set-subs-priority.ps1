<#
.SYNOPSIS
Batch Default Subtitle Setter - Sets the default subtitle track in video files based on language priority using ffmpeg.

.DESCRIPTION
Scans video files or directories for subtitle streams, identifies the preferred language based on a priority list,
and remuxes the file (copying all streams) to set the chosen subtitle track as the default.
Can either create a new file with a suffix or replace the original file.

.PARAMETER Path
One or more input video file paths or directory paths to process.

.PARAMETER Lang
Comma-separated language priority list (3-letter ISO 639-2 codes, e.g., "jpn,eng,kor"). Case-insensitive.
Default: 'eng,jpn'.

.PARAMETER Title
Comma-separated subtitle title priority list (regex patterns, e.g., "Full,Dialogue,Signs"). Case-insensitive.
Used as a tie-breaker for language matches, or as a primary selector if no language matches are found.
Default: 'Full,Dialogue,Signs'.

.PARAMETER Suffix
Suffix for the output filename when not using -Replace. Default: '_reordered'. Ignored if -Replace is used.

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

.EXAMPLE
.\set-subs-priority.ps1 -Path "C:\videos\anime.mkv" -Lang "fra,eng" -Replace

.EXAMPLE
.\set-subs-priority.ps1 -Path "C:\videos\movies_folder" -Recurse -Lang "spa" -Suffix "_subs_set" -Delete

.EXAMPLE
.\set-subs-priority.ps1 -Path "C:\videos\movie.mkv" -Lang "eng" -Title "Signs,Songs" -Replace
# This will prioritize the English track. If there are multiple, it will pick one with "Signs" or "Songs" in the title.

.EXAMPLE
.\set-subs-priority.ps1 -Path "C:\videos\movie.mkv" -Lang "eng" -Title "Full.*Doki" -Replace
# This will prioritize the English track. If there are multiple, it will pick one with "Full" and "Doki" in the title.

.NOTES
Requires ffmpeg and ffprobe.
The script remuxes the entire file, copying all video, audio, subtitle, and other streams.
If no subtitle stream matches the priority list, the file is skipped.
If only one subtitle stream exists, the file is skipped as no reordering is needed.
The -Replace operation is generally safer as it avoids leaving partial files if interrupted, but uses temporary disk space.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')] # Possible file modification/deletion
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
    [string[]]$Path,

    [Parameter()]
    [string]$Lang = 'eng,jpn',

    [Parameter()]
    [string]$Title = '',

    [Parameter()]
    [string]$Suffix = '_reordered', # Used only if -Replace is not specified

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
    [string]$ConfigPath = ''
)

begin {
    # --- Load Configuration from JSON ---
    $config = $null
    $effectiveConfigPath = $ConfigPath
    if ([string]::IsNullOrEmpty($effectiveConfigPath)) {
        # Default to config file named after script in the same directory
        $effectiveConfigPath = Join-Path $PSScriptRoot ($MyInvocation.MyCommand.Name -replace '\.ps1$', '-config.json')
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
                        } # else { $VerbosePreference = 'SilentlyContinue' }
                    } else { Write-Verbose "Parameter -Verbose was provided via command line, ignoring config value." }
                } elseif ($keyLower -eq 'debug') {
                    if ($PSBoundParameters.ContainsKey('Debug') -eq $false) {
                        if ($paramValue -is [bool] -and $paramValue) {
                            $DebugPreference = 'Continue'
                            Write-Verbose "Setting `$DebugPreference = 'Continue' based on config."
                        } # else { $DebugPreference = 'SilentlyContinue' }
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
    $script:anySubsSet = $false
    $script:ffmpegFailureCode = $null

    Write-Verbose "Script Root: $PSScriptRoot"

    # --- Parameter Validation ---
    if ($Delete -and $Replace) {
        Write-Error "-Delete and -Replace parameters are mutually exclusive."
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($Lang)) {
        $Lang = 'eng,jpn' # Default language priority
    }

    # --- Determine File Action ---
    # 0 = Create new with suffix, 1 = Delete original after creating new, 2 = Replace original
    $FileAction = 0
    if ($Delete) { $FileAction = 1 }
    if ($Replace) { $FileAction = 2 }
    Write-Verbose "File Action Mode: $FileAction (0=Suffix, 1=Delete, 2=Replace)"

    # --- Helper Function to Find Executables (Adapted) ---
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
                Write-Verbose "Using explicit path: $ExplicitPath"; return (Get-Item -LiteralPath $ExplicitPath).FullName
            } else { Write-Warning "Explicit path for $Name not found: $ExplicitPath" }
        }
        # 2. Script/Parent Directory
        $scriptDir = $PSScriptRoot
        $localPath = Join-Path $scriptDir "$Name.exe"
        if (Test-Path -LiteralPath $localPath -PathType Leaf) { Write-Verbose "Found $Name in script directory: $localPath"; return $localPath }
        $parentDir = Split-Path -LiteralPath $scriptDir
        $parentLocalPath = Join-Path $parentDir "$Name.exe"
        if (Test-Path -LiteralPath $parentLocalPath -PathType Leaf) { Write-Verbose "Found $Name in parent directory: $parentLocalPath"; return $parentLocalPath }
        # 3. PATH
        if (-not $DisableWhere) {
            try { $foundPath = (Get-Command $Name -EA SilentlyContinue).Source; if ($foundPath) { Write-Verbose "Found $Name via Get-Command: $foundPath"; return $foundPath } else { Write-Verbose "$Name not found via Get-Command." } } catch { Write-Verbose "Get-Command failed: $($_.Exception.Message)"}
            try { $whereOutput = where.exe $Name 2>&1; if ($LASTEXITCODE -eq 0 -and $whereOutput) { $foundPath = $whereOutput | Select-Object -First 1; Write-Verbose "Found $Name via where.exe: $foundPath"; return $foundPath } else { Write-Verbose "$Name not found via where.exe." } } catch { Write-Verbose "where.exe failed: $($_.Exception.Message)"}
        } else { Write-Verbose "Skipping PATH search for $Name." }
        # Error only if required executable not found
        if ($Name -in ('ffmpeg', 'ffprobe')) { Write-Error "$Name could not be located."; return $null }
        else { Write-Warning "$Name could not be located."; return $null }
    }

    # --- Locate FFMPEG and FFPROBE ---
    $ffmpeg = Find-Executable -Name 'ffmpeg' -ExplicitPath $FfmpegPath -DisableWhere:$DisableWhereSearch
    $ffprobe = Find-Executable -Name 'ffprobe' -ExplicitPath $FfprobePath -DisableWhere:$DisableWhereSearch
    if (-not $ffmpeg) {
        Write-Error "ffmpeg.exe could not be located."
        $script:fatalErrorOccurred = $true
        exit 1
    }
    if (-not $ffprobe) {
        Write-Error "ffprobe.exe could not be located."
        $script:fatalErrorOccurred = $true
        exit 1
    }
    if (-not $Concise) {
        Write-Host "Using FFMPEG: $ffmpeg"
        Write-Host "Using FFPROBE: $ffprobe"
    }

    # --- Prepare Language Priority List ---
    $LangPriorityList = $Lang.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if (-not $Concise) { Write-Host "Language Priority: $($LangPriorityList -join ', ')" }

    $TitlePriorityList = @()
    if (-not [string]::IsNullOrWhiteSpace($Title)) {
        $TitlePriorityList = $Title.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if (-not $Concise -and $TitlePriorityList.Count -gt 0) { Write-Host "Title Priority: $($TitlePriorityList -join ', ')" }
    }

    # --- Temporary File Suffix for Replace Mode ---
    $tempSuffix = ".tmp_reorder"


    # --- Function to Process a Single File ---
    function Set-DefaultSubtitleLogic {
        param(
            [Parameter(Mandatory = $true)]
            [System.IO.FileInfo]$FileInput,

            [Parameter(Mandatory = $true)]
            [string[]]$LanguagePriority,

            [Parameter(Mandatory = $true)][AllowEmptyCollection()]
            [string[]]$TitlePriority,

            [Parameter(Mandatory = $true)]
            [int]$CurrentFileAction, # 0, 1, or 2

            [Parameter(Mandatory = $true)]
            [string]$OutputSuffix, # Used for action 0, 1

            [Parameter()]
            [switch]$ForceProcessing
        )

        $inputFileFullPath = $FileInput.FullName
        $inputPath = $FileInput.DirectoryName
        $inputName = $FileInput.BaseName
        $inputExt = $FileInput.Extension

        if (-not $Concise) {
            Write-Host "`n-----------------------------------------------------"
            Write-Host "Processing Subtitles for: $inputFileFullPath"
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
        # For replace mode, we check the *temp* file existence later before running ffmpeg

        # --- Get Subtitle Stream Info (Index, Language) ---
        if (-not $Concise) { Write-Host "Probing subtitle streams..." }
        $subtitleStreams = @() # Array of PSCustomObjects
        try {
            $ffprobeArgs = @(
                '-v', 'error',
                '-select_streams', 's', # Select only subtitle streams
                '-show_streams',
                # Request index, disposition flags, and language tag (doesn't properly retrieve disposition)
                # '-show_entries', 'stream=index,disposition:stream_tags=language',
                '-of', 'json',
                "`"$inputFileFullPath`""
            )
            Write-Verbose "Running: $ffprobe $($ffprobeArgs -join ' ')"
            $jsonOutput = & $ffprobe @ffprobeArgs 2>&1 # Capture stdout and stderr
            $exitCode = $LASTEXITCODE

            if ($exitCode -ne 0) {
                Write-Warning "ffprobe failed to get subtitle stream info for '$inputFileFullPath' (Exit Code: $exitCode). Skipping."
                # Write-Verbose "ffprobe output: $jsonOutput"
                return
            }
            if ([string]::IsNullOrWhiteSpace($jsonOutput)) {
                if (-not $Concise) { Write-Host "No subtitle streams found via ffprobe for '$inputFileFullPath'. Skipping." }
                return
            }

            $probeData = $jsonOutput | ConvertFrom-Json -ErrorAction SilentlyContinue
            if (-not $probeData -or -not $probeData.streams) {
                Write-Warning "Could not parse ffprobe JSON output or no streams found for '$inputFileFullPath'."
                return
            }

            # Convert to simpler objects for easier handling
            $subtitleStreams = $probeData.streams | ForEach-Object {
                [PSCustomObject]@{
                    Index     = $_.index
                    Lang      = if ($_.tags -and $_.tags.language) { $_.tags.language.ToLowerInvariant() } else { 'und' }
                    Title     = if ($_.tags -and $_.tags.title) { $_.tags.title } else { '' }
                    IsDefault = $_.disposition -and [System.Convert]::ToInt32($_.disposition.default) -ne 0
                }
            }

        } catch {
            Write-Error "Error running ffprobe for subtitle info on '$inputFileFullPath': $($_.Exception.Message)"
            $script:fatalErrorOccurred = $true # Consider ffprobe error potentially fatal
            return
        }

        if ($subtitleStreams.Count -eq 0) {
            if (-not $Concise) { Write-Host "No subtitle streams found in '$inputFileFullPath'. Skipping." }
            return
        }
        if ($subtitleStreams.Count -eq 1) {
            if (-not $Concise) { Write-Host "Only one subtitle stream found (Index: $($subtitleStreams[0].Index)). No reordering needed. Skipping." }
            return
        }

        if (-not $Concise) {
            Write-Host "Found $($subtitleStreams.Count) subtitle streams:"
            $subtitleStreams | Format-Table -AutoSize -Wrap
        }

        # --- Find Preferred Subtitle Stream ---
        $defaultSubtitleStream = $null

        # 1. Loop through language priorities to find a candidate stream
        foreach ($lang in $LanguagePriority) {
            $langMatchingStreams = @($subtitleStreams | Where-Object { $_.Lang -eq $lang })
            if ($langMatchingStreams.Count -eq 0) {
                Write-Verbose "Language '$lang' not found in subtitle streams."
                continue
            }

            if (-not $Concise) { Write-Host "Found language '$lang'. Analyzing $($langMatchingStreams.Count) matching stream(s)." }

            if ($langMatchingStreams.Count -eq 1) {
                $defaultSubtitleStream = $langMatchingStreams[0]
                if (-not $Concise) { Write-Host "Selected single stream for language '$lang' at index $($defaultSubtitleStream.Index)." }
                break
            }

            # Multiple streams for this language, use Title as tie-breaker
            if ($TitlePriority.Count -gt 0) {
                if (-not $Concise) { Write-Host "Multiple streams for '$lang' found. Using title priority to select one." }
                $regex = [regex]::new('(' + ($TitlePriority -join '|') + ')', 'IgnoreCase')
                $foundStream = $langMatchingStreams | Where-Object { $_.Title -and $_.Title -match $regex } | Select-Object -First 1
                if ($foundStream) {
                    $defaultSubtitleStream = $foundStream
                    if (-not $Concise) { Write-Host "Selected stream for '$lang' based on title pattern '$titlePattern' at index $($defaultSubtitleStream.Index)." }
                    break
                }
                if ($defaultSubtitleStream) { break } # Exit outer language loop
            }

            # If still no selection (e.g. no title match), default to the first stream for this language
            if (-not $defaultSubtitleStream) {
                $defaultSubtitleStream = $langMatchingStreams[0]
                if (-not $Concise) { Write-Host "No title match for language '$lang', or no title priority specified. Defaulting to first stream found at index $($defaultSubtitleStream.Index)." }
            }

            if ($defaultSubtitleStream) { break } # Exit language loop
        }

        # 2. If no language match, fall back to title-only priority
        if (-not $defaultSubtitleStream -and $TitlePriority.Count -gt 0) {
            if (-not $Concise) { Write-Host "No language match from priority list. Checking title-only priority..." }
            $regex = [regex]::new('(' + ($TitlePriority -join '|') + ')', 'IgnoreCase')
            $foundStream = $subtitleStreams | Where-Object { $_.Title -and $_.Title -match $regex } | Select-Object -First 1
            if ($foundStream) {
                $defaultSubtitleStream = $foundStream
                if (-not $Concise) { Write-Host "Found preferred title pattern '$titlePattern' in stream index $($defaultSubtitleStream.Index) (Title: '$($defaultSubtitleStream.Title)')." }
                break
            }
        }

        if (-not $defaultSubtitleStream) {
            $priorityDescription = @()
            if ($LanguagePriority.Count -gt 0 -and $LanguagePriority[0]) { $priorityDescription += "languages '$($LanguagePriority -join ', ')'" }
            if ($TitlePriority.Count -gt 0 -and $TitlePriority[0]) { $priorityDescription += "titles '$($TitlePriority -join ', ')'" }
            Write-Warning "No subtitle stream found matching the priority for $($priorityDescription -join ' or '). Skipping file."
            return
        }

        # --- Check if Processing is Actually Needed ---
        $firstSubtitleStream = ($subtitleStreams | Sort-Object Index)[0]
        $preferredIsFirst = $defaultSubtitleStream.Index -eq $firstSubtitleStream.Index
        $preferredIsDefault = $defaultSubtitleStream.IsDefault
        # Check if any *other* stream is also marked as default
        $otherStreamIsDefault = $false
        foreach ($stream in $subtitleStreams) {
            if ($stream.Index -ne $defaultSubtitleStream.Index -and $stream.IsDefault) {
                $otherStreamIsDefault = $true
                Write-Warning "Found another subtitle stream (Index: $($stream.Index)) also marked as default."
                break # Found one, no need to check further
            }
        }

        # Skip ONLY if the preferred stream is first, is default, AND no other stream is default.
        if ($preferredIsFirst -and $preferredIsDefault -and (-not $otherStreamIsDefault)) {
            if (-not $Concise) { Write-Host "File is already correctly configured: Preferred subtitle (Index: $($defaultSubtitleStream.Index), Lang: $($defaultSubtitleStream.Lang)) is first, marked default, and no other streams conflict. Skipping." }
            return
        }

        # --- Log Reason for Processing ---
        if (-not $Concise) {
            if (-not $preferredIsFirst) {
                Write-Host "Reason: Preferred subtitle stream (Index: $($defaultSubtitleStream.Index)) needs to be moved to the first position."
            }
            if (-not $preferredIsDefault) {
                Write-Host "Reason: Preferred subtitle stream (Index: $($defaultSubtitleStream.Index)) needs its 'default' flag set."
            }
            if ($otherStreamIsDefault) {
                Write-Host "Reason: Need to remove 'default' flag from other subtitle streams."
            }
            Write-Host "Proceeding with ffmpeg remux..."
        }

        # --- Construct ffmpeg map arguments ---
        $mapArgs = @(
            '-map', '0:v?', # Map video streams (optional)
            '-map', '0:a?',  # Map audio streams (optional)
            '-map', '0:t?',  # Map all attachment streams (e.g., fonts) (optional)
            '-map', '0:d?' # Map data streams (optional)
            # Data streams? Attachments? Map all metadata?
        )
        # Add the default subtitle stream first
        $mapArgs += '-map', "0:$($defaultSubtitleStream.Index)"

        # Add remaining subtitle streams
        foreach ($stream in $subtitleStreams) {
            if ($stream.Index -ne $defaultSubtitleStream.Index) {
                $mapArgs += '-map', "0:$($stream.Index)"
            }
        }

        # --- Construct Full FFMPEG Command ---
        $ffmpegArgs = @(
            '-v', 'warning', '-stats',
            '-y', # Overwrite temporary file or final file if -Force is used
            '-i', "`"$inputFileFullPath`""
        )
        $ffmpegArgs += $mapArgs
        $ffmpegArgs += '-c', 'copy' # Copy all mapped streams

        # Reset disposition for ALL output subtitle streams to 0 (none)
        $ffmpegArgs += '-disposition:s', '0'
        $ffmpegArgs += '-disposition:s:0', 'default'
        # Note: The order matters here. Reset all first, then set the specific one. This will cause an ffmpeg warning, but it's ignorable.

        $ffmpegArgs += "`"$ffmpegTargetFile`"" # Output (temporary or final)

        # --- Check Temporary File in Replace Mode ---
        if ($CurrentFileAction -eq 2 -and (Test-Path -LiteralPath $ffmpegTargetFile -PathType Leaf) -and (-not $ForceProcessing)) {
            Write-Warning "Temporary file '$ffmpegTargetFile' already exists for replace operation. Use -Force to overwrite it and proceed."
            return
        } elseif ($CurrentFileAction -eq 2 -and (Test-Path -LiteralPath $ffmpegTargetFile -PathType Leaf) -and (-not $Concise)) {
            Write-Host "Temporary file '$ffmpegTargetFile' exists, but -Force is enabled. Will overwrite."
        }

        # --- Execute FFMPEG ---
        if (-not $Concise) { Write-Host "Starting ffmpeg reorder command:`n$ffmpeg $($ffmpegArgs -join ' ')" }

        if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Set default subtitle track (Output: $ffmpegTargetFile)")) {
            $success = $false
            try {
                Write-Verbose "Running: $ffmpeg $($ffmpegArgs -join ' ')"
                & $ffmpeg @ffmpegArgs
                $exitCode = $LASTEXITCODE
                if (-not $Concise) { Write-Host "" }

                if ($exitCode -ne 0) {
                    Write-Error "ffmpeg process failed (Exit Code: $exitCode) while processing '$inputFileFullPath'."
                    $script:fatalErrorOccurred = $true
                    $script:ffmpegFailureCode = $exitCode
                } else {
                    if (-not $Concise) { Write-Host "Successfully processed subtitle streams into '$ffmpegTargetFile'." }
                    $success = $true
                    $script:anySubsSet = $true
                }
            } catch {
                Write-Error "Error executing ffmpeg for '$inputFileFullPath': $($_.Exception.Message)"
                $script:fatalErrorOccurred = $true
            }

            # --- Post-processing File Actions ---
            if ($success) {
                if ($CurrentFileAction -eq 1) { # Delete Original
                    if (-not $Concise) { Write-Host "Deleting original file: '$inputFileFullPath'" }
                    if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Delete original after successful processing")) {
                        try { Remove-Item -LiteralPath $inputFileFullPath -Force -ErrorAction Stop; if (-not $Concise) { Write-Host "Successfully deleted original." } }
                        catch { Write-Warning "Failed to delete original '$inputFileFullPath': $($_.Exception.Message)" }
                    } else { Write-Warning "Skipping deletion of original due to -WhatIf." }

                } elseif ($CurrentFileAction -eq 2) { # Replace Original
                    if (-not $Concise) { Write-Host "Replacing original file '$inputFileFullPath' with '$ffmpegTargetFile'" }
                    if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Replace with processed file '$ffmpegTargetFile'")) {
                        try {
                            # Move/Rename the temporary file to the original filename, overwriting it
                            Move-Item -LiteralPath $ffmpegTargetFile -Destination $inputFileFullPath -Force -ErrorAction Stop
                            if (-not $Concise) { Write-Host "Successfully replaced original file." }
                        } catch {
                            Write-Error "Failed to replace original file '$inputFileFullPath' with temporary file '$ffmpegTargetFile'. Error: $($_.Exception.Message)"
                            Write-Warning "Temporary file '$ffmpegTargetFile' may still exist."
                            # Do not delete the temp file automatically in case user wants to recover it
                        }
                    } else {
                        Write-Warning "Skipping replacement of original due to -WhatIf. Temporary file '$ffmpegTargetFile' may remain."
                        # Consider removing temp file if -WhatIf? Or leave it? Let's leave it.
                    }
                }
                # Action 0 (Suffix) requires no further action here, the file is already named correctly.

            } else { # ffmpeg failed
                # Clean up temporary file if it exists (only in replace mode)
                if ($CurrentFileAction -eq 2 -and (Test-Path -LiteralPath $ffmpegTargetFile -PathType Leaf)) {
                    Write-Warning "Attempting to remove incomplete temporary file: $ffmpegTargetFile"
                    Remove-Item -LiteralPath $ffmpegTargetFile -Force -ErrorAction SilentlyContinue
                }
                # For action 0/1, the $ffmpegTargetFile is the final file, remove if failed?
                elseif ($CurrentFileAction -ne 2 -and (Test-Path -LiteralPath $ffmpegTargetFile -PathType Leaf)) {
                    Write-Warning "Attempting to remove failed output file: $ffmpegTargetFile"
                    Remove-Item -LiteralPath $ffmpegTargetFile -Force -ErrorAction SilentlyContinue
                }
            } # End if ($success)

        } else { # ShouldProcess returned false (-WhatIf)
            Write-Warning "Skipping ffmpeg execution for '$inputFileFullPath' due to -WhatIf."
            $script:anySubsSet = $true # Consider WhatIf as an attempted operation
            # No post-processing needed for -WhatIf
        }

    } # End Function Set-DefaultSubtitleLogic

} # End Begin block

process {
    # Define common video extensions
    $videoExtensions = @(".mkv", ".mp4", ".avi", ".mov", ".wmv", ".flv", ".ts", ".webm", ".mpg", ".mpeg", ".m2ts") # Add more as needed

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
                $allFiles = Get-ChildItem -LiteralPath $item.FullName -Recurse:$Recurse | Where-Object { $videoExtensions -contains $_.Extension }
                # Filter out temp/processed files before counting
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
                    Write-Host "Progress: $processedCount / $totalFiles - Setting subtitles for '$($file.Name)'"
                    # Skip temporary files (redundant check, but safe)
                    if ($FileAction -eq 2 -and $file.Name -like "*$tempSuffix$($file.Extension)") {
                        Write-Verbose "Skipping temporary file: $($file.FullName)"
                        continue
                    }
                    # Skip already processed files (redundant check, but safe)
                    if ($FileAction -ne 2 -and $Suffix -ne '' -and $file.BaseName -like "*$Suffix") {
                        Write-Verbose "Skipping already processed file (suffix match): $($file.FullName)"
                        continue
                    }

                    Set-DefaultSubtitleLogic -FileInput $file `
                                          -LanguagePriority $LangPriorityList `
                                          -TitlePriority $TitlePriorityList `
                                          -CurrentFileAction $FileAction `
                                          -OutputSuffix $Suffix `
                                          -ForceProcessing:$Force
                }

            } elseif ($item -is [System.IO.FileInfo]) {
                # Check if the file extension is in our list
                if ($videoExtensions -contains $item.Extension) {
                    # Skip temporary files if passed directly
                    if ($FileAction -eq 2 -and $item.Name -like "*$tempSuffix$($item.Extension)") {
                        Write-Warning "Skipping temporary file provided directly: $($item.FullName)"
                        continue
                    }
                    # Skip already processed files if passed directly (using suffix from non-replace mode)
                    if ($FileAction -ne 2 -and $Suffix -ne '' -and $item.BaseName -like "*$Suffix") {
                        Write-Warning "Skipping already processed file (suffix match) provided directly: $($item.FullName)"
                        continue
                    }

                    Write-Host "Progress: 1 / 1 - Setting subtitles for '$($item.Name)'"
                    Set-DefaultSubtitleLogic -FileInput $item `
                                        -LanguagePriority $LangPriorityList `
                                        -TitlePriority $TitlePriorityList `
                                        -CurrentFileAction $FileAction `
                                        -OutputSuffix $Suffix `
                                        -ForceProcessing:$Force
                } else {
                    Write-Warning "Skipping file '$($item.FullName)' as its extension '$($item.Extension)' is not in the recognized list of video formats."
                }

            } else {
                Write-Warning "Path '$itemPath' is not a file or directory. Skipping."
            }
        } catch {
            Write-Error "Error processing path '$itemPath': $($_.Exception.Message)"
            $script:fatalErrorOccurred = $true # Error getting item is fatal
            # Continue to end block to exit with correct code
        }
    }
} # End Process block

end {
    if (-not $Concise) { Write-Host "`nSet subtitle priority script finished." }

    # Determine final exit code
    if ($script:fatalErrorOccurred) {
        if ($null -ne $script:ffmpegFailureCode) {
            Write-Verbose "Exiting with ffmpeg failure code: $script:ffmpegFailureCode."
            exit $script:ffmpegFailureCode
        } else {
            Write-Verbose "Exiting with code 1 (Generic Fatal Error)."
            exit 1
        }
    } elseif ($script:anySubsSet) {
        Write-Verbose "Exiting with code 0 (Success/Subtitle Set Attempted)."
        exit 0
    } else {
        Write-Verbose "Exiting with code -2 (No Subtitle Setting Needed/Performed)."
        exit -2 # Use -2 to indicate nothing needed to be done or no matching streams found
    }
} # End End block