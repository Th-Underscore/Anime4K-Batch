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

.PARAMETER ScaleFactor
Scale factor multiplier (e.g. 2.0). If set > 0, overrides TargetResolutionW/H.
Calculates dimensions based on input resolution, enforcing Mod2 (even numbers).

.PARAMETER ShaderFile
Shader filename located in the ShaderBasePath. Default: 'Anime4K_ModeA_A-fast.glsl'.

.PARAMETER ShaderBasePath
Path to the shaders folder. Default: Script's 'shaders' subdirectory.

.PARAMETER EncoderProfile
Encoder profile (e.g., 'nvidia_h265', 'intel_h265', 'cpu_av1'). Default: 'nvidia_h265'.
Options: cpu_h264, cpu_h265, cpu_av1, nvidia_h264, nvidia_h265, nvidia_av1, amd_h264, amd_h265, amd_av1, intel_h264, intel_h265, intel_av1, vulkan_h264, vulkan_h265, vaapi_h264, vaapi_h265, vaapi_av1.
Any other value is treated as a custom codec name, and any extra arguments within (e.g., 'hevc_vaapi -hwaccel vaapi -hwaccel_output_format vaapi') are passed directly to ffmpeg.

.PARAMETER EncoderPreset
Encoder preset (e.g., 'slow', 'veryfast'). Default: 'slow' for CPU, Intel, VA-API; 'p7' for NVENC.
Different options per codec.

.PARAMETER HwAccelDevice
Specifies the hardware acceleration device by index or name (e.g., '0', '1', 'PCI_BUS_ID'). Only applies to hardware-accelerated encoder profiles.
NOT CURRENTLY IMPLEMENTED.

.PARAMETER CQP
Constant Quantization Parameter (0-51, lower is better). Default: 24.

.PARAMETER CRF
Constant Rate Factor (0-51, lower is better), overrides CQP. Default: -1.

.PARAMETER PreserveTexture
Texture quality (0-5, higher is better - greater file size). Default: 0.

.PARAMETER Container
Output container format (e.g., 'mkv', 'mp4'). Default: 'mkv'.

.PARAMETER FastStart
Controls MP4 FastStart optimization (moov atom at beginning).
0: Disabled.
1: Write to local Temp folder first, then move to destination (best for network/NAS).
2: Write directly to destination (best for local drives).

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
Audio bitrate PER CHANNEL for transcoding (e.g., '640k' = 1280kbps for stereo, '96k' = 576kbps for 5.1ch). Defaults to the original value. Only applies if AudioCodec is specified.

.PARAMETER AudioChannels
Number of audio channels (e.g., '2' for stereo, '6' or '5.1' for 5.1). Defaults to the original value. Only applies if AudioCodec is specified.

.PARAMETER Recurse
Process folders recursively.

.PARAMETER Force
Force overwrite existing output files.

.PARAMETER SetSubsPriority
Set default subtitle track on the *input* file using set-track-priority.ps1 before transcoding. This modifies the source file in-place.

.PARAMETER ExtractSubs
Extract subtitles from the *input* file using extract-tracks.ps1 before transcoding. Accounts for set sub priority.

.PARAMETER SetAudioPriority
Set default audio track on the *output* file using set-track-priority.ps1 after transcoding.

.PARAMETER Delete
Delete original file after successful transcode (mutually exclusive with `-Replace`).

