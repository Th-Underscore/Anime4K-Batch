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
Encoder profile (e.g., 'nvidia_h265', 'cpu_av1'). Default: 'nvidia_h265'.
Options: cpu_h264, cpu_h265, cpu_av1, nvidia_h264, nvidia_h265, nvidia_av1, amd_h264, amd_h265, amd_av1.

.PARAMETER CQP
Constant Quantization Parameter (0-51, lower is better). Default: 24.

.PARAMETER Container
Output container format (e.g., 'mkv', 'mp4'). Default: 'mkv'.

.PARAMETER Suffix
Suffix to append to output filenames. Default: '_upscaled'.

.PARAMETER SubsLangPriority
Comma-separated subtitle language priority list for -SetSubsPriority (e.g., "jpn,eng").

.PARAMETER SubsTitlePriority
Comma-separated subtitle title priority list for -SetSubsPriority (e.g., "Full,Signs").

.PARAMETER SubFormat
Subtitle filename format for -ExtractSubs. Default: 'SOURCE.lang.title.dispo'.
Placeholders: SOURCE (base filename), lang (language code), title (stream title/tag), dispo (disposition i.e. 'default', 'forced').

.PARAMETER AudioLangPriority
Comma-separated audio language priority list for -SetAudioPriority (e.g., "jpn,eng"). Default: ''.

.PARAMETER AudioTitlePriority
Comma-separated audio title priority list for -SetAudioPriority (e.g., "Commentary,Surround").

.PARAMETER Recurse
Process folders recursively.

.PARAMETER Force
Force overwrite existing output files.

.PARAMETER SetSubsPriority
Set default subtitle track on the *input* file using set-subs-priority.ps1 before transcoding. This modifies the source file in-place.

.PARAMETER ExtractSubs
Extract subtitles from the *input* file using extract-subs.ps1 before transcoding.

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
    [ValidateSet('cpu_h264', 'cpu_h265', 'cpu_av1', 'nvidia_h264', 'nvidia_h265', 'nvidia_av1', 'amd_h264', 'amd_h265', 'amd_av1')]
    [string]$EncoderProfile = 'nvidia_h265',

    [Parameter()]
    [ValidateRange(-1, 51)]
    [int]$CQP = 24,

    [Parameter()]
    [ValidateSet('mkv', 'mp4', 'avi')] # Add more if needed
    [string]$Container = 'mkv',

    [Parameter()]
    [string]$Suffix = '_upscaled',

    [Parameter()]
    [string]$SubFormat = 'SOURCE.lang.title.dispo', # Default for Jellyfin

    [Parameter()]
    [string]$AudioLangPriority = '', # Default: Use script default

    [Parameter()]
    [string]$AudioTitlePriority = '',

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

        # 2. Script Directory
        $localPath = Join-Path $PSScriptRoot "$Name.exe"
        if (Test-Path -LiteralPath $localPath -PathType Leaf) {
            Write-Verbose "Found $Name in script directory: $localPath"
            return $localPath
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
    # Correctly pass the switch parameter using -SwitchName:$BooleanVariable syntax
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
        default {
            Write-Error "Invalid EncoderProfile selected: $EncoderProfile"
            exit 1
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
    $setSubsPriorityScript = Join-Path $PSScriptRoot "set-subs-priority.ps1"
    $extractSubsScript = Join-Path $PSScriptRoot "extract-subs.ps1"
    $setAudioPriorityScript = Join-Path $PSScriptRoot "set-audio-priority.ps1"

    # --- Container Compatibility Rules ---
    # Define conditions where certain stream types should NOT be copied.
    # Key: Container extension (e.g., '.mp4')
    # Value: Array of strings ('no_video', 'no_audio', 'no_subs')
    $containerLimitations = @{
        '.gif' = @('no_audio', 'no_subs') # GIF only contains video
        '.mp4' = @('no_subs')             # MP4 subtitle copy is often problematic
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
            [string]$TaskDescription = "External script" # For logging
        )

        if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
            Write-Warning "$TaskDescription script not found: $ScriptPath. Skipping execution."
            return -1
        }

        # Escape square brackets to avoid wildcard expansion
        $escapedScriptPath = $ScriptPath -replace '\[', '`[' -replace '\]', '`]'

        if (-not $Concise) {
            Write-Host "$TaskDescription..."
        }
        $exitCode = -1 # Default to error
        try {
            & $escapedScriptPath @Parameters *> $null
            $exitCode = $LASTEXITCODE
        } catch {
            Write-Warning "Error starting $TaskDescription process for '$ScriptPath': $($_.Exception.Message)"
            # Keep $exitCode as -1 (or other non-zero)
        }

        Write-Verbose "$TaskDescription completed with Exit Code: $exitCode for '$ScriptPath'."

        return $exitCode
    }

    # --- Function to Process a Single File ---
    function Process-SingleFile {
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
            [string]$AudioTitlePriorityForSet
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

        # --- Set Default Subtitle on INPUT if Flag is Set ---
        if ($DoSetSubsPriority) {
            if (-not (Test-Path -LiteralPath $setSubsPriorityScript -PathType Leaf)) {
                Write-Warning "SetSubsPriority flag is set, but script not found: $setSubsPriorityScript. Skipping subtitle prioritization."
            } else {
                if (-not $Concise) { Write-Host "`n--- Setting Default Subtitle Track (on Input) ---" }

                if (([string]::IsNullOrWhiteSpace($SubsLangPriorityForSet)) -and ([string]::IsNullOrWhiteSpace($SubsTitlePriorityForSet)) -and (-not $Concise)) {
                    Write-Host "SetSubsPriority flag is set, but no language or title priority specified. Using script default."
                }
                $setSubsParams = @{
                    Path    = $inputFileFullPath
                    Lang    = $SubsLangPriorityForSet
                    Title   = $SubsTitlePriorityForSet
                    Replace = $true
                    Force   = $ForceProcessing
                }

                # Use the helper function to execute the script
                $exitCode = Invoke-ExternalScript -ScriptPath $setSubsPriorityScript -Parameters $setSubsParams -TaskDescription "Set subtitle priority"

                if ($Concise) {
                    switch($exitCode) {
                        0 { Write-Host "Subtitle priority configured successfully!" }
                        -2 { Write-Host "Subtitle priority already configured." }
                        default { Write-Warning "Set subtitle priority indicated failure (Exit Code: $exitCode) for '$inputFileFullPath'. Check script output for details." }
                    }
                } else {
                    switch ($exitCode) {
                        0 { Write-Host "Subtitle priority configured successfully for '$inputFileFullPath'." }
                        -2 { Write-Host "No subtitle tracks found for '$inputFileFullPath', or it's already configured." }
                        default { Write-Warning "Set subtitle priority indicated failure (Exit Code: $exitCode) for '$inputFileFullPath'. Check script output for details." }
                    }
                    Write-Host "--- End Set Default Subtitle ---`n"
                }
            }
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
                "`"$inputFileFullPath`""
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
                # For now, error out if not found.
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
        $mapArgs = @('-map', '0:v:0') # Always map the first video stream
        $inputLimitations = if ($containerLimitations.ContainsKey($inputExt)) { $containerLimitations[$inputExt] } else { @() }
        $outputLimitations = if ($containerLimitations.ContainsKey($OutputExt)) { $containerLimitations[$OutputExt] } else { @() }

        # Map Audio?
        if (-not ($inputLimitations -contains 'no_audio' -or $outputLimitations -contains 'no_audio')) {
            Write-Verbose "Mapping audio streams (copying)."
            $mapArgs += '-map', '0:a?', '-c:a', 'copy'
        } elseif (-not $Concise) {
            Write-Host "Skipping audio streams due to container limitations ($inputExt -> $OutputExt)."
        }

        # Map Subtitles?
        if (-not ($inputLimitations -contains 'no_subs' -or $outputLimitations -contains 'no_subs')) {
            Write-Verbose "Mapping subtitle streams (copying)."
            $mapArgs += '-map', '0:s?', '-c:s', 'copy'
        } elseif (-not $Concise) {
            Write-Host "Skipping subtitle streams due to container limitations ($inputExt -> $OutputExt)."
            if (-not $DoExtractSubs) {
                Write-Host "Consider using -ExtractSubs flag."
            }
        }

        # --- Extract Subtitles if Flag is Set ---
        if ($DoExtractSubs) {
            if (-not (Test-Path -LiteralPath $extractSubsScript -PathType Leaf)) {
                Write-Warning "ExtractSubs flag is set, but script not found: $extractSubsScript. Skipping subtitle extraction."
            } else {
                if (-not $Concise) { Write-Host "`n--- Extracting Subtitles ---" }
                $extractParams = @{
                    Path    = $inputFileFullPath
                    Format  = $SubFormatForExtract
                    Suffix  = $OutputSuffix
                    Force   = $ForceProcessing
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

                if (-not $Concise) { Write-Host "--- End Subtitle Extraction ---`n" }
            }
        }
        # --- Construct FFMPEG Command Arguments ---
        # Start with -y for overwrite, then add logging based on $Concise
        $ffmpegArgs = @('-y')
        if ($Concise) {
            $ffmpegArgs += '-v', 'fatal'
        } else {
            $ffmpegArgs += '-v', 'warning'
        }
        $ffmpegArgs += '-stats'
        $ffmpegArgs += $hwAccelParams # Add HWAccel params if any
        $ffmpegArgs += '-i', "`"$inputFileFullPath`"" # Input file
        $ffmpegArgs += '-init_hw_device', 'vulkan' # Libplacebo needs Vulkan
        # The filtergraph needs careful quoting, especially the shader path
        $filterGraph = "format=$pixFmt,hwupload,libplacebo=w=$TargetResolutionW`:h=$TargetResolutionH`:upscaler=bilinear`:custom_shader_path='$escapedShaderPath',format=$pixFmt"
        $ffmpegArgs += '-vf', "`"$filterGraph`""
        $ffmpegArgs += $mapArgs # Add stream mapping args
        $ffmpegArgs += '-c:v', $videoCodec # Video codec
        $ffmpegArgs += '-qp', $CQP # Quality parameter
        if (-not [string]::IsNullOrWhiteSpace($presetParam)) { $ffmpegArgs += $presetParam.Split(' ') } # Preset
        if (-not [string]::IsNullOrWhiteSpace($threadParam)) { $ffmpegArgs += $threadParam.Split(' ') } # Threads
        $ffmpegArgs += "`"$outputFileFullPath`"" # Output file

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
                # Use & operator for execution
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


        # --- Set Default Audio if Flag is Set ---
        if ($DoSetAudioPriority -and (Test-Path -LiteralPath $outputFileFullPath -PathType Leaf)) {
            if (-not (Test-Path -LiteralPath $setAudioPriorityScript -PathType Leaf)) {
                Write-Warning "SetAudioPriority flag is set, but script not found: $setAudioPriorityScript. Skipping setting default audio."
            } else {
                if (-not $Concise) { Write-Host "`n--- Setting Default Audio Track ---" }

                if ([string]::IsNullOrWhiteSpace($AudioLangPriorityForSet) -and (-not $Concise)) {
                    Write-Host "SetAudioPriority flag is set, but no language priority specified via -AudioLangPriority. Using default."
                }
                $setAudioParams = @{
                    Path    = $outputFileFullPath
                    Lang    = $AudioLangPriorityForSet
                    Title   = $AudioTitlePriorityForSet
                    Replace = $true
                    Force   = $ForceProcessing
                }

                # Use the helper function to execute the script
                $exitCode = Invoke-ExternalScript -ScriptPath $setAudioPriorityScript -Parameters $setAudioParams -TaskDescription "Set audio priority"

                if ($Concise) {
                    switch($exitCode) {
                        0 { Write-Host "Audio priority configured successfully!" }
                        -2 { Write-Host "Audio priority already configured." }
                        default { Write-Warning "Set audio priority indicated failure (Exit Code: $exitCode) for '$outputFileFullPath'. Check script output for details." }
                    }
                } else {
                    switch ($exitCode) {
                        0 { Write-Host "Audio priority configured successfully for '$outputFileFullPath'." }
                        -2 { Write-Host "No audio tracks found for '$outputFileFullPath', or it's already configured." }
                        default { Write-Warning "Set audio priority indicated failure (Exit Code: $exitCode) for '$outputFileFullPath'. Check script output for details." }
                    }
                    Write-Host "--- End Set Default Audio ---`n"
                }
            }
        }

        # --- Delete Original File if Flag is Set ---
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
    } # End Function Process-SingleFile

} # End Begin block

process {
    foreach ($itemPath in $Path) {
        Write-Verbose "Processing argument: $itemPath"
        try {
            $item = Get-Item -LiteralPath $itemPath -ErrorAction Stop
            $videoExtensions = @(".mkv", ".mp4", ".avi", ".gif") # Add more if needed
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
                    Process-SingleFile -FileInput $file `
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
                                       -SubsTitlePriorityForSet $SubsTitlePriority
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

                Process-SingleFile -FileInput $item `
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
                                   -SubsTitlePriorityForSet $SubsTitlePriority
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
}