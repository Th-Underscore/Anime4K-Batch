<#
.SYNOPSIS
Batch Audio Transcoder - Transcodes audio streams in video files to a specified format (e.g., AC3) using ffmpeg.

.DESCRIPTION
Scans video files or directories and transcodes all audio streams to a specified codec, such as AC3.
All video, subtitle, and other data streams are copied without modification.
Can either create a new file with a suffix or replace the original file.
The script will skip files where all audio streams already match the target codec.

.PARAMETER Path
One or more input video file paths or directory paths to process.

.PARAMETER Codec
The target audio codec for transcoding. Examples: 'ac3', 'aac', 'eac3', 'dts'. Default: 'ac3'.

.PARAMETER Bitrate
The target audio bitrate (e.g., '640k', '384k'). If not specified, ffmpeg's default for the codec will be used.

.PARAMETER Channels
The number of audio channels for the output (e.g., 6 or '5.1' for 5.1 surround). If not specified, channels will not be changed.

.PARAMETER Suffix
Suffix for the output filename when not using -Replace. Default: '_transcoded'. Ignored if -Replace is used.

.PARAMETER Recurse
Process folders recursively.

.PARAMETER Force
Force overwrite existing output files. Also forces processing even if the target file exists during the -Replace operation's temporary phase.

.PARAMETER Delete
Delete original file after successful processing. Mutually exclusive with -Replace.

.PARAMETER Replace
Replace the original file with the processed version. Mutually exclusive with -Delete. Creates a temporary file during processing.

.PARAMETER FfmpegPath
Path to ffmpeg executable. Auto-detected if not provided.

.PARAMETER FfprobePath
Path to ffprobe executable. Auto-detected if not provided.

.PARAMETER Concise
Concise output (only progress shown).

.EXAMPLE
.\transcode-audio.ps1 -Path "C:\videos\movie.mkv" -Codec ac3 -Bitrate 640k -Channels 6 -Replace

.EXAMPLE
.\transcode-audio.ps1 -Path "C:\videos\series_folder" -Recurse -Suffix "_ac3" -Delete

.NOTES
Requires ffmpeg and ffprobe.
The script remuxes the entire file, copying all video and subtitle streams. Only audio is re-encoded.
If a file's audio is already in the target format, it is skipped.
The -Replace operation is generally safer as it avoids leaving partial files if interrupted, but uses temporary disk space.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')] # Possible file modification/deletion
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
    [string[]]$Path,

    [Parameter()]
    [string]$Codec = 'ac3',

    [Parameter()]
    [string]$Bitrate = '',

    [Parameter()]
    [string]$Channels = '0', # Can be a number (e.g., 6) or layout (e.g., '5.1'). '0' or empty means "not specified".

    [Parameter()]
    [string]$Suffix = '_a-transcoded', # Used only if -Replace is not specified

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
        $effectiveConfigPath = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\config\$($MyInvocation.MyCommand.Name -replace '\.ps1$', '-config.json')")
        Write-Verbose "No -ConfigPath specified, attempting default: $effectiveConfigPath"
    }
    if (Test-Path -LiteralPath $effectiveConfigPath -PathType Leaf) {
        Write-Verbose "Loading configuration from: $effectiveConfigPath"
        try {
            $jsonContent = (Get-Content -LiteralPath $effectiveConfigPath -Raw) -replace '//.*'
            $config = $jsonContent | ConvertFrom-Json -ErrorAction Stop
            Write-Verbose "Configuration loaded successfully."
            foreach ($key in $config.PSObject.Properties.Name) {
                $paramValue = $config.$key; $keyLower = $key.ToLowerInvariant()
                if ($keyLower -eq 'verbose') { if ($PSBoundParameters.ContainsKey('Verbose') -eq $false -and $paramValue -is [bool] -and $paramValue) { $VerbosePreference = 'Continue'; Write-Verbose "Setting `$VerbosePreference = 'Continue' based on config." } }
                elseif ($keyLower -eq 'debug') { if ($PSBoundParameters.ContainsKey('Debug') -eq $false -and $paramValue -is [bool] -and $paramValue) { $DebugPreference = 'Continue'; Write-Verbose "Setting `$DebugPreference = 'Continue' based on config." } }
                elseif ($PSBoundParameters.ContainsKey($key) -eq $false -and $MyInvocation.MyCommand.Parameters.ContainsKey($key)) { Write-Verbose "Overriding `$$key with value from config: '$paramValue'"; Set-Variable -Name $key -Value $paramValue -Scope Script; }
            }
        } catch { Write-Warning "Failed to load or parse configuration file '$effectiveConfigPath': $($_.Exception.Message)" }
    } else { if (-not [string]::IsNullOrEmpty($ConfigPath)) { Write-Warning "Specified configuration file not found at '$ConfigPath'." } else { Write-Verbose "Default configuration file '$effectiveConfigPath' not found." } }

    # --- Script Status Tracking ---
    $script:fatalErrorOccurred = $false
    $script:anyFileTranscoded = $false
    $script:ffmpegFailureCode = $null

    # --- Parameter Validation ---
    if ($Delete -and $Replace) { Write-Error "-Delete and -Replace parameters are mutually exclusive."; exit 1 }

    # --- Process Channels Parameter ---
    $ffmpegChannels = 0
    if (-not ([string]::IsNullOrWhiteSpace($Channels) -or $Channels -eq '0')) {
        $channelMap = @{
            'mono'   = 1;
            'stereo' = 2;
            '5.1'    = 6;
            '6.1'    = 7;
            '7.1'    = 8
        }
        $lookupChannel = $Channels.ToLowerInvariant()
        if ($channelMap.ContainsKey($lookupChannel)) {
            $ffmpegChannels = $channelMap[$lookupChannel]
        } else {
            if ([int]::TryParse($Channels, [ref]$outInt)) {
                $ffmpegChannels = $outInt
            } else {
                Write-Warning "Invalid Channels value '$Channels'. It must be an integer or a known layout (e.g., '5.1', 'stereo'). Defaulting to 'auto'."
                $ffmpegChannels = 0
            }
        }
    }
    if ($ffmpegChannels -gt 0) { Write-Verbose "Processed Channels parameter: '$Channels' -> $ffmpegChannels" }

    # --- Determine File Action ---
    $FileAction = 0; if ($Delete) { $FileAction = 1 }; if ($Replace) { $FileAction = 2 }
    Write-Verbose "File Action Mode: $FileAction (0=Suffix, 1=Delete, 2=Replace)"

    # --- Helper Function to Find Executables ---
    function Find-Executable { param([string]$Name, [string]$ExplicitPath, [switch]$DisableWhere)
        Write-Verbose "Searching for $Name..."; if (-not [string]::IsNullOrEmpty($ExplicitPath)) { if (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) { Write-Verbose "Using explicit path: $ExplicitPath"; return (Get-Item -LiteralPath $ExplicitPath).FullName } else { Write-Warning "Explicit path for $Name not found: $ExplicitPath" } }
        $scriptDir = $PSScriptRoot; $localPath = Join-Path $scriptDir "$Name.exe"; if (Test-Path -LiteralPath $localPath) { Write-Verbose "Found $Name in script directory: $localPath"; return $localPath }
        $parentDir = Split-Path -LiteralPath $scriptDir; $parentLocalPath = Join-Path $parentDir "$Name.exe"; if (Test-Path -LiteralPath $parentLocalPath) { Write-Verbose "Found $Name in parent directory: $parentLocalPath"; return $parentLocalPath }
        if (-not $DisableWhere) { try { $foundPath = (Get-Command $Name -EA SilentlyContinue).Source; if ($foundPath) { Write-Verbose "Found $Name via Get-Command: $foundPath"; return $foundPath } } catch { }
            try { $whereOutput = where.exe $Name 2>&1; if ($LASTEXITCODE -eq 0 -and $whereOutput) { $foundPath = $whereOutput | Select-Object -First 1; Write-Verbose "Found $Name via where.exe: $foundPath"; return $foundPath } } catch { }
        }
        if ($Name -in ('ffmpeg', 'ffprobe')) { Write-Error "$Name could not be located."; return $null } else { Write-Warning "$Name could not be located."; return $null }
    }

    # --- Locate FFMPEG and FFPROBE ---
    $ffmpeg = Find-Executable -Name 'ffmpeg' -ExplicitPath $FfmpegPath -DisableWhere:$DisableWhereSearch
    $ffprobe = Find-Executable -Name 'ffprobe' -ExplicitPath $FfprobePath -DisableWhere:$DisableWhereSearch
    if (-not $ffmpeg) { Write-Error "ffmpeg.exe could not be located."; $script:fatalErrorOccurred = $true; exit 1 }
    if (-not $ffprobe) { Write-Error "ffprobe.exe could not be located."; $script:fatalErrorOccurred = $true; exit 1 }
    if (-not $Concise) { Write-Host "Using FFMPEG: $ffmpeg"; Write-Host "Using FFPROBE: $ffprobe" }

    # --- Temporary File Suffix for Replace Mode ---
    $tempSuffix = ".tmp_transcode"

    # --- Function to Process a Single File ---
    function Transcode-AudioLogic {
        param(
            [Parameter(Mandatory = $true)] [System.IO.FileInfo]$FileInput,
            [Parameter(Mandatory = $true)] [int]$CurrentFileAction,
            [Parameter(Mandatory = $true)] [string]$OutputSuffix,
            [Parameter()] [switch]$ForceProcessing
        )
        $inputFileFullPath = $FileInput.FullName
        $inputPath = $FileInput.DirectoryName; $inputName = $FileInput.BaseName; $inputExt = $FileInput.Extension

        if (-not $Concise) {
            Write-Host "`n-----------------------------------------------------"
            Write-Host "Processing Audio for: $inputFileFullPath"
            Write-Host "Target Codec: $Codec, Bitrate: $($Bitrate | ForEach-Object {if ([string]::IsNullOrWhiteSpace($_)) {'auto'} else {$_}}), Channels: $(if ([string]::IsNullOrWhiteSpace($Channels) -or $Channels -eq '0') {'auto'} else {$Channels})"
            Write-Host "Action: $CurrentFileAction (0=Suffix, 1=Delete, 2=Replace)"
            if ($CurrentFileAction -ne 2) { Write-Host "Suffix: $OutputSuffix" }
            Write-Host "Force: $ForceProcessing"
            Write-Host "-----------------------------------------------------`n"
        }

        # --- Determine Output Filename(s) ---
        $finalOutputFile = ''; $ffmpegTargetFile = ''
        if ($CurrentFileAction -eq 2) { # Replace mode
            $ffmpegTargetFile = Join-Path $inputPath ($inputName + $tempSuffix + $inputExt)
            $finalOutputFile = $inputFileFullPath
            Write-Verbose "Action: Replace original. Temp file: '$ffmpegTargetFile'"
        } else { # Suffix or Delete mode
            $ffmpegTargetFile = Join-Path $inputPath ($inputName + $OutputSuffix + $inputExt)
            $finalOutputFile = $ffmpegTargetFile
            Write-Verbose "Action: Create new file. Target: '$ffmpegTargetFile'"
        }

        # --- Check if FINAL target exists ---
        if ($CurrentFileAction -ne 2 -and (Test-Path -LiteralPath $finalOutputFile) -and (-not $ForceProcessing)) {
            Write-Warning "Skipping transcode, output file '$finalOutputFile' already exists. Use -Force to overwrite."
            return
        }

        # --- Check if audio is already in the target format to avoid needless work ---
        if (-not $Concise) { Write-Host "Probing audio streams to check current codecs..." }
        try {
            $ffprobeArgs = @('-v', 'error', '-select_streams', 'a', '-show_entries', 'stream=codec_name', '-of', 'json', "`"$inputFileFullPath`"")
            Write-Verbose "Running: $ffprobe $($ffprobeArgs -join ' ')"
            $jsonOutput = & $ffprobe @ffprobeArgs
            if ($LASTEXITCODE -ne 0) { Write-Warning "ffprobe failed for '$inputFileFullPath'. Skipping codec check."; throw "ffprobe failed" }

            $probeData = $jsonOutput | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($probeData.streams.Count -eq 0) { if (-not $Concise) { Write-Host "No audio streams found. Skipping file."; return } }
            
            $streamsToConvert = $probeData.streams | Where-Object { $_.codec_name -ne $Codec.ToLower() }
            if ($streamsToConvert.Count -eq 0) {
                if (-not $Concise) { Write-Host "All audio streams are already in '$Codec' format. No transcoding needed. Skipping." }
                return
            }
            if (-not $Concise) { Write-Host "Found $($streamsToConvert.Count) audio stream(s) that need transcoding." }
        } catch { Write-Warning "Could not determine audio codecs for '$inputFileFullPath'. Proceeding with transcode attempt. Error: $($_.Exception.Message)" }

        # --- Construct Full FFMPEG Command ---
        $ffmpegArgs = @(
            '-hide_banner', '-v', 'warning', '-stats',
            '-y', # Overwrite temp/final file
            '-i', "`"$inputFileFullPath`"",
            '-map', '0',         # Map all streams from input 0
            '-c:v', 'copy',      # Copy video stream(s)
            '-c:s', 'copy',      # Copy subtitle stream(s)
            '-c:a', $Codec       # Transcode audio stream(s) to target codec
        )
        if (-not [string]::IsNullOrWhiteSpace($Bitrate)) { $ffmpegArgs += '-b:a', $Bitrate }
        if ($ffmpegChannels -gt 0) { $ffmpegArgs += '-ac', $ffmpegChannels }
        $ffmpegArgs += "`"$ffmpegTargetFile`""

        # --- Check Temporary File in Replace Mode ---
        if ($CurrentFileAction -eq 2 -and (Test-Path -LiteralPath $ffmpegTargetFile) -and (-not $ForceProcessing)) {
            Write-Warning "Temporary file '$ffmpegTargetFile' already exists. Use -Force to overwrite it."
            return
        }

        # --- Execute FFMPEG ---
        if (-not $Concise) { Write-Host "Starting ffmpeg transcode command:`n$ffmpeg $($ffmpegArgs -join ' ')" }

        if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Transcode audio to $Codec (Output: $ffmpegTargetFile)")) {
            $success = $false
            try {
                & $ffmpeg @ffmpegArgs
                if (-not $Concise) { Write-Host "" }
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "ffmpeg process failed (Exit Code: $LASTEXITCODE) for '$inputFileFullPath'."
                    $script:fatalErrorOccurred = $true; $script:ffmpegFailureCode = $LASTEXITCODE
                } else {
                    if (-not $Concise) { Write-Host "Successfully transcoded audio into '$ffmpegTargetFile'." }
                    $success = $true; $script:anyFileTranscoded = $true
                }
            } catch { Write-Error "Error executing ffmpeg for '$inputFileFullPath': $($_.Exception.Message)"; $script:fatalErrorOccurred = $true }

            # --- Post-processing File Actions ---
            if ($success) {
                if ($CurrentFileAction -eq 1) { # Delete Original
                    if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Delete original")) {
                        try { Remove-Item -LiteralPath $inputFileFullPath -Force -ErrorAction Stop; if (-not $Concise) { Write-Host "Successfully deleted original." } }
                        catch { Write-Warning "Failed to delete original '$inputFileFullPath': $($_.Exception.Message)" }
                    } else { Write-Warning "Skipping deletion of original due to -WhatIf." }
                } elseif ($CurrentFileAction -eq 2) { # Replace Original
                    if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Replace with processed file")) {
                        try { Move-Item -LiteralPath $ffmpegTargetFile -Destination $inputFileFullPath -Force -ErrorAction Stop; if (-not $Concise) { Write-Host "Successfully replaced original." } }
                        catch { Write-Error "Failed to replace original file. Temp file '$ffmpegTargetFile' may still exist. Error: $($_.Exception.Message)" }
                    } else { Write-Warning "Skipping replacement of original due to -WhatIf. Temp file '$ffmpegTargetFile' may remain." }
                }
            } else { # ffmpeg failed
                if (Test-Path -LiteralPath $ffmpegTargetFile) {
                    Write-Warning "Attempting to remove failed/incomplete output file: $ffmpegTargetFile"
                    Remove-Item -LiteralPath $ffmpegTargetFile -Force -ErrorAction SilentlyContinue
                }
            }
        } else { Write-Warning "Skipping ffmpeg execution due to -WhatIf."; $script:anyFileTranscoded = $true }
    } # End Function Transcode-AudioLogic
} # End Begin block

process {
    $videoExtensions = @(".mkv", ".mp4", ".avi", ".mov", ".wmv", ".flv", ".ts", ".webm", ".mpg", ".mpeg", ".m2ts")

    foreach ($itemPath in $Path) {
        if ($script:fatalErrorOccurred) { Write-Warning "A fatal error occurred. Stopping further processing."; break }
        try {
            $item = Get-Item -LiteralPath $itemPath -ErrorAction Stop
            if ($item -is [System.IO.DirectoryInfo]) {
                if (-not $Concise) { Write-Host "`nProcessing directory: $($item.FullName) (Recursive: $Recurse)" }
                $allFiles = Get-ChildItem -LiteralPath $item.FullName -Recurse:$Recurse | Where-Object { $videoExtensions -contains $_.Extension }
                $filesToProcess = $allFiles | Where-Object { ($FileAction -ne 2 -or $_.Name -notlike "*$tempSuffix*") -and ($FileAction -eq 2 -or $Suffix -eq '' -or $_.BaseName -notlike "*$Suffix") }
                $totalFiles = $filesToProcess.Count; $processedCount = 0
                if ($totalFiles -eq 0) { if (-not $Concise) { Write-Host "No supported video files found." }; continue }
                if (-not $Concise) { Write-Host "Found $totalFiles video file(s) to process." }

                foreach ($file in $filesToProcess) {
                    $processedCount++
                    Write-Host "Progress: $processedCount / $totalFiles - Transcoding audio for '$($file.Name)'"
                    Transcode-AudioLogic -FileInput $file -CurrentFileAction $FileAction -OutputSuffix $Suffix -ForceProcessing:$Force
                }
            } elseif ($item -is [System.IO.FileInfo]) {
                if ($videoExtensions -contains $item.Extension) {
                    Write-Host "Progress: 1 / 1 - Transcoding audio for '$($item.Name)'"
                    Transcode-AudioLogic -FileInput $item -CurrentFileAction $FileAction -OutputSuffix $Suffix -ForceProcessing:$Force
                } else { Write-Warning "Skipping file '$($item.FullName)', unsupported extension." }
            } else { Write-Warning "Path '$itemPath' is not a file or directory. Skipping." }
        } catch { Write-Error "Error processing path '$itemPath': $($_.Exception.Message)"; $script:fatalErrorOccurred = $true }
    }
} # End Process block

end {
    if (-not $Concise) { Write-Host "`nAudio transcoding script finished." }

    if ($script:fatalErrorOccurred) {
        if ($null -ne $script:ffmpegFailureCode) { exit $script:ffmpegFailureCode }
        else { exit 1 }
    } elseif ($script:anyFileTranscoded) {
        exit 0
    } else {
        exit -2 # Nothing needed to be done
    }
}