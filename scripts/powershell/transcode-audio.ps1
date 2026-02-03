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

.PARAMETER StreamInfoB64
Optional: Base64 encoded JSON string containing ffprobe output for the file.
If provided, the script skips running ffprobe itself to improve performance when called from a parent script.

.PARAMETER PassThru
Returns the ffmpeg command arguments instead of executing them. Useful for compiling commands for later execution.

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
    [string]$ConfigPath = '',

    [Parameter()]
    [string]$StreamInfoB64 = '',

    [Parameter()]
    [switch]$PassThru
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

    # --- Generic Helpers ---
    function ConvertFrom-JsonHash {
        param([Parameter(ValueFromPipeline = $true)][string]$json)
        if ($PSVersionTable.PSVersion.Major -ge 6) { return ($json | ConvertFrom-Json -AsHashtable) }
        else {
            if (-not ("System.Web.Script.Serialization.JavaScriptSerializer" -as [type])) { Add-Type -AssemblyName System.Web.Extensions }
            $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer; $serializer.MaxJsonLength = [int32]::MaxValue
            return $serializer.Deserialize($json, [System.Collections.Hashtable])
        }
    }

    function Get-ChannelCount {
        param([string]$layout)
        $channelMap = @{
            'mono'   = 1;
            'stereo' = 2;
            '5.1'    = 6;
            '6.1'    = 7;
            '7.1'    = 8
        }
        $lookupChannel = $layout.ToLowerInvariant()
        if ($channelMap.ContainsKey($lookupChannel)) { return $channelMap[$lookupChannel] }
        $outInt = 0
        if (-not [int]::TryParse($layout, [ref]$outInt)) {
            Write-Warning "Invalid Channels value '$layout'. It must be an integer or a known layout (e.g., '5.1', 'stereo'). Defaulting to 'auto'."
        }
        return $outInt
    }

    # --- Script Status Tracking ---
    $script:fatalErrorOccurred = $false
    $script:anyFileTranscoded = $false
    $script:ffmpegFailureCode = $null

    # --- Parameter Validation ---
    if ($Delete -and $Replace) { Write-Error "-Delete and -Replace parameters are mutually exclusive."; exit 1 }

    # --- Process Channels Parameter ---
    $ffmpegChannels = 0
    if (-not ([string]::IsNullOrWhiteSpace($Channels) -or $Channels -eq '0')) {
        $ffmpegChannels = Get-ChannelCount $Channels
    }
    if ($ffmpegChannels -gt 0) { Write-Verbose "Processed Channels parameter: '$Channels' -> $ffmpegChannels" }

    # --- Determine File Action ---
    $FileAction = 0; if ($Delete) { $FileAction = 1 }; if ($Replace) { $FileAction = 2 }
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
    if (-not $ffmpeg) { Write-Error "ffmpeg.exe could not be located."; $script:fatalErrorOccurred = $true; exit 1 }
    if (-not $ffprobe) { Write-Error "ffprobe.exe could not be located."; $script:fatalErrorOccurred = $true; exit 1 }
    if (-not $Concise) { Write-Host "Using FFMPEG: $ffmpeg"; Write-Host "Using FFPROBE: $ffprobe" }

    # --- Temporary File Suffix for Replace Mode ---
    $tempSuffix = ".tmp_transcode"

    # --- Function to Process a Single File ---
    function Convert-AudioTracks {
        param(
            [Parameter(Mandatory = $true)] [System.IO.FileInfo]$FileInput,
            [Parameter(Mandatory = $true)] [int]$CurrentFileAction,
            [Parameter(Mandatory = $true)] [string]$OutputSuffix,
            [Parameter()] [switch]$ForceProcessing,
            [Parameter()] [switch]$PassThru
        )
        $inputFileFullPath = $FileInput.FullName
        $inputPath = $FileInput.DirectoryName; $inputName = $FileInput.BaseName; $inputExt = $FileInput.Extension

        if (-not $Concise) {
            Write-Host "`n-----------------------------------------------------"
            Write-Host "Processing Audio for: $inputFileFullPath"
            Write-Host "Target Codec: $Codec, Bitrate: $($Bitrate | ForEach-Object {if ([string]::IsNullOrWhiteSpace($_)) {'auto'} else {$_}}), Channels: $(if ([string]::IsNullOrWhiteSpace($Channels) -or $Channels -eq '0') {'auto'} else {$Channels})"
            Write-Host "Action: $CurrentFileAction (0=Suffix, 1=Delete, 2=Replace) Force: $ForceProcessing"
            if ($CurrentFileAction -ne 2) { Write-Host "Suffix: $OutputSuffix" }
            Write-Host "-----------------------------------------------------`n"
        }

        # --- Determine Output Filename(s) ---
        $finalOutputFile = ''; $ffmpegTargetFile = ''
        if ($CurrentFileAction -eq 2) { # Replace mode
            $ffmpegTargetFile = Join-Path $inputPath ($inputName + $tempSuffix + $inputExt)
            $finalOutputFile = $inputFileFullPath
        } else { # Suffix or Delete mode
            $ffmpegTargetFile = Join-Path $inputPath ($inputName + $OutputSuffix + $inputExt)
            $finalOutputFile = $ffmpegTargetFile
        }

        if ($CurrentFileAction -ne 2 -and (Test-Path -LiteralPath $finalOutputFile) -and (-not $ForceProcessing)) {
            Write-Warning "Skipping transcode, output file '$finalOutputFile' already exists. Use -Force to overwrite."
            return
        }

        # --- Get Stream Info (Probe or B64) ---
        $probeData = $null
        try {
            if (-not [string]::IsNullOrEmpty($StreamInfoB64)) {
                Write-Verbose "Using provided Base64 stream info."
                try {
                    $jsonBytes = [Convert]::FromBase64String($StreamInfoB64)
                    $jsonStr = [Text.Encoding]::UTF8.GetString($jsonBytes)
                    $probeData = $jsonStr | ConvertFrom-JsonHash
                } catch { Write-Warning "Failed to decode provided stream info. Falling back to local ffprobe." }
            }

            if ($null -eq $probeData) {
                if (-not $Concise) { Write-Host "Probing streams..." }
                $ffprobeArgs = @('-v', 'fatal', '-show_streams', '-print_format', 'json', "$inputFileFullPath")
                Write-Verbose "Running: $ffprobe $($ffprobeArgs -join ' ')"
                $jsonOutput = & $ffprobe @ffprobeArgs 2>&1
                if ($LASTEXITCODE -ne 0) { Write-Warning "ffprobe failed."; return }
                $probeData = [string]$jsonOutput | ConvertFrom-JsonHash
            }
        } catch { Write-Warning "Error getting stream info: $($_.Exception.Message)"; return }

        if (-not $probeData -or -not $probeData.streams) { Write-Warning "No stream info available."; return }

        # --- Analyze Audio Streams ---
        $audioStreams = $probeData.streams | Where-Object { $_.codec_type -eq 'audio' }
        if ($audioStreams.Count -eq 0) {
            if (-not $Concise) { Write-Host "No audio streams found. Skipping file." }; if (-not $PassThru) { return }
        }

        # Check if already in target codec
        $streamsToConvert = $audioStreams | Where-Object { $_.codec_name -ne $Codec.ToLower() }
        if ($streamsToConvert.Count -eq 0) {
            if (-not $Concise) { Write-Host "All audio streams are already in '$Codec' format. No transcoding needed. Skipping." }
            if (-not $PassThru) { return }
        }

        # --- Construct FFMPEG Command ---
        # Map all streams, copy video/subs by default
        $ffmpegArgs = @('-map', '0', '-c:v', 'copy', '-c:s', 'copy', '-strict', '-2')
        
        # Build per-stream audio arguments
        $audioIdx = 0
        foreach ($stream in $audioStreams) {
            $ffmpegArgs += "-c:a:$audioIdx", $Codec

            if (-not [string]::IsNullOrWhiteSpace($Bitrate)) { $ffmpegArgs += "-b:a:$audioIdx", $Bitrate }
            if ($ffmpegChannels -gt 0) { $ffmpegArgs += "-ac:a:$audioIdx", $ffmpegChannels } else { $ffmpegArgs += "-ac:a:$audioIdx", "$(Get-ChannelCount $stream.channels)" }

            $audioIdx++
        }

        if ($PassThru) { return $ffmpegArgs }

        # --- Construct Full Command and Execute ---
        $fullFfmpegArgs = @('-y', '-stats')
        if ($Concise) { $fullFfmpegArgs += '-v', 'fatal' } else { $fullFfmpegArgs += '-v', 'warning' }
        $fullFfmpegArgs += '-i', "$inputFileFullPath"
        $fullFfmpegArgs += $ffmpegArgs
        $fullFfmpegArgs += "$ffmpegTargetFile"

        if ($CurrentFileAction -eq 2 -and (Test-Path -LiteralPath $ffmpegTargetFile) -and (-not $ForceProcessing)) {
            Write-Warning "Temporary file '$ffmpegTargetFile' already exists. Use -Force to overwrite."
            return
        }

        if (-not $Concise) { Write-Host "Starting ffmpeg transcode..." }

        if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Transcode audio to $Codec")) {
            $success = $false
            try {
                Write-Verbose "Command: $ffmpeg $($fullFfmpegArgs -join ' ')"
                & $ffmpeg @fullFfmpegArgs
                if (-not $Concise) { Write-Host "" }
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "ffmpeg failed (Exit Code: $LASTEXITCODE)."
                    $script:fatalErrorOccurred = $true; $script:ffmpegFailureCode = $LASTEXITCODE
                } else {
                    $success = $true; $script:anyFileTranscoded = $true
                }
            } catch { Write-Error "Error executing ffmpeg: $($_.Exception.Message)"; $script:fatalErrorOccurred = $true }

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
        }
    } # End Function Convert-AudioTracks
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
                    $result = Convert-AudioTracks -FileInput $file -CurrentFileAction $FileAction -OutputSuffix $Suffix -ForceProcessing:$Force -PassThru:$PassThru
                    if ($PassThru -and $result) {
                        $script:anyFileTranscoded = $true
                        return $result
                        exit 0
                    }
                }
            } elseif ($item -is [System.IO.FileInfo]) {
                if ($videoExtensions -contains $item.Extension) {
                    Write-Host "Progress: 1 / 1 - Transcoding audio for '$($item.Name)'"
                    $result = Convert-AudioTracks -FileInput $item -CurrentFileAction $FileAction -OutputSuffix $Suffix -ForceProcessing:$Force -PassThru:$PassThru
                    if ($PassThru -and $result) {
                        $script:anyFileTranscoded = $true
                        return $result
                        exit 0
                    }
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
} # End End block
