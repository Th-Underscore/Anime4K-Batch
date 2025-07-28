<#
.SYNOPSIS
Batch GLSL Transcoder - Replicates the core ffmpeg transcoding logic of the Anime4K-GUI project.

.DESCRIPTION
Processes video files or directories, applying a GLSL shader for upscaling/filtering using ffmpeg with libplacebo.
Supports various encoders, hardware acceleration, subtitle extraction, and default audio track setting.

.PARAMETER Path
One or more input file paths or directory paths to process.

.PARAMETER TargetResolutionW
Target output width. Default: 3840.

.PARAMETER TargetResolutionH
Target output height. Default: 2160.

.PARAMETER ShaderFile
Shader filename located in the ShaderBasePath. Default: 'Anime4K_ModeA_A-fast.glsl'.

.PARAMETER ShaderBasePath
Path to the shaders folder. Default: Script's 'shaders' subdirectory.

.PARAMETER EncoderProfile
Encoder profile (e.g., 'nvidia_h265', 'intel_h265', 'cpu_av1'). Default: 'nvidia_h265'.
Options: cpu_h264, cpu_h265, cpu_av1, nvidia_h264, nvidia_h265, nvidia_av1, amd_h264, amd_h265, amd_av1, intel_h264, intel_h265, intel_av1, vulkan_h264, vulkan_h265, h264_vaapi, hevc_vaapi, av1_vaapi. Any other value is treated as a custom codec name.

.PARAMETER CQP
Constant Quantization Parameter (0-51, lower is better). Default: 24.

.PARAMETER Container
Output container format (e.g., 'mkv', 'mp4'). Default: 'mkv'.

.PARAMETER Suffix
Suffix to append to output filenames. Default: '_upscaled'.

.PARAMETER SubsLangPriority
Comma-separated subtitle language priority list for -SetSubsPriority (e.g., "jpn,chi,kor,eng").

.PARAMETER SubsTitlePriority
Comma-separated subtitle title priority list for -SetSubsPriority (e.g., "Full,Signs").

.PARAMETER SubFormat
Subtitle filename format for -ExtractSubs. Default: 'SOURCE.lang.title.dispo'.
Placeholders: SOURCE (base filename), lang (language code), title (stream title/tag), dispo (disposition i.e. 'default', 'forced').

.PARAMETER AudioLangPriority
Comma-separated audio language priority list for -SetAudioPriority (e.g., "jpn,eng"). Default: ''.

.PARAMETER AudioTitlePriority
Comma-separated audio title priority list for -SetAudioPriority (e.g., "Commentary,Surround").
.PARAMETER AudioCodec
Audio codec for transcoding (e.g., 'aac', 'ac3', 'flac'). Defaults to the original value (copied).

.PARAMETER AudioBitrate
Audio bitrate for transcoding (e.g., '192k', '256k'). Defaults to the original value. Only applies if AudioCodec is specified.

.PARAMETER AudioChannels
Number of audio channels (e.g., '2' for stereo, '6' or '5.1' for 5.1). Defaults to the original value. Only applies if AudioCodec is specified.

.PARAMETER Recurse
Process folders recursively.

.PARAMETER Force
Force overwrite existing output files.

.PARAMETER SetSubsPriority
Set default subtitle track on the *input* file using set-subs-priority.ps1 before transcoding. This modifies the source file in-place.

.PARAMETER ExtractSubs
Extract subtitles from the *input* file using extract-subs.ps1 before transcoding. Accounts for set sub priority.

.PARAMETER SetAudioPriority
Set default audio track on the *output* file using set-audio-priority.ps1 after transcoding.

.PARAMETER Delete
Delete original file after successful transcode (USE WITH CAUTION!).


.PARAMETER FfmpegPath
Path to ffmpeg executable. Auto-detected if not provided.

.PARAMETER FfprobePath
Path to ffprobe executable. Auto-detected if not provided.

.PARAMETER DisableWhereSearch
Disable searching for ffmpeg/ffprobe in PATH using 'where.exe' or 'Get-Command'.


.PARAMETER Concise
Concise output (only progress shown).

.PARAMETER ConfigPath
Path to the config.json file. Default: `glsl-transcode-config.json`. Anime4K-Batch default: 'config.json' (script's root directory).


.EXAMPLE
.\glsl-transcode.ps1 -Path "C:\videos\input.mkv" -TargetResolutionW 1920 -TargetResolutionH 1080 -EncoderProfile cpu_h265 -CQP 28

.EXAMPLE
.\glsl-transcode.ps1 -Path "C:\videos\series_folder" -Recurse -ExtractSubs -SetAudioPriority -AudioLangPriority "jpn,eng" -Delete

.NOTES
Requires ffmpeg and ffprobe. Hardware acceleration requires appropriate drivers and compatible hardware.
Ensure the specified shader file exists in the ShaderBasePath.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')] # Possible file modification/deletion
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
    [string[]]$Path,

    [Parameter()]
    [int]$TargetResolutionW = 3840,

    [Parameter()]
    [int]$TargetResolutionH = 2160,

    [Parameter()]
    [string]$ShaderFile = 'Anime4K_ModeA_A-fast.glsl',

    [Parameter()]
    [string]$ShaderBasePath = '', # Default assigned in begin block

    [Parameter()]
    [string]$EncoderProfile = 'nvidia_h265',

    [Parameter()]
    [ValidateRange(-1, 51)]
    [int]$CQP = 24,

    [Parameter()]
    [ValidateSet('mkv', 'mp4', 'avi', 'mov', 'gif')] # Add more if needed
    [string]$Container = 'mkv',

    [Parameter()]
    [string]$Suffix = '_upscaled',

    [Parameter()]
    [string]$SubFormat = 'SOURCE.lang.title.dispo', # Default for Jellyfin

    [Parameter()]
    [string]$AudioLangPriority = '',

    [Parameter()]
    [string]$AudioTitlePriority = '',

    [Parameter()]
    [string]$AudioCodec = '',

    [Parameter()]
    [string]$AudioBitrate = '',

    [Parameter()]
    [string]$AudioChannels = '',

    [Parameter()]
    [switch]$Recurse,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$ExtractSubs,

    [Parameter()]
    [switch]$SetAudioPriority,

    [Parameter()]
    [switch]$SetSubsPriority,

    [Parameter()]
    [string]$SubsLangPriority = '',

    [Parameter()]
    [string]$SubsTitlePriority = '',

    [Parameter()]
    [switch]$Delete,

    [Parameter()]
    [string]$FfmpegPath = '',

    [Parameter()]
    [string]$FfprobePath = '',

    [Parameter()]
    [switch]$DisableWhereSearch,

    [Parameter()]
    [switch]$Concise,

    # Internal parameter for CPU threads, might expose later
    [int]$CpuThreads = 0,

    [Parameter()]
    [string]$ConfigPath = ''
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

    Write-Verbose "Script Root: $PSScriptRoot"
    Write-Verbose "Concise Execution: $Concise"
    Write-Verbose "ShaderBasePath: $ShaderBasePath"
    # --- Assign Default ShaderBasePath if not provided ---
    if ([string]::IsNullOrEmpty($ShaderBasePath)) {
        if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
            $ShaderBasePath = Join-Path (Split-Path -LiteralPath (Split-Path -LiteralPath $PSScriptRoot)) 'shaders'
            Write-Verbose "Using default ShaderBasePath: $ShaderBasePath"
        } else {
            # Fallback if PSScriptRoot is somehow still empty (e.g., running selection in ISE)
            $ShaderBasePath = Join-Path (Get-Location) 'shaders'
            Write-Warning "PSScriptRoot was empty. Using current location for default ShaderBasePath: $ShaderBasePath"
        }
    } else {
        Write-Verbose "Using user-provided ShaderBasePath: $ShaderBasePath"
    }


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
        Write-Error "ffmpeg.exe not found. Please provide the path using -FfmpegPath or ensure it's in the script directory or PATH."
        exit 1
    }
    if (-not $ffprobe) {
        Write-Error "ffprobe.exe not found. Please provide the path using -FfprobePath or ensure it's in the script directory or PATH."
        exit 1
    }
    Write-Host "Using FFMPEG: $ffmpeg"
    Write-Host "Using FFPROBE: $ffprobe"

    # --- Validate Shader Path ---
    $fullShaderPath = Join-Path $ShaderBasePath $ShaderFile
    if (-not (Test-Path -LiteralPath $fullShaderPath -PathType Leaf)) {
        Write-Error "Shader file not found: $fullShaderPath"
        exit 1
    }
    Write-Host "Using Shader: $fullShaderPath"

    # --- Determine Encoder and HWAccel Params ---
    $videoCodec = ''
    $hwAccelParams = @()
    $presetParam = ''
    $threadParam = ''

    switch ($EncoderProfile.ToLower()) {
        'cpu_h264' {
            $videoCodec = 'libx264'
            $presetParam = '-preset slow'
            if ($CpuThreads -ne 0) { $threadParam = "-threads $CpuThreads" }
        }
        'cpu_h265' {
            $videoCodec = 'libx265'
            $presetParam = '-preset slow'
            if ($CpuThreads -ne 0) { $threadParam = "-x265-params pools=$CpuThreads" }
        }
        'cpu_av1' {
            $videoCodec = 'libsvtav1'
            # AV1 uses preset differently
            if ($CpuThreads -ne 0) { $threadParam = "-svtav1-params pin=$CpuThreads" }
        }
        'nvidia_h264' {
            $videoCodec = 'h264_nvenc'
            $hwAccelParams = '-hwaccel_device', 'cuda', '-hwaccel_output_format', 'cuda'
            $presetParam = '-preset p7 -tune hq'
        }
        'nvidia_h265' {
            $videoCodec = 'hevc_nvenc'
            $hwAccelParams = '-hwaccel_device', 'cuda', '-hwaccel_output_format', 'cuda'
            $presetParam = '-preset p7 -tune hq -tier high'
        }
        'nvidia_av1' {
            $videoCodec = 'av1_nvenc'
            $hwAccelParams = '-hwaccel_device', 'cuda', '-hwaccel_output_format', 'cuda'
            $presetParam = '-preset p7 -tune hq'
        }
        'amd_h264' {
            $videoCodec = 'h264_amf'
            $hwAccelParams = '-hwaccel_device', 'opencl', '-hwaccel_output_format', 'opencl'
            $presetParam = '-quality quality'
        }
        'amd_h265' {
            $videoCodec = 'hevc_amf'
            $hwAccelParams = '-hwaccel_device', 'opencl', '-hwaccel_output_format', 'opencl'
            $presetParam = '-quality quality'
        }
        'amd_av1' {
            $videoCodec = 'av1_amf'
            $hwAccelParams = '-hwaccel_device', 'opencl', '-hwaccel_output_format', 'opencl'
            $presetParam = '-quality quality'
        }
        'intel_h264' {
            $videoCodec = 'h264_qsv'
            $hwAccelParams = '-hwaccel', 'qsv', '-hwaccel_output_format', 'qsv'
            $presetParam = '-preset slow'
        }
        'intel_h265' {
            $videoCodec = 'hevc_qsv'
            $hwAccelParams = '-hwaccel', 'qsv', '-hwaccel_output_format', 'qsv'
            $presetParam = '-preset slow'
        }
        'intel_av1' {
            $videoCodec = 'av1_qsv'
            $hwAccelParams = '-hwaccel', 'qsv', '-hwaccel_output_format', 'qsv'
            $presetParam = '-preset slow'
        }
        'vulkan_h264' {
            $videoCodec = 'h264_vulkan'
            $hwAccelParams = '-hwaccel', 'vulkan', '-hwaccel_output_format', 'vulkan'
        }
        'vulkan_h265' {
            $videoCodec = 'hevc_vulkan'
            $hwAccelParams = '-hwaccel', 'vulkan', '-hwaccel_output_format', 'vulkan'
        }
        'h264_vaapi' {
            $videoCodec = 'h264_vaapi'
            $hwAccelParams = '-hwaccel', 'vaapi', '-hwaccel_output_format', 'vaapi'
            $presetParam = '-preset slow'
        }
        'hevc_vaapi' {
            $videoCodec = 'hevc_vaapi'
            $hwAccelParams = '-hwaccel', 'vaapi', '-hwaccel_output_format', 'vaapi'
            $presetParam = '-preset slow'
        }
        'av1_vaapi' {
            $videoCodec = 'av1_vaapi'
            $hwAccelParams = '-hwaccel', 'vaapi', '-hwaccel_output_format', 'vaapi'
            $presetParam = '-preset slow'
        }
        default {
            Write-Warning "EncoderProfile '$EncoderProfile' is not a built-in profile. Treating it as a custom video codec and arguments."
            $customArgs = $EncoderProfile.Split(' ')
            $videoCodec = $customArgs[0]
            if ($customArgs.Count -gt 1) {
                $hwAccelParams = $customArgs[1..($customArgs.Count - 1)]
            }
        }
    }
    Write-Host "Using Encoder: $videoCodec"
    if ($hwAccelParams.Count -gt 0) { Write-Host "Using HWAccel: $($hwAccelParams -join ' ')" }

    # --- Escape Shader Path for ffmpeg filtergraph ---
    # PowerShell handles paths with spaces if quoted, but ffmpeg filtergraph needs specific escaping
    $escapedShaderPath = $fullShaderPath -replace '\\', '\\\\' `
                                         -replace ':', '\:' `
                                         -replace '''', '\\\\''\\\\''' # No way to escape apostrophes unfortunately
    Write-Verbose "Escaped Shader Path for filtergraph: $escapedShaderPath"

    # --- Begin ---
    Write-Host ""

    # --- Container Extension ---
    $outputExt = ".$Container"

    # --- Script Paths for Sub-tasks ---
    $remuxScript = Join-Path $PSScriptRoot "remux.ps1"
    $setSubsPriorityScript = Join-Path $PSScriptRoot "set-subs-priority.ps1"
    $extractSubsScript = Join-Path $PSScriptRoot "extract-subs.ps1"
    $setAudioPriorityScript = Join-Path $PSScriptRoot "set-audio-priority.ps1"
    $transcodeAudioScript = Join-Path $PSScriptRoot "transcode-audio.ps1"

    # --- Container Compatibility Rules ---
    # Define conditions where certain stream types should NOT be copied.
    # Key: Container extension (e.g., '.mp4')
    # Value: Array of strings ('no_video', 'no_audio', 'no_subs')
    $containerLimitations = @{
        '.gif' = @('no_audio', 'no_subs', 'no_ttf', 'no_data') # GIF needs video transcode, no audio/subs, no fonts, no data streams
        '.mp4' = @('no_subs', 'no_ttf') # MP4 subtitle copy is often problematic
        # !! TTF and Data filtering not yet implemented !!
        # Add more container rules as needed
        # '.avi' = @('no_subs') # Example
        # '.mov' = @('no_subs') # Example
    }

    # --- Function to Execute External PowerShell Scripts Robustly ---
    function Invoke-ExternalScript {
        param(
            [Parameter(Mandatory = $true)]
            [string]$ScriptPath,

            [Parameter(Mandatory = $true)]
            [hashtable]$Parameters,

            [Parameter(Mandatory = $false)]
            [string]$TaskDescription = "External script", # For logging

            [Parameter(Mandatory = $false)]
            [switch]$CaptureOutput
        )

        if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
            Write-Warning "$TaskDescription script not found: $ScriptPath. Skipping execution."
            return if ($CaptureOutput) { [PSCustomObject]@{ ExitCode = -1; Output = $null } } else { -1 }
        }

        # Escape square brackets to avoid wildcard expansion
        $escapedScriptPath = $ScriptPath -replace '\[', '`[' -replace '\]', '`]'

        if (-not $Concise) { Write-Host "$TaskDescription..." }
        $exitCode = -1 # Default to error
        $output = $null
        try {
            if ($CaptureOutput) {
                $output = & $escapedScriptPath @Parameters 2>$null 3>$null 4>$null 5>$null 6>$null
            } else {
                & $escapedScriptPath @Parameters *> $null
            }
            $exitCode = $LASTEXITCODE
        } catch {
            Write-Warning "Error starting $TaskDescription process for '$ScriptPath': $($_.Exception.Message)"
            # Keep $exitCode as -1
        }

        Write-Verbose "$TaskDescription completed with Exit Code: $exitCode for '$ScriptPath'."

        if ($CaptureOutput) {
            return [PSCustomObject]@{
                ExitCode = $exitCode
                Output   = $output
            }
        } else {
            return $exitCode
        }
    }

    # --- Function to Select/Reject ffmpeg parameter pairs ---
    function Select-ParameterPairs {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [string[]]$ArgumentList,

            [Parameter(Mandatory = $true, Position = 0)]
            [string[]]$Filter,

            [Parameter()]
            [switch]$Whitelist, # If present, select only matching. Default is to remove matching (blacklist).

            [Parameter()]
            [switch]$Regex # Use regex for matching filter values
        )
        $i = 0
        $max = $ArgumentList.Count
        $result = while ($i -lt $max) {
            $param = $ArgumentList[$i]
            # A value is the next item, as long as it doesn't start with a hyphen
            $value = if (($i + 1) -lt $max -and -not $ArgumentList[$i + 1].StartsWith('-')) {
                $ArgumentList[$i + 1]
            } else {
                $null
            }

            $isMatch = $false
            # Create a string to test against, e.g., "-param value" or just "-param"
            $testString = if ($null -ne $value) { "$param $value" } else { $param }

            foreach ($f in $Filter) {
                if ($Regex.IsPresent) {
                    # With regex, we test against the combined "param value" string
                    if ($testString -match $f) {
                        $isMatch = $true
                        break
                    }
                } else {
                    # Without regex, we only test the parameter name for an exact match
                    if ($param -eq $f) {
                        $isMatch = $true
                        break
                    }
                }
            }

            # XOR logic determines if we keep the pair
            $keep = $Whitelist.IsPresent -eq $isMatch

            if ($keep) {
                $param
                if ($null -ne $value) {
                    $value
                }
            }

            # Advance index past parameter and value if it exists
            if ($null -ne $value) {
                $i += 2
            } else {
                $i += 1
            }
        }

        return @($result)
    }

    # --- Function to Process a Single File ---
    function New-TranscodedVideo {
        param(
            [Parameter(Mandatory = $true)]
            [System.IO.FileInfo]$FileInput,

            [Parameter(Mandatory = $true)]
            [string]$OutputExt,

            [Parameter(Mandatory = $true)]
            [string]$OutputSuffix,

            [Parameter()]
            [switch]$ForceProcessing,

            [Parameter()]
            [switch]$DeleteOriginalFlag,

            [Parameter()]
            [switch]$DoSetSubsPriority,

            [Parameter()]
            [switch]$DoExtractSubs,

            [Parameter()]
            [switch]$DoSetAudioPriority,
            [Parameter()]
            [string]$SubsLangPriorityForSet,
            [Parameter()]
            [string]$SubsTitlePriorityForSet,

            [Parameter()]
            [string]$SubFormatForExtract,

            [Parameter()]
            [string]$AudioLangPriorityForSet,
            [Parameter()]
            [string]$AudioTitlePriorityForSet,

            [Parameter()]
            [string]$AudioCodecForTranscode,
            [Parameter()]
            [string]$AudioBitrateForTranscode,
            [Parameter()]
            [string]$AudioChannelsForTranscode
        )

        $inputFileFullPath = $FileInput.FullName
        $inputPath = $FileInput.DirectoryName
        $inputName = $FileInput.BaseName
        $inputExt = $FileInput.Extension

        # Construct Potential Output Path EARLY for check
        $outputFileFullPath = Join-Path $inputPath ($inputName + $OutputSuffix + $OutputExt)

        if (-not $Concise) {
            Write-Host "`n-----------------------------------------------------"
            Write-Host "Processing: $inputFileFullPath"
            Write-Host "Output will be: $outputFileFullPath"
            Write-Host "-----------------------------------------------------`n"
        }

        # Check if Output File Exists and if Force flag is NOT set
        $outputExists = Test-Path -LiteralPath $outputFileFullPath -PathType Leaf
        if ($outputExists -and -not $ForceProcessing) {
            if (-not $Concise) { Write-Warning "Skipping '$inputFileFullPath' because output '$outputFileFullPath' already exists. Use -Force to overwrite." }
            return
        } elseif ($outputExists -and -not $Concise) {
            Write-Host "Force processing for '$inputFileFullPath' despite existing output '$outputFileFullPath'."
        }
        if (-not (Test-Path -LiteralPath $inputFileFullpath -PathType Leaf)) {
            Write-Warning "Input file '$inputFileFullPath' does not exist. Skipping."
            return
        }


        # --- Get Input Video Info (Pixel Format) ---
        if (-not $Concise) { Write-Host "Probing file details with ffprobe..." }
        $pixFmt = $null
        try {
            # Use & operator to capture output
            $ffprobeArgs = @(
                '-v', 'error',
                '-select_streams', 'v:0',
                '-show_entries', 'stream=pix_fmt',
                '-of', 'csv=p=0',
                "$inputFileFullPath"
            )
            Write-Verbose "Running: $ffprobe $($ffprobeArgs -join ' ')"
            $output = & $ffprobe @ffprobeArgs 2>&1 # Capture stdout and stderr
            $exitCode = $LASTEXITCODE

            if ($exitCode -eq 0 -and (-not [string]::IsNullOrWhiteSpace($output))) {
                $pixFmt = $output.Trim()
                if (-not $Concise) { Write-Host "Detected Pixel Format: $pixFmt" }
            } else {
                Write-Warning "ffprobe did not return a pixel format for '$inputFileFullPath'. Exit Code: $exitCode. Output: $output"
                # Attempt fallback or decide how to handle - maybe default to yuv420p?
                Write-Error "ffprobe failed to determine pixel format for '$inputFileFullPath'. Cannot proceed."
                return
            }
        } catch {
            Write-Error "Error running ffprobe for pixel format on '$inputFileFullPath': $($_.Exception.Message)"
            return
        }

        # --- HDR Check (Simple heuristic) ---
        if ($videoCodec -notmatch '^(libsvtav1|av1_nvenc|av1_amf)$' -and $pixFmt -match '(10[lb]e|12[lb]e|p010|yuv420p10)') {
            Write-Warning "Detected potential HDR pixel format ($pixFmt). Only AV1 encoders fully support HDR preservation in this script. Output might not be HDR."
        }

        # --- Collect Stream Mapping Arguments ---
        $inputLimitations = if ($containerLimitations.ContainsKey($inputExt)) { $containerLimitations[$inputExt] } else { @() }
        $outputLimitations = if ($containerLimitations.ContainsKey($OutputExt)) { $containerLimitations[$OutputExt] } else { @() }

        # --- Get Base Arguments ---
        $containerName = $OutputExt
        $remuxParams = @{
            Path        = $inputFileFullPath
            Container   = $containerName
            FfmpegPath  = $ffmpeg
            FfprobePath = $ffprobe
            Concise     = $true
            Verbose     = $false
            PassThru    = $true
        }

        $remuxResult = Invoke-ExternalScript -ScriptPath $remuxScript -Parameters $remuxParams -TaskDescription "Retrieving remux args" -CaptureOutput
        $streamArgs = @()
        if ($remuxResult.ExitCode -eq 0 -and $remuxResult.Output) {
            $streamArgs = $remuxResult.Output
            Write-Verbose "Base arguments from remux.ps1: $($streamArgs -join ' ')"
        } else {
            if ($remuxResult.ExitCode -ne -2) { Write-Warning "Failed to get base arguments from remux.ps1 (Exit Code: $($remuxResult.ExitCode)). Stream mapping may be incorrect." }
            $streamArgs = @(
                '-map', '0:v:0',
                '-map', '0:a?',
                '-map', '0:s?',
                '-map', '0:d?',
                '-map', '0:t?',
                '-c:a', 'copy',
                '-c:s', 'copy'
            )
        }

        $ALL_STREAMS = '^-c .*' + '^-map 0'

        # --- Handle Audio Overrides ---
        $allowAudio = -not ($inputLimitations -contains 'no_audio' -or $outputLimitations -contains 'no_audio')
        if ($allowAudio) {
            $transcodeAudioRequested = (-not [string]::IsNullOrWhiteSpace($AudioCodecForTranscode))
            if ($transcodeAudioRequested -or $DoSetAudioPriority) {
                $transcodeAudioArgs = @()
                $priorityDispositionArgs = @()

                # --- Transcode Audio ---
                if ($transcodeAudioRequested) {
                    $transcodeParams = @{
                        Path        = $inputFileFullPath
                        Codec       = $AudioCodecForTranscode
                        Bitrate     = $AudioBitrateForTranscode
                        Channels    = $AudioChannelsForTranscode
                        FfmpegPath  = $ffmpeg
                        FfprobePath = $ffprobe
                        Concise     = $true
                        Verbose     = $false
                        PassThru    = $true
                    }
                    $transcodeResult = Invoke-ExternalScript -ScriptPath $transcodeAudioScript -Parameters $transcodeParams -TaskDescription "Retrieving audio transcode args" -CaptureOutput
                    if ($transcodeResult.ExitCode -eq 0 -and $transcodeResult.Output) {
                        $transcodeAudioArgs = $transcodeResult.Output
                    } else {
                        if ($priorityResult.ExitCode -ne -2) { Write-Warning "Failed to get audio transcode args (Exit Code: $($transcodeResult.ExitCode))." }
                    }
                }

                # --- Set Audio Track Priority ---
                if ($DoSetAudioPriority) {
                    $priorityParams = @{
                        Path        = $inputFileFullPath
                        Lang        = $AudioLangPriorityForSet
                        Title       = $AudioTitlePriorityForSet
                        FfmpegPath  = $ffmpeg
                        FfprobePath = $ffprobe
                        Concise     = $true
                        Verbose     = $false
                        PassThru    = $true
                    }
                    $priorityResult = Invoke-ExternalScript -ScriptPath $setAudioPriorityScript -Parameters $priorityParams -TaskDescription "Retrieving audio disposition args" -CaptureOutput
                    if ($priorityResult.ExitCode -eq 0 -and $priorityResult.Output) {
                        $priorityDispositionArgs = $priorityResult.Output
                    } else {
                        if ($priorityResult.ExitCode -ne -2) { Write-Warning "Failed to get audio disposition args (Exit Code: $($priorityResult.ExitCode))." }
                    }
                }

                # Combine and replace
                $audioArgs = $transcodeAudioArgs + $priorityDispositionArgs
                if ($audioArgs.Count -gt 0) {
                    Write-Verbose "Overriding remux audio arguments. New args: $($audioArgs -join ' ')"
                    # Remove all previous audio-related arguments
                    $audioFilter = '^-map 0:a.*', '^-c:a .*', '^-disposition:a.* .+', '^-b:a .*', '^-ac .*', '^-ar .*', '^-af .*'
                    $streamArgs = Select-ParameterPairs -ArgumentList $streamArgs -Filter ($audioFilter + $ALL_STREAMS) -Regex
                    $streamArgs += Select-ParameterPairs -ArgumentList $audioArgs -Filter ($audioFilter + '^-map 0:\d+') -Regex -Whitelist
                }
            }
        } else {
            if (-not $Concise) { Write-Host "Skipping audio streams due to container limitations ($inputExt -> $OutputExt)." }
        }

        # --- Handle Subtitle Overrides ---
        $allowInputSubs = -not ($inputLimitations -contains 'no_subs')
        $allowOutputSubs = -not ($outputLimitations -contains 'no_subs')
        $prioritizedSubStreamIndex = -1

        if ($allowInputSubs -and $DoSetSubsPriority) {
            Write-Verbose "Setting subtitle priority."
            $setSubsParams = @{
                Path        = $inputFileFullPath
                Lang        = $SubsLangPriorityForSet
                Title       = $SubsTitlePriorityForSet
                FfmpegPath  = $ffmpeg
                FfprobePath = $ffprobe
                Concise     = $true
                Verbose     = $false
                PassThru    = $true
            }
            $result = Invoke-ExternalScript -ScriptPath $setSubsPriorityScript -Parameters $setSubsParams -TaskDescription "Retrieving subtitle prioritization args" -CaptureOutput
            if ($result.ExitCode -eq 0 -and $result.Output) {
                $newSubsArgs = $result.Output

                # Retrieve prioritized stream index from output
                $prioritizedMap = Select-ParameterPairs -ArgumentList $result.Output -Filter "-map 0:\d+" -Regex -Whitelist
                if ($DoExtractSubs -and $prioritizedMap.Count -gt 0 -and $prioritizedMap[1] -match '^0:(\d+)$') {
                    $prioritizedSubStreamIndex = $matches[1]
                    Write-Verbose "Found prioritized subtitle stream index for extraction: $prioritizedSubStreamIndex"
                }

                Write-Verbose "Overriding remux subtitle arguments. New args: $($newSubsArgs -join ' ')"
                # Remove all previous subtitle-related arguments
                $subsFilter = '^-map 0:s.*', '^-c:s .+', '^-disposition:s.* .+'
                $streamArgs = Select-ParameterPairs -ArgumentList $streamArgs -Filter ($subsFilter + $ALL_STREAMS) -Regex
                if ($allowOutputSubs) {
                    Write-Verbose "Setting subtitle priority for output container with arguments: $($newSubsArgs -join ' ')"
                    $streamArgs += Select-ParameterPairs -ArgumentList $newSubsArgs -Filter ($subsFilter + '^-map 0:\d+$') -Regex -Whitelist
                }
            } else {
                if ($result.ExitCode -ne -2) { Write-Warning "Failed to get subtitle arguments from set-subs-priority.ps1 (Exit Code: $($result.ExitCode)). Subtitle handling may be incorrect." }
            }
            if (-not $Concise) { Write-Host "Skipping subtitle stream mapping due to output container limitations ($OutputExt), but extraction may still occur." }
        } elseif (-not $allowInputSubs) {
            if (-not $Concise) { Write-Host "Skipping subtitle streams due to input container limitations ($inputExt)." }
        }

        # --- Extract Subtitles ---
        if ($DoExtractSubs) {
            if (-not (Test-Path -LiteralPath $extractSubsScript -PathType Leaf)) {
                Write-Warning "ExtractSubs flag is set, but script not found: $extractSubsScript. Skipping subtitle extraction."
            } else {
                if (-not $Concise) { Write-Host "`n--- Extracting Subtitles ---" }
                $extractParams = @{
                    Path        = $inputFileFullPath
                    Format      = $SubFormatForExtract
                    Suffix      = $OutputSuffix
                    Force       = $ForceProcessing
                    FfmpegPath  = $ffmpeg
                    FfprobePath = $ffprobe
                    Concise     = $true
                    Verbose     = $false
                }

                if ($prioritizedSubStreamIndex -ge 0) {
                    $extractParams['OverrideDefault'] = $prioritizedSubStreamIndex
                }

                $exitCode = Invoke-ExternalScript -ScriptPath $extractSubsScript -Parameters $extractParams -TaskDescription "Subtitle extraction"

                if ($Concise) {
                    switch($exitCode) {
                        0 { Write-Host "Subtitles extracted successfully!" }
                        -2 { Write-Host "Subtitles already extracted." }
                        default { Write-Warning "Subtitle extraction subprocess indicated failure (Exit Code: $exitCode) for '$inputFileFullPath'. Check script output for details." }
                    }
                } else {
                    switch ($exitCode) {
                        0 { Write-Host "Subtitles extracted successfully for '$inputFileFullPath'." }
                        -2 { Write-Host "No subtitle streams found for '$inputFileFullPath', or they're already extracted." }
                        default { Write-Warning "Subtitle extraction subprocess indicated failure (Exit Code: $exitCode) for '$inputFileFullPath'. Check script output for details." }
                    }
                    Write-Host "--- End Subtitle Extraction ---`n"
                }
            }
        }

        # --- Reorder Stream Maps ---
        $attachmentMaps = Select-ParameterPairs -ArgumentList $streamArgs -Filter '^-map 0:t.*' -Regex -Whitelist
        if ($attachmentMaps.Count -gt 0) {
            Write-Verbose "Found attachment maps to move to end: $($attachmentMaps -join ', ')"
            # Remove existing attachment maps from streamArgs and add them back at the end
            $streamArgs = Select-ParameterPairs -ArgumentList $streamArgs -Filter '^-map 0:t.*' -Regex
            $streamArgs += $attachmentMaps
        } else {
            Write-Verbose "No attachment maps found in stream arguments."
        }

        # --- Construct FFMPEG Command Arguments ---
        # Start with -y for overwrite, then add logging based on $Concise
        $ffmpegArgs = @('-y', '-stats')
        if ($Concise) {
            $ffmpegArgs += '-v', 'fatal'
        } else {
            $ffmpegArgs += '-v', 'warning'
        }
        $ffmpegArgs += $hwAccelParams # Add HWAccel params if any
        $ffmpegArgs += '-i', "$inputFileFullPath" # Input file
        $ffmpegArgs += '-init_hw_device', 'vulkan' # Libplacebo needs Vulkan
        # The filtergraph needs careful quoting, especially the shader path
        $filterGraph = "format=$pixFmt,hwupload,libplacebo=w=${TargetResolutionW}:h=${TargetResolutionH}:upscaler=bilinear:custom_shader_path='$escapedShaderPath',format=$pixFmt"
        $ffmpegArgs += '-vf', "$filterGraph"
        $ffmpegArgs += $streamArgs # Add stream mapping args
        $ffmpegArgs += '-c:v', $videoCodec # Video codec
        $ffmpegArgs += '-qp', $CQP # Quality parameter
        if (-not [string]::IsNullOrWhiteSpace($presetParam)) { $ffmpegArgs += $presetParam.Split(' ') } # Preset
        if (-not [string]::IsNullOrWhiteSpace($threadParam)) { $ffmpegArgs += $threadParam.Split(' ') } # Threads
        $ffmpegArgs += "$outputFileFullPath" # Output file

        # Last-second check
        $outputExists = Test-Path -LiteralPath $outputFileFullPath -PathType Leaf
        if ($outputExists -and -not $ForceProcessing) {
            if (-not $Concise) { Write-Warning "Skipping '$inputFileFullPath' because output '$outputFileFullPath' already exists. Use -Force to overwrite." }
            return
        } elseif ($outputExists -and -not $Concise) {
            Write-Host "Force processing for '$inputFileFullPath' despite existing output '$outputFileFullPath'."
        }
        if (-not (Test-Path -LiteralPath $inputFileFullpath -PathType Leaf)) {
            Write-Warning "Input file '$inputFileFullPath' no longer exists. Skipping."
            return
        }

        # --- Execute FFMPEG ---
        if (-not $Concise) { Write-Host "Starting ffmpeg command:`n$ffmpeg $($ffmpegArgs -join ' ')" }

        if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Transcode to $outputFileFullPath")) {
            try {
                Write-Verbose "Running: $ffmpeg $($ffmpegArgs -join ' ')"
                & $ffmpeg @ffmpegArgs
                $exitCode = $LASTEXITCODE
                if (-not $Concise) { Write-Host "" }

                if ($exitCode -ne 0) {
                    Write-Error "ffmpeg process failed (Exit Code: $exitCode) while processing '$inputFileFullPath'."
                    # Attempt to clean up potentially broken output file
                    if (Test-Path -LiteralPath $outputFileFullPath -PathType Leaf) {
                        Write-Warning "Attempting to remove potentially incomplete output file: $outputFileFullPath"
                        Remove-Item -LiteralPath $outputFileFullPath -ErrorAction SilentlyContinue
                    }
                    # Consider stopping further processing if needed
                    # $script:StopProcessing = $true # Requires $script: scope if needed globally
                    return # Stop processing this file
                } else {
                    if (-not $Concise) { Write-Host "Successfully processed '$inputFileFullPath' to '$outputFileFullPath'" }
                }
            } catch {
                Write-Error "Error executing ffmpeg for '$inputFileFullPath': $($_.Exception.Message)"
                # Attempt cleanup
                if (Test-Path -LiteralPath $outputFileFullPath -PathType Leaf) {
                    Write-Warning "Attempting to remove potentially incomplete output file due to error: $outputFileFullPath"
                    Remove-Item -LiteralPath $outputFileFullPath -ErrorAction SilentlyContinue
                }
                return # Stop processing this file
            }
        } else {
            Write-Warning "Skipping transcode for '$inputFileFullPath' due to -WhatIf."
            return # Don't proceed with post-processing if -WhatIf
        }

        # --- Delete Original File ---
        if ($DeleteOriginalFlag -and (Test-Path -LiteralPath $outputFileFullPath -PathType Leaf)) {
            if (-not $Concise) { Write-Host "Deleting original file: '$inputFileFullPath'" }
            if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Delete original file after successful transcode")) {
                try {
                    Remove-Item -LiteralPath $inputFileFullPath -Force -ErrorAction Stop
                    if (-not $Concise) { Write-Host "Successfully deleted original file: '$inputFileFullPath'" }
                } catch {
                    # Warnings should always show
                    Write-Warning "Failed to delete original file '$inputFileFullPath'. It might be in use or permissions are denied. Error: $($_.Exception.Message)"
                }
            } else {
                Write-Warning "Skipping deletion of '$inputFileFullPath' due to -WhatIf."
            }
        }
    } # End Function New-TranscodedVideo

} # End Begin block