.PARAMETER Replace
Replace original file after successful transcode (mutually exclusive with `-Delete`).


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
    [double]$ScaleFactor = 0.0, # 0.0 means disabled (use target resolution)

    [Parameter()]
    [string]$ShaderFile = 'Anime4K_ModeA_A-fast.glsl',

    [Parameter()]
    [string]$ShaderBasePath = '', # Default assigned in begin block

    [Parameter()]
    [string]$EncoderProfile = 'nvidia_h265_legacy',

    [Parameter()]
    [string]$EncoderPreset = '', # Default assigned in "Determine Encoder and HWAccel Params" section

    [Parameter()]
    [string]$HwAccelDevice = '', # NOT CURRENTLY IMPLEMENTED

    [Parameter()]
    [ValidateRange(-1, 51)]
    [int]$CQP = 24,

    [Parameter()]
    [ValidateRange(-1, 63)]
    [int]$CRF = -1,

    [Parameter()]
    [ValidateSet(0, 1, 2, 3, 4, 5)]
    [int]$PreserveTexture = 1,

    [Parameter()]
    [ValidateSet('mkv', 'mp4', 'avi', 'mov', 'gif')] # Add more if needed
    [string]$Container = 'mkv',

    [Parameter()]
    [string]$Suffix = '_upscaled',

    [Parameter()]
    [ValidateSet(0, 1, 2)]
    [int]$FastStart = 0, # 0: Disabled, 1: Temp+Move, 2: Direct

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
    [switch]$Replace,

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

    # --- Parameter Validation ---
    if ($Delete -and $Replace) {
        Write-Error "-Delete and -Replace parameters are mutually exclusive."
        exit 1
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
            $ShaderBasePath = Get-Location
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
            return $null
        } else {
            Write-Warning "$Name could not be located, but may not be essential for this script."
            return $null
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
    $encParams = @()

    if ([string]::IsNullOrWhiteSpace(($EncoderPreset))) {
        switch ($EncoderProfile.ToLower()) {
            {$_ -match 'cpu_|intel_|vaapi_'} {
                $EncoderPreset = 'slow'
            }
            {$_ -match 'nvidia_'} {
                $EncoderPreset = 'p7'
            }
        }
    }

    switch ($EncoderProfile.ToLower()) {
        'cpu_h264' {
            $videoCodec = 'libx264'
            $presetParam = "-preset $EncoderPreset"
            if ($CpuThreads -ne 0) { $threadParam = "-threads $CpuThreads" }
        }
        'cpu_h265' {
            $videoCodec = 'libx265'
            $presetParam = "-preset $EncoderPreset"
            if ($CpuThreads -ne 0) { $encParams += "pools=${CpuThreads}" }
            if ($Concise) { $encParams += "log-level=error" }
        }
        'cpu_av1' {
            $videoCodec = 'libsvtav1'
            $presetParam = "-preset $EncoderPreset"
            if ($CpuThreads -ne 0) { $encParams += "pin=$CpuThreads" }
        }
        'nvidia_h264' {
            $videoCodec = 'h264_nvenc'
            $hwAccelParams = '-hwaccel_device', 'cuda', '-hwaccel_output_format', 'cuda'
            $presetParam = "-preset $EncoderPreset -tune hq"
        }
        {$_ -match 'nvidia_h265'} {
            $videoCodec = 'hevc_nvenc'
            $hwAccelParams = '-hwaccel_device', 'cuda', '-hwaccel_output_format', 'cuda'
            $presetParam = "-preset $EncoderPreset -tune hq -tier high"
        }
        'nvidia_av1' {
            $videoCodec = 'av1_nvenc'
            $hwAccelParams = '-hwaccel_device', 'cuda', '-hwaccel_output_format', 'cuda'
            $presetParam = "-preset $EncoderPreset -tune hq"
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
            $presetParam = "-preset $EncoderPreset"
        }
        'intel_h265' {
            $videoCodec = 'hevc_qsv'
            $hwAccelParams = '-hwaccel', 'qsv', '-hwaccel_output_format', 'qsv'
            $presetParam = "-preset $EncoderPreset"
        }
        'intel_av1' {
            $videoCodec = 'av1_qsv'
            $hwAccelParams = '-hwaccel', 'qsv', '-hwaccel_output_format', 'qsv'
            $presetParam = "-preset $EncoderPreset"
        }
        'vulkan_h264' {
            $videoCodec = 'h264_vulkan'
            $hwAccelParams = '-hwaccel', 'vulkan', '-hwaccel_output_format', 'vulkan'
        }
        'vulkan_h265' {
            $videoCodec = 'hevc_vulkan'
            $hwAccelParams = '-hwaccel', 'vulkan', '-hwaccel_output_format', 'vulkan'
        }
        'vaapi_h264' {
            $videoCodec = 'h264_vaapi'
            $hwAccelParams = '-hwaccel', 'vaapi', '-hwaccel_output_format', 'vaapi'
            $presetParam = "-preset $EncoderPreset"
        }
        'vaapi_h265' {
            $videoCodec = 'hevc_vaapi'
            $hwAccelParams = '-hwaccel', 'vaapi', '-hwaccel_output_format', 'vaapi'
            $presetParam = "-preset $EncoderPreset"
        }
        'vaapi_av1' {
            $videoCodec = 'av1_vaapi'
            $hwAccelParams = '-hwaccel', 'vaapi', '-hwaccel_output_format', 'vaapi'
            $presetParam = "-preset $EncoderPreset"
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

    # --- PRESERVE TEXTURE / GRAIN LOGIC ---
    if ($PreserveTexture -gt 0) {
        Write-Verbose "Applying Texture Preservation Level: $PreserveTexture"

        if ($videoCodec -eq 'libx264') {
            $encParams += "aq-mode=3"

            switch ($PreserveTexture) {
                1 { # Clean - standard upscale output, minimal intervention
                    $encParams += "psy-rd=1.0:0.10"
                }
                2 { # Balanced - preserve some texture without fighting the upscaler
                    $encParams += "aq-strength=0.9", "psy-rd=1.2\:0.15", "deblock=-1:-1"
                }
                3 { # Good retention - daily driver for most upscaled anime
                    $encParams += "aq-strength=1.0", "psy-rd=1.4\:0.20", "trellis=2", "deblock=-1\:-1"
                }
                4 { # Heavy grain / classic anime / strong stylization
                    $presetParam += " -tune grain"
                    $encParams += "aq-strength=0.8", "psy-rd=1.7\:0.30", "trellis=2", "deblock=-2\:-2", "qcomp=0.8"
                }
                5 { # Archival
                    $presetParam += " -tune grain"
                    $encParams += "aq-strength=0.8", "psy-rd=2.0\:0.40", "trellis=2", "deblock=-2\:-2", "qcomp=0.8", "mbtree=0"
                }
            }
        } elseif ($videoCodec -eq 'libx265') {
            $encParams += "sao=0", "strong-intra-smoothing=0", "aq-mode=3"

            switch ($PreserveTexture) {
                1 { # Clean
                    $encParams += "psy-rd=1.0", "psy-rdoq=1.0"
                }
                2 { # Balanced
                    $encParams += "aq-strength=0.9", "psy-rd=1.2", "psy-rdoq=1.5", "deblock=-1\:-1"
                }
                3 { # Good retention
                    $encParams += "aq-strength=1.0", "psy-rd=1.4", "psy-rdoq=2.5", "deblock=-1\:-1"
                }
                4 { # Heavy grain
                    $presetParam += " -tune grain"
                    $encParams += "tskip=1", "psy-rd=1.7", "psy-rdoq=4.0", "rdoq-level=2", "deblock=-2\:-2", "qg-size=32"
                }
                5 { # Archival
                    $presetParam += " -tune grain"
                    $encParams += "tskip=1", "psy-rd=2.0", "psy-rdoq=6.0", "rdoq-level=2", "deblock=-2\:-2", "qcomp=0.8", "cutree=0", "qg-size=32"
                }
            }
        } elseif ($videoCodec -eq 'libsvtav1') {
            $encParams += "tune=0", "enable-qm=1"

            switch ($PreserveTexture) {
                1 { # Clean
                    $encParams += "qm-min=8"
                }
                2 { # Balanced
                    $encParams += "qm-min=4", "sharpness=1", "variance-boost-strength=2", "variance-octile=6"
                }
                3 { # Good retention
                    $encParams += "qm-min=0", "sharpness=2", "variance-boost-strength=3", "variance-octile=5", "enable-tf=0"
                }
                4 { # Heavy grain
                    $encParams += "qm-min=0", "qm-max=8", "sharpness=3", "variance-boost-strength=4", "variance-octile=5", "enable-tf=0", "enable-cdef=0"
                }
                5 { # Archival
                    $encParams += "qm-min=0", "qm-max=8", "sharpness=4", "variance-boost-strength=4", "variance-octile=4", "enable-tf=0", "enable-cdef=0", "enable-restoration=0"
                }
            }
        } elseif ($videoCodec -match 'nvenc') {
            if ($EncoderProfile -notmatch 'legacy') { $presetParam += " -temporal_aq 1" }

            switch ($PreserveTexture) {
                1 {}
                2 { # Balanced
                    $presetParam += " -spatial-aq 1 -aq-strength 8"
                }
                3 { # Good retention
                    $presetParam += " -spatial-aq 1 -aq-strength 12 -rc-lookahead 32 -b_ref_mode 2 -multipass 1"
                }
                4 { # Heavy grain
                    $presetParam += " -spatial-aq 1 -aq-strength 15 -rc-lookahead 53 -b_ref_mode 2 -weighted_pred 1 -multipass 1"
                }
                5 { # Maximum retention (NVENC)
                    $presetParam += " -spatial-aq 1 -aq-strength 15 -rc-lookahead 53 -b_ref_mode 2 -weighted_pred 1 -multipass 2"
                }
            }

        }
        Write-Verbose "New encoder params w/ PreserveTexture: $encParams"
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
    $setTrackPriorityScript = Join-Path $PSScriptRoot "set-track-priority.ps1"
    $extractTracksScript = Join-Path $PSScriptRoot "extract-tracks.ps1"
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
            [switch]$Regex
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
            $testString = if ($null -ne $value) { "$param $value" } else { $param }

            foreach ($f in $Filter) {
                if ($Regex.IsPresent) {
                    if ($testString -match $f) {
                        $isMatch = $true
                        break
                    }
                } else {
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
            [switch]$ReplaceOriginalFlag,

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

        # --- Determine Output Filename(s) ---
        $tempSuffix = ".tmp_transcode"
        $finalOutputFile = ''
        $ffmpegTargetFile = ''

        if ($ReplaceOriginalFlag) { # Replace mode
            $OutputSuffix = ''
            $ffmpegTargetFile = Join-Path $inputPath ($inputName + $tempSuffix + $OutputExt)
            $finalOutputFile = $inputFileFullPath
            Write-Verbose "Action: Replace original. Temp file: '$ffmpegTargetFile'"
        } else { # Suffix or Delete mode
            $ffmpegTargetFile = Join-Path $inputPath ($inputName + $OutputSuffix + $OutputExt)
            $finalOutputFile = $ffmpegTargetFile
            Write-Verbose "Action: Create new file. Target: '$ffmpegTargetFile'"
        }

        $processingFile = $ffmpegTargetFile
        $useLocalTemp = ($OutputExt -eq '.mp4' -and $FastStart -eq 1) # TODO: Make this a general option

        if ($useLocalTemp) {
            $tempDir = [System.IO.Path]::GetTempPath()
            $tempName = $FileInput.BaseName + "_" + [System.IO.Path]::GetRandomFileName() + $OutputExt
            $processingFile = Join-Path $tempDir $tempName
            Write-Verbose "FastStart Level 1: Transcoding to local temp '$processingFile' before move."
        }

        $outputFileFullPath = $ffmpegTargetFile # Use ffmpegTargetFile for processing

        if (-not $Concise) {
            Write-Host "`n-----------------------------------------------------"
            Write-Host "Processing: $inputFileFullPath"
            Write-Host "Output will be: $outputFileFullPath"
            if ($useLocalTemp) { Write-Host "Temp Work File: $processingFile" }
            Write-Host "-----------------------------------------------------`n"
        }

        # Check if FINAL target exists (for suffix mode) or target TEMP exists (for replace mode)
        if ($ReplaceOriginalFlag) {
            if ((Test-Path -LiteralPath $ffmpegTargetFile) -and (-not $ForceProcessing)) {
                Write-Warning "Temporary file '$ffmpegTargetFile' already exists. Use -Force to overwrite it and continue."
                return
            }
        } else {
            if ((Test-Path -LiteralPath $finalOutputFile) -and (-not $ForceProcessing)) {
                Write-Warning "Skipping transcode, output file '$finalOutputFile' already exists. Use -Force to overwrite."
                return
            }
        }
        if (-not (Test-Path -LiteralPath $inputFileFullpath -PathType Leaf)) {
            Write-Warning "Input file '$inputFileFullPath' does not exist. Skipping."
            return
        }

        $success = $false
        try {
            if (-not $useLocalTemp) { New-Item -Path $ffmpegTargetFile -ItemType File -Force | Out-Null }

            # --- Probe File Metadata (JSON) ---
            if (-not $Concise) { Write-Host "Probing file details with ffprobe..." }
            $probeData = $null
            $probeJson = ""
            $inputW = 0
            $inputH = 0
            $pixFmt = "yuv420p"

            try {
                $ffprobeArgs = @(
                    '-v', 'fatal',
                    '-show_format',
                    '-show_streams',
                    '-print_format', 'json',
                    "$inputFileFullPath"
                )
                Write-Verbose "Running: $ffprobe $($ffprobeArgs -join ' ')"
                $probeJson = & $ffprobe @ffprobeArgs

                if ($LASTEXITCODE -eq 0 -and (-not [string]::IsNullOrWhiteSpace($probeJson))) {
                    $probeData = [string]$probeJson | ConvertFrom-JsonHash

                    $videoStream = $probeData.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
                    if ($videoStream) {
                        # Write-Verbose "Detected video stream: $($videoStream | ConvertTo-Json -Depth 10)"
                        $inputW = $videoStream.width
                        $inputH = $videoStream.height
                        if ($videoStream.pix_fmt) { $pixFmt = $videoStream.pix_fmt }

                        if (-not $Concise) { Write-Verbose "Detected: ${inputW}x${inputH}, $pixFmt" }
                    } else {
                        Write-Warning "No video stream found."
                        return
                    }
                } else {
                    Write-Error "ffprobe failed to probe '$inputFileFullPath'."
                    return
                }
            } catch {
                Write-Error "Error running ffprobe on '$inputFileFullPath': $($_.Exception.Message)"
                return
            }

            # --- Encode Probe Data for Sub-Scripts ---
            $compressedJson = $probeData | ConvertTo-Json -Depth 10 -Compress
            $probeDataB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($compressedJson))

            # --- HDR Check (simple heuristic) ---
            if (-not $Concise -and $videoCodec -notmatch '^(libsvtav1|av1_nvenc|av1_amf)$' -and $pixFmt -match '(10[lb]e|12[lb]e|p010|yuv420p10)') {
                Write-Warning "Detected potential HDR pixel format ($pixFmt). Only AV1 encoders fully support HDR preservation in this script. Output might not be HDR."
            }

            # --- Calculate Dimensions ---
            $w_str = "$TargetResolutionW"
            $h_str = "$TargetResolutionH"

            if ($ScaleFactor -gt 0.0) {
                $calcW = [math]::Round($inputW * $ScaleFactor)
                $calcH = [math]::Round($inputH * $ScaleFactor)

                # Enforce Mod2 (even numbers) for codec compatibility
                if ($calcW % 2 -ne 0) { $calcW++ }
                if ($calcH % 2 -ne 0) { $calcH++ }

                $w_str = "$calcW"
                $h_str = "$calcH"
                Write-Verbose "Using scale factor $ScaleFactor. Calculated resolution: ${w_str}x${h_str}"
            } elseif ($TargetResolutionH -le 0) {
                $h_str = "-2" # Auto-height
                Write-Verbose "Auto-Height enabled (aspect ratio preserved, Mod2 enforced)"
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

            $ALL_STREAMS = '^-c .*', '^-map 0$'

            # --- Handle Audio Overrides ---
            $allowAudio = -not ($inputLimitations -contains 'no_audio' -or $outputLimitations -contains 'no_audio')
            if ($allowAudio) {
                $transcodeAudioRequested = -not [string]::IsNullOrWhiteSpace($AudioCodecForTranscode)
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
                            StreamInfoB64   = $probeDataB64
                        }
                        $transcodeResult = Invoke-ExternalScript -ScriptPath $transcodeAudioScript -Parameters $transcodeParams -TaskDescription "Retrieving audio transcode args" -CaptureOutput
                        if (($transcodeResult.ExitCode -eq 0 -or $transcodeResult.ExitCode -eq -2) -and $transcodeResult.Output) {
                            $transcodeAudioArgs = $transcodeResult.Output
                        } else {
                            if ($transcodeResult.ExitCode -ne -2) { Write-Warning "Failed to get audio transcode args (Exit Code: $($transcodeResult.ExitCode))." }
                        }
                    }

                    # --- Set Audio Track Priority ---
                    if ($DoSetAudioPriority) {
                        $priorityParams = @{
                            Path            = $inputFileFullPath
                            Type            = 'Audio'
                            Lang            = $AudioLangPriorityForSet
                            Title           = $AudioTitlePriorityForSet
                            FfmpegPath      = $ffmpeg
                            FfprobePath     = $ffprobe
                            Concise         = $true
                            Verbose         = $false
                            PassThru        = $true
                            StreamInfoB64   = $probeDataB64
                        }
                        $priorityResult = Invoke-ExternalScript -ScriptPath $setTrackPriorityScript -Parameters $priorityParams -TaskDescription "Retrieving audio disposition args" -CaptureOutput
                        if (($priorityResult.ExitCode -eq 0 -or $priorityResult.ExitCode -eq -2) -and $priorityResult.Output) {
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
                        $audioFilter = '^-c:a.* .+', '^-disposition:a.* .+', '^-b:a.* .+', '^-ac.* .+', '^-ar .*', '^-af .*'
                        $audioMapArgs = Select-ParameterPairs -ArgumentList $audioArgs -Filter '^-map 0:\d+' -Regex -Whitelist
                        if ($audioMapArgs.Count -gt 0) {
                            $audioFilter = (,'^-map 0:a.*') + $audioFilter
                        }
                        $streamArgs = Select-ParameterPairs -ArgumentList $streamArgs -Filter ($audioFilter + $ALL_STREAMS) -Regex
                        $streamArgs += $audioMapArgs + (Select-ParameterPairs -ArgumentList $audioArgs -Filter $audioFilter -Regex -Whitelist)
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
                    Path            = $inputFileFullPath
                    Type            = 'Subtitle'
                    Lang            = $SubsLangPriorityForSet
                    Title           = $SubsTitlePriorityForSet
                    FfmpegPath      = $ffmpeg
                    FfprobePath     = $ffprobe
                    Concise         = $true
                    Verbose         = $false
                    PassThru        = $true
                    StreamInfoB64   = $probeDataB64
                }
                $result = Invoke-ExternalScript -ScriptPath $setTrackPriorityScript -Parameters $setSubsParams -TaskDescription "Retrieving subtitle prioritization args" -CaptureOutput
                if (($result.ExitCode -eq 0 -or $result.ExitCode -eq -2) -and $result.Output) {
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
                        $streamArgs += Select-ParameterPairs -ArgumentList $newSubsArgs -Filter ($subsFilter + (,'^-map 0:\d+$')) -Regex -Whitelist
                    }
                } else {
                    if ($result.ExitCode -ne -2) { Write-Warning "Failed to get subtitle arguments from set-track-priority.ps1 (Exit Code: $($result.ExitCode)). Subtitle handling may be incorrect." }
                }

                if (-not $allowOutputSubs -and -not $Concise) { Write-Host "Skipping subtitle stream mapping due to output container limitations ($OutputExt), but extraction may still occur." }
            } elseif (-not $allowInputSubs) {
                if (-not $Concise) { Write-Host "Skipping subtitle streams due to input container limitations ($inputExt)." }
            }

            # --- Extract Subtitles ---
            if ($DoExtractSubs) {
                if (-not (Test-Path -LiteralPath $extractTracksScript -PathType Leaf)) {
                    Write-Warning "ExtractSubs flag is set, but script not found: $extractTracksScript. Skipping subtitle extraction."
                } else {
                    if (-not $Concise) { Write-Host "`n--- Extracting Subtitles ---" }
                    $extractParams = @{
                        Path            = $inputFileFullPath
                        Type            = 'Subtitle'
                        Format          = $SubFormatForExtract
                        Suffix          = $OutputSuffix
                        Force           = $ForceProcessing
                        FfmpegPath      = $ffmpeg
                        FfprobePath     = $ffprobe
                        Concise         = $true
                        Verbose         = $false
                        OverrideDefault = $prioritizedSubStreamIndex
                        StreamInfoB64   = $probeDataB64
                    }

                    $exitCode = Invoke-ExternalScript -ScriptPath $extractTracksScript -Parameters $extractParams -TaskDescription "Subtitle extraction"

                    if ($Concise) {
                        switch($exitCode) {
                            0 { Write-Host "  Subtitles extracted successfully!" }
                            -2 { Write-Host "  Subtitles already extracted." }
                            default { Write-Warning "  Subtitle extraction subprocess indicated failure (Exit Code: $exitCode) for '$inputFileFullPath'. Check script output for details." }
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
            $subtitleMaps = Select-ParameterPairs -ArgumentList $streamArgs -Filter '^-map 0:s.*' -Regex -Whitelist
            if ($subtitleMaps.Count -gt 0) {
                Write-Verbose "Found subtitle maps to move to end: $($subtitleMaps -join ', ')"
                $streamArgs = Select-ParameterPairs -ArgumentList $streamArgs -Filter '^-map 0:s.*' -Regex
                $streamArgs += $subtitleMaps
            }

            $dataMaps = Select-ParameterPairs -ArgumentList $streamArgs -Filter '^-map 0:d.*' -Regex -Whitelist
            if ($dataMaps.Count -gt 0) {
                Write-Verbose "Found data maps to move to end: $($dataMaps -join ', ')"
                $streamArgs = Select-ParameterPairs -ArgumentList $streamArgs -Filter '^-map 0:d.*' -Regex
                $streamArgs += $dataMaps
            }

            $attachmentMaps = Select-ParameterPairs -ArgumentList $streamArgs -Filter '^-map 0:t.*' -Regex -Whitelist
            if ($attachmentMaps.Count -gt 0) {
                Write-Verbose "Found attachment maps to move to end: $($attachmentMaps -join ', ')"
                $streamArgs = Select-ParameterPairs -ArgumentList $streamArgs -Filter '^-map 0:t.*' -Regex
                $streamArgs += $attachmentMaps
            }

            $paramKeys = @{
                'libx264' = '-x264-params'
                'libx265' = '-x265-params'
                'libsvtav1' = '-svtav1-params'
            }

            # --- Colorspace Preservation ---
            $p_range = if ($videoStream.color_range) { $videoStream.color_range } else { "tv" }
            $p_space = if ($videoStream.color_space) { $videoStream.color_space } else { "bt709" }
            $p_prim  = if ($videoStream.color_primaries) { $videoStream.color_primaries } else { "bt709" }
            $p_trans = if ($videoStream.color_transfer) { $videoStream.color_transfer } else { "bt709" }

            $range_str = if ($p_range -match "tv|limited") { "limited" } else { "full" }
            $x265ColorArgs = "range=${range_str}", "colorprim=${p_prim}", "transfer=${p_trans}", "colormatrix=${p_space}"

            $uploadFmt = $pixFmt
            $outputFmt = "yuv420p10le" # if ($EncoderProfile -match "nvidia") { "p010le" } else { "yuv420p10le" } breaks libplacebo

            # --- Construct FFMPEG Command Arguments ---
            $ffmpegArgs = @('-y', '-stats')
            $ffmpegArgs += if ($Concise) { '-v', 'fatal' } else { '-v', 'warning' }
            $ffmpegArgs += $hwAccelParams
            $ffmpegArgs += '-i', "$inputFileFullPath"
            $ffmpegArgs += '-init_hw_device', 'vulkan' # libplacebo needs Vulkan

            $filterGraph = "format=${uploadFmt},setparams=color_primaries=${p_prim}:color_trc=${p_trans}:colorspace=${p_space}:range=$range_str"
            $filterGraph += ",hwupload,libplacebo=format=${outputFmt}:w=${w_str}:h=${h_str}:upscaler=bilinear:custom_shader_path='$escapedShaderPath'"
            $filterGraph += ":dithering=none:tonemapping=clip:colorspace=${p_space}:color_primaries=${p_prim}:color_trc=${p_trans}:range=$range_str"
            $filterGraph += ",hwdownload,format=${outputFmt}"
            $ffmpegArgs += '-pix_fmt', $outputFmt

            $ffmpegArgs += '-vf', "$filterGraph"
            $ffmpegArgs += $streamArgs
            $ffmpegArgs += '-c:v', $videoCodec
            $ffmpegArgs += if ($CRF -ge 0 -and $EncoderProfile -notmatch "nvidia") { '-crf', $CRF } else { '-qp', $CQP }
            $ffmpegArgs += '-strict', '-2' # Allow experimental codecs

            if ($videoCodec -eq 'libx265') {
                $encParams = $encParams + $x265ColorArgs
            } elseif ($videoCodec -match "nvenc|amf|qsv") {
                $ffmpegArgs += "-color_primaries", $p_prim
                $ffmpegArgs += "-color_trc", $p_trans
                $ffmpegArgs += "-colorspace", $p_space
                $ffmpegArgs += "-color_range", $p_range
            }

            if (-not [string]::IsNullOrWhiteSpace($presetParam)) { $ffmpegArgs += $presetParam.Split(' ') }
            if (-not [string]::IsNullOrWhiteSpace($threadParam)) { $ffmpegArgs += $threadParam.Split(' ') }
            if ($encParams.Count -gt 0) { $ffmpegArgs += $paramKeys[$videoCodec], ($encParams -join ':') }

            if ($FastStart -ge 1 -and $OutputExt -eq '.mp4') { $ffmpegArgs += '-movflags', '+faststart' }

            $ffmpegArgs += "$processingFile"

            # --- Execute FFMPEG ---
            if (-not $Concise) { Write-Host "Starting FFmpeg..." }

            if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Transcode to $outputFileFullPath")) {
                try {
                    Write-Verbose "Running: $ffmpeg $($ffmpegArgs -join ' ')"
                    & $ffmpeg @ffmpegArgs
                    $exitCode = $LASTEXITCODE
                    if (-not $Concise) { Write-Host "" }

                    if ($exitCode -ne 0) {
                        Write-Error "ffmpeg process failed (Exit Code: $exitCode) while processing '$inputFileFullPath'."
                    } else {
                        if (-not $Concise) { Write-Host "Successfully processed '$inputFileFullPath'" }
                        $success = $true
                    }
                } catch {
                    Write-Error "Error executing ffmpeg for '$inputFileFullPath': $($_.Exception.Message)"
                }

                # --- Post-processing File Actions ---
                if ($success) {
                    if ($useLocalTemp) {
                        if (-not $Concise) { Write-Host "FastStart: Moving temporary file to final destination..." -ForegroundColor Cyan }
                        try {
                            Move-Item -LiteralPath $processingFile -Destination $ffmpegTargetFile -Force -ErrorAction Stop
                            $processingFile = $ffmpegTargetFile
                        } catch {
                            Write-Error "Failed to move temp file '$processingFile' to '$ffmpegTargetFile'. Error: $($_.Exception.Message)"
                            $success = $false # Mark as failed so we don't delete source
                        }
                    }

                    if ($success) {
                        if ($DeleteOriginalFlag) {
                            if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Delete original file after successful transcode")) {
                                try {
                                    Remove-Item -LiteralPath $inputFileFullPath -Force -ErrorAction Stop
                                    if (-not $Concise) { Write-Host "Successfully deleted original file: '$inputFileFullPath'" }
                                } catch {
                                    Write-Warning "Failed to delete original file '$inputFileFullPath'. It might be in use or permissions are denied. Error: $($_.Exception.Message)"
                                }
                            } else {
                                Write-Warning "Skipping deletion of '$inputFileFullPath' due to -WhatIf."
                            }
                        } elseif ($ReplaceOriginalFlag) {
                            if ($PSCmdlet.ShouldProcess($inputFileFullPath, "Replace with processed file '$processingFile'")) {
                                try {
                                    Move-Item -LiteralPath $processingFile -Destination $inputFileFullPath -Force -ErrorAction Stop
                                    if (-not $Concise) { Write-Host "Successfully replaced original file." }
                                } catch {
                                    Write-Error "Failed to replace original file. Temp file '$processingFile' may still exist. Error: $($_.Exception.Message)"
                                }
                            } else {
                                Write-Warning "Skipping replacement of original due to -WhatIf. Temp file '$processingFile' may remain."
                            }
                        }
                    }
                } if (-not $success) { # ffmpeg or move failed
                    # Attempt to clean up potentially broken output file
                    if (Test-Path -LiteralPath $processingFile -PathType Leaf) {
                        Write-Warning "Attempting to remove potentially incomplete output file: $processingFile"
                        Remove-Item -LiteralPath $processingFile -ErrorAction SilentlyContinue
                    }
                }
            } else {
                Write-Warning "Skipping transcode for '$inputFileFullPath' due to -WhatIf."
                return # Don't proceed with post-processing if -WhatIf
            }
        } finally {
            if (-not $success) {
                Write-Host "Anime4K-Batch was interrupted, cleaning up..." -ForegroundColor Yellow
                if ($useLocalTemp -and (Test-Path -LiteralPath $processingFile -PathType Leaf)) {
                    Write-Verbose "Cleaning up local temp file: $processingFile"
                }
                # if (-not $useLocalTemp -and (Test-Path -LiteralPath $ffmpegTargetFile -PathType Leaf) -and (-not $ForceProcessing)) {
                #     Remove-Item -LiteralPath $processingFile -ErrorAction SilentlyContinue
                # }
                Remove-Item -LiteralPath $processingFile -ErrorAction SilentlyContinue
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
                    Write-Host "Progress: $processedCount / $totalFiles - Processing '$($file.Name)'" -ForegroundColor Green

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
                                        -ReplaceOriginalFlag:$Replace `
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
                Write-Host "Progress: 1 / 1 - Processing '$($item.Name)'" -ForegroundColor Green

                New-TranscodedVideo -FileInput $item `
                                    -OutputExt $outputExt `
                                    -OutputSuffix $Suffix `
                                    -ForceProcessing:$Force `
                                    -DeleteOriginalFlag:$Delete `
                                    -ReplaceOriginalFlag:$Replace `
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