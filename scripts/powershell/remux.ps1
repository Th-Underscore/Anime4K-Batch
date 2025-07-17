<#
.SYNOPSIS
Batch Remuxer - Remuxes video files to a new container format using ffmpeg.

.DESCRIPTION
Processes video files or directories, copying all existing video, audio, and subtitle streams into a new container format without re-encoding.

.PARAMETER Path
One or more input video file paths or directory paths to process.

.PARAMETER Container
Target output container format (e.g., 'mp4', 'mkv'). Default: 'mp4'.

.PARAMETER Recurse
Process folders recursively.

.PARAMETER Force
Force overwrite existing output files.

.PARAMETER Delete
Delete original file after successful remux (USE WITH CAUTION!).

.PARAMETER FfmpegPath
Path to ffmpeg executable. Auto-detected if not provided.

.PARAMETER DisableWhereSearch
Disable searching for ffmpeg in PATH using 'where.exe' or 'Get-Command'.

.PARAMETER Concise
Concise output (only progress shown).

.PARAMETER PassThru
Returns the ffmpeg command arguments instead of executing them. Useful for compiling commands for later execution.

.EXAMPLE
.\remux.ps1 -Path "C:\videos\input.avi" -Container mkv

.EXAMPLE
.\remux.ps1 -Path "C:\videos\downloads" -Recurse -Container mp4 -Delete -Force

.NOTES
Requires ffmpeg. This script copies streams directly; it does not re-encode.
Ensure the target container supports the codecs present in the source file.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')] # Possible file modification/deletion
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
    [string[]]$Path,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Container = 'mp4',

    [Parameter()]
    [switch]$Recurse,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$Delete,

    [Parameter()]
    [string]$FfmpegPath = '',

    # FFprobe not strictly needed for basic remux, but keep parameter for consistency
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
                        } # else { $VerbosePreference = 'SilentlyContinue' } # Default is usually SilentlyContinue
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

    # --- Container Compatibility Rules ---
    # Define conditions where certain stream types should NOT be copied.
    # Key: Container extension (e.g., '.mp4')
    # Value: Array of strings ('no_video', 'no_audio', 'no_subs')
    $containerLimitations = @{
        '.gif' = @('no_copy_video', 'no_audio', 'no_subs', 'no_ttf', 'no_data') # GIF needs video transcode, no audio/subs, no fonts, no data streams
        '.mp4' = @('no_subs', 'no_ttf') # MP4 subtitle copy is often problematic
        # Add more container rules as needed
        # '.avi' = @('no_subs') # Example
        # '.mov' = @('no_subs') # Example
    }

    # --- Script Status Tracking ---
    $script:fatalErrorOccurred = $false
    $script:anyRemuxPerformed = $false
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

    # --- Locate FFMPEG ---
    $ffmpeg = Find-Executable -Name 'ffmpeg' -ExplicitPath $FfmpegPath -DisableWhere:$DisableWhereSearch
    if (-not $ffmpeg) {
        $script:fatalErrorOccurred = $true
        exit 1
    }
    if (-not $Concise) { Write-Host "Using FFMPEG: $ffmpeg" }

    # --- Validate Container ---
    # Remove leading dot if present
    $outputExt = "." + $Container.TrimStart('.')
    if (-not $Concise) { Write-Host "Target Container Extension: $outputExt" }

    # --- Function to Process a Single File ---
    function Convert-VideoFile {
        param(
            [Parameter(Mandatory = $true)]
            [System.IO.FileInfo]$FileInput,

            [Parameter(Mandatory = $true)]
            [string]$OutputExt,

            [Parameter()]
            [switch]$ForceProcessing,

            [Parameter()]
            [switch]$DeleteOriginalFlag,

            [Parameter()]
            [switch]$PassThru
        )

        $inputFileFullPath = $FileInput.FullName
        $inputPath = $FileInput.DirectoryName
        $inputName = $FileInput.BaseName
        $inputExt = $FileInput.Extension

        # Construct Output Path
        $outputFileFullPath = Join-Path $inputPath ($inputName + $OutputExt)

        if (-not $Concise) {
            Write-Host "`n-----------------------------------------------------"
            Write-Host "Remuxing: $inputFileFullPath"
            Write-Host "Output:   $outputFileFullPath"
            Write-Host "-----------------------------------------------------`n"
        }

        # Check if input and output are the same (e.g., remuxing mkv to mkv)
        if ($inputFileFullPath -eq $outputFileFullPath) {
            Write-Warning "Skipping remux, input and output file are the same: '$inputFileFullPath'"
            return
        }

        # Check if Output File Exists and handle -Force
        if (Test-Path -LiteralPath $outputFileFullPath -PathType Leaf) {
            if (-not $ForceProcessing) {
                Write-Warning "Skipping remux, output file '$outputFileFullPath' already exists. Use -Force to overwrite."
                return
            } elseif (-not $Concise) {
                Write-Host "Force remux enabled, will overwrite existing file '$outputFileFullPath'."
            }
        }

        # --- Collect Stream Mapping Arguments ---
        $mapArgs = @()
        $inputLimitations = if ($containerLimitations.ContainsKey($inputExt)) { $containerLimitations[$inputExt] } else { @() }
        $outputLimitations = if ($containerLimitations.ContainsKey($OutputExt)) { $containerLimitations[$OutputExt] } else { @() }

        # Copy Video?
        if (-not ($inputLimitations -contains 'no_copy_video' -or $outputLimitations -contains 'no_copy_video')) {
            Write-Verbose "Mapping video streams (copying)."
            $mapArgs += '-map', '0:v:0', '-c:v', 'copy'
        } else {
            if (-not $Concise) { Write-Host "Mapping video streams (transcoding)." }
            $mapArgs += '-map', '0:v:0'
        }

        # Map Audio?
        if (-not ($inputLimitations -contains 'no_audio' -or $outputLimitations -contains 'no_audio')) {
            Write-Verbose "Mapping audio streams (copying)."
            $mapArgs += '-map', '0:a?', '-c:a', 'copy'
        } else {
            if (-not $Concise) { Write-Host "Skipping audio streams due to container limitations ($inputExt -> $OutputExt)." }
        }

        # Map Subtitles?
        if (-not ($inputLimitations -contains 'no_subs' -or $outputLimitations -contains 'no_subs')) {
            Write-Verbose "Mapping subtitle streams (copying)."
            $mapArgs += '-map', '0:s?', '-c:s', 'copy'
        } else {
            if (-not $Concise) { Write-Host "Skipping subtitle streams due to container limitations ($inputExt -> $OutputExt)." }
        }

        # Map Fonts (TTF)?
        if (-not ($inputLimitations -contains 'no_ttf' -or $outputLimitations -contains 'no_ttf')) {
            Write-Verbose "Mapping font streams (copying)."
            $mapArgs += '-map', '0:t?', '-c:t', 'copy'
        } else {
            if (-not $Concise) { Write-Host "Skipping font streams due to container limitations ($inputExt -> $OutputExt)." }
        }

        # Map Data?
        if (-not ($inputLimitations -contains 'no_data' -or $outputLimitations -contains 'no_data')) {
            Write-Verbose "Mapping data streams (copying)."
            $mapArgs += '-map', '0:d?', '-c:d', 'copy'
        } else {
            if (-not $Concise) { Write-Host "Skipping data streams due to container limitations ($inputExt -> $OutputExt)." }
        }

        # --- PassThru Mode: Return arguments instead of executing ---
        if ($PassThru) {
            Write-Verbose "PassThru enabled. Returning ffmpeg arguments as a single string."
            return $mapArgs
        }

        # Check if any map arguments were actually added (excluding the initial base args)
        # A bit simplistic check: if only base args + output file exist, likely nothing was mapped.
        if ($mapArgs.Count -le 0) { # Count base args (-v, warning, -stats, -y, -i, input) + output file = 7? Let's use a safer lower bound.
            # Refine check: Look for at least one '-map' argument
            if (-not ($mapArgs -contains '-map')) {
                Write-Error "No streams could be mapped for '$inputFileFullPath' based on the rules for '$OutputExt'. Skipping remux."
                return
            }
        }

        # Add output file path
        # --- Construct FFMPEG Command Arguments based on Container Compatibility ---
        $ffmpegArgs = @('-y') # Overwrite output without asking (already checked with -Force)
        if ($Concise) { # Logging level and progress
            $ffmpegArgs += '-v', 'fatal'
        } else {
            $ffmpegArgs += '-v', 'warning'
        }
        $ffmpegArgs += '-i', "$inputFileFullPath"
        $ffmpegArgs += $mapArgs
        $ffmpegArgs += "$outputFileFullPath"

        # --- Execute FFMPEG ---
        if (-not $Concise) { Write-Host "Starting ffmpeg remux command:`n$ffmpeg $($ffmpegArgs -join ' ')" }

        if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Remux to $outputFileFullPath")) {
            try {
                Write-Verbose "Running: $ffmpeg $($ffmpegArgs -join ' ')"
                & $ffmpeg @ffmpegArgs
                $exitCode = $LASTEXITCODE
                if (-not $Concise) { Write-Host "" }

                if ($exitCode -ne 0) {
                    Write-Error "ffmpeg process failed (Exit Code: $exitCode) while remuxing '$inputFileFullPath'."
                    $script:fatalErrorOccurred = $true
                    $script:ffmpegFailureCode = $exitCode
                    # Attempt to clean up potentially broken output file
                    if (Test-Path -LiteralPath $outputFileFullPath -PathType Leaf) {
                        Write-Warning "Attempting to remove potentially incomplete output file: $outputFileFullPath"
                        Remove-Item $outputFileFullPath -ErrorAction SilentlyContinue
                    }
                    return # Stop processing this file
                } else {
                    if (-not $Concise) { Write-Host "Successfully remuxed '$inputFileFullPath' to '$outputFileFullPath'" }
                    $script:anyRemuxPerformed = $true

                    # --- Delete Original File if Flag is Set and Remux Succeeded ---
                    if ($DeleteOriginalFlag) {
                        if (-not $Concise) { Write-Host "Deleting original file: '$inputFileFullPath'" }
                        if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Delete original file after successful remux")) {
                            try {
                                Remove-Item -LiteralPath $inputFileFullPath -Force -ErrorAction Stop
                                if (-not $Concise) { Write-Host "Successfully deleted original file: '$inputFileFullPath'" }
                            } catch {
                                Write-Warning "Failed to delete original file '$inputFileFullPath'. It might be in use or permissions denied. Error: $($_.Exception.Message)"
                            }
                        } else {
                            Write-Warning "Skipping deletion of '$inputFileFullPath' due to -WhatIf."
                        }
                    }
                }
            } catch {
                Write-Error "Error executing ffmpeg for remuxing '$inputFileFullPath': $($_.Exception.Message)"
                $script:fatalErrorOccurred = $true
                # Attempt cleanup
                if (Test-Path -LiteralPath $outputFileFullPath -PathType Leaf) {
                    Write-Warning "Attempting to remove potentially incomplete output file due to error: $outputFileFullPath"
                    Remove-Item $outputFileFullPath -ErrorAction SilentlyContinue
                }
                return # Stop processing this file
            }
        } else {
            Write-Warning "Skipping remux for '$inputFileFullPath' due to -WhatIf."
            $script:anyRemuxPerformed = $true
            return # Don't proceed with deletion if -WhatIf
        }
    } # End Function Convert-VideoFile

} # End Begin block

process {
    # Define common video extensions broadly
    $videoExtensions = @(".mkv", ".mp4", ".avi", ".mov", ".wmv", ".flv", ".ts", ".webm", ".mpg", ".mpeg", ".vob", ".mts", ".m2ts") # Add more as needed

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
                    Write-Host "Progress: $processedCount / $totalFiles - Remuxing '$($file.Name)'"
                    $result = Convert-VideoFile -FileInput $file `
                        -OutputExt $outputExt `
                        -ForceProcessing:$Force `
                        -DeleteOriginalFlag:$Delete `
                        -PassThru:$PassThru
                    if ($PassThru -and $result) {
                        $script:anyRemuxPerformed = $true
                        return $result
                    }
                }

            } elseif ($item -is [System.IO.FileInfo]) {
                # Check if the file extension is in our list (basic check)
                if ($videoExtensions -contains $item.Extension) {
                    Write-Host "Progress: 1 / 1 - Remuxing '$($item.Name)'"
                    $result = Convert-VideoFile -FileInput $item `
                        -OutputExt $outputExt `
                        -ForceProcessing:$Force `
                        -DeleteOriginalFlag:$Delete `
                        -PassThru:$PassThru
                    if ($PassThru -and $result) {
                        $script:anyRemuxPerformed = $true
                        return $result
                    }
                } else {
                    Write-Warning "Skipping file '$($item.FullName)' as its extension '$($item.Extension)' is not in the recognized list of video formats for remuxing."
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
    if (-not $Concise) { Write-Host "`nRemux script finished." }

    # Determine final exit code
    if ($script:fatalErrorOccurred) {
        if ($null -ne $script:ffmpegFailureCode) {
            Write-Verbose "Exiting with ffmpeg failure code: $script:ffmpegFailureCode."
            exit $script:ffmpegFailureCode
        } else {
            Write-Verbose "Exiting with code 1 (Generic Fatal Error)."
            exit 1
        }
    } elseif ($script:anyRemuxPerformed) {
        Write-Verbose "Exiting with code 0 (Success/Remux Attempted)."
        exit 0
    } else {
        Write-Verbose "Exiting with code -2 (No Remuxing Needed/Performed)."
        exit -2 # Use -2 to indicate nothing needed to be done (e.g., same container, skipped)
    }
} # End End block