process {
    foreach ($itemPath in $Path) {
        $itemPath = $itemPath.Trim()
        Write-Verbose "Processing argument: $itemPath"
        try {
            Write-Verbose "PATH ----- $(Get-Item -LiteralPath $itemPath)"
            $item = Get-Item -LiteralPath $itemPath -ErrorAction Stop
            $videoExtensions = @('.mkv', '.mp4', '.avi', '.mov', '.gif') # Add more if needed
            if ($item -is [System.IO.DirectoryInfo]) {
                if (-not $Concise) { Write-Host "`nProcessing directory: $($item.FullName) (Recursive: $Recurse)" }
                # Filter out already processed files *before* counting
                $allFiles = Get-ChildItem -LiteralPath $item.FullName -Recurse:$Recurse | Where-Object { $videoExtensions -contains $_.Extension }
                $filesToProcess = $allFiles | Where-Object { $_.BaseName -notlike "*$Suffix" }
                $totalFiles = $filesToProcess.Count
                $processedCount = 0

                if ($totalFiles -eq 0) {
                    if (-not $Concise) { Write-Host "No supported video files found (or all are already processed) in '$($item.FullName)'." }
                    continue
                }

                if (-not $Concise) { Write-Host "Found $totalFiles video file(s) to process." }

                foreach ($file in $filesToProcess) {
                    $processedCount++
                    Write-Host "Progress: $processedCount / $totalFiles - Processing '$($file.Name)'"

                    # Skip files that already have the suffix (redundant check now, but safe)
                    if ($file.BaseName -like "*$Suffix") {
                        Write-Verbose "Skipping already processed file: $($file.FullName)"
                        continue
                    }
                    New-TranscodedVideo -FileInput $file `
                                        -OutputExt $outputExt `
                                        -OutputSuffix $Suffix `
                                        -ForceProcessing:$Force `
                                        -DeleteOriginalFlag:$Delete `
                                        -DoExtractSubs:$ExtractSubs `
                                        -DoSetAudioPriority:$SetAudioPriority `
                                        -AudioLangPriorityForSet $AudioLangPriority `
                                        -AudioTitlePriorityForSet $AudioTitlePriority `
                                        -SubFormatForExtract $SubFormat `
                                        -DoSetSubsPriority:$SetSubsPriority `
                                        -SubsLangPriorityForSet $SubsLangPriority `
                                        -SubsTitlePriorityForSet $SubsTitlePriority `
                                        -AudioCodecForTranscode $AudioCodec `
                                        -AudioBitrateForTranscode $AudioBitrate `
                                        -AudioChannelsForTranscode $AudioChannels
                    # Add check here if $script:StopProcessing was set inside the function
                }
            } elseif ($item -is [System.IO.FileInfo]) {
                if (-not ($videoExtensions -contains $item.Extension)) {
                    Write-Warning "File '$($item.FullName)' is not supported as its extension '$($item.Extension)' is not in the recognized list of video formats."
                }
                # Skip files that already have the suffix if passed directly
                if ($item.BaseName -like "*$Suffix") {
                    Write-Warning "Skipping file '$($item.FullName)' as it appears to be an already processed output file."
                    continue
                }

                # Always show progress for single files too
                Write-Host "Progress: 1 / 1 - Processing '$($item.Name)'"

                New-TranscodedVideo -FileInput $item `
                                    -OutputExt $outputExt `
                                    -OutputSuffix $Suffix `
                                    -ForceProcessing:$Force `
                                    -DeleteOriginalFlag:$Delete `
                                    -DoExtractSubs:$ExtractSubs `
                                    -DoSetAudioPriority:$SetAudioPriority `
                                    -AudioLangPriorityForSet $AudioLangPriority `
                                    -AudioTitlePriorityForSet $AudioTitlePriority `
                                    -SubFormatForExtract $SubFormat `
                                    -DoSetSubsPriority:$SetSubsPriority `
                                    -SubsLangPriorityForSet $SubsLangPriority `
                                    -SubsTitlePriorityForSet $SubsTitlePriority `
                                    -AudioCodecForTranscode $AudioCodec `
                                    -AudioBitrateForTranscode $AudioBitrate `
                                    -AudioChannelsForTranscode $AudioChannels
                # Add check here if $script:StopProcessing was set inside the function
            } else {
                Write-Warning "Path '$itemPath' is not a file or directory. Skipping."
            }
        } catch {
            Write-Error "Error processing path '$itemPath': $($_.Exception)"
        }
    }
} # End Process block

end {
    Write-Host "`nAll arguments processed."
} # End End block
