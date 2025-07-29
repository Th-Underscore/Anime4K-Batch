<#
.SYNOPSIS
    Discovers, tests, and categorizes available FFmpeg GPU-accelerated video encoders.

.DESCRIPTION
    This script automates the process of testing FFmpeg GPU codecs.
    1. Creates a dummy video and a passthrough shader for testing.
    2. Identifies potential GPU encoders (NVENC, QSV, AMF, VAAPI) from `ffmpeg -encoders`.
    3. For each identified codec, it runs a specific FFmpeg upscaling command.
    4. It collects all codecs that execute without errors.
    5. Finally, it presents a categorized list of the successful codecs.

.PARAMETER ShaderFilePath
    Path to the shader to test.

.NOTES
    Requires ffmpeg.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
    [string]$ShaderFilePath
)

# --- Script Configuration ---
$dummyFileName = "dummy_test_video"
$dummyInputFile = Join-Path -Path $PSScriptRoot -ChildPath "${dummyFileName}.mkv"
if (-not $ShaderFilePath) {
    $ShaderFilePath = (Get-ChildItem (Join-Path -Path (Split-Path -LiteralPath (Split-Path -LiteralPath $PSScriptRoot)) -ChildPath 'shaders/*.glsl'))[0].FullName
    Write-Host "Using first shader file found: $ShaderFilePath" -ForegroundColor Green
    #$ShaderFilePath = Join-Path -Path $PSScriptRoot -ChildPath "passthrough.glsl";
    #$doGenerateShader = $true
}
$escapedShaderPath = $ShaderFilePath -replace '\\', '\\\\' `
                                     -replace ':', '\:' `
                                     -replace '''', '\\\\''\\\\''' # No way to escape apostrophes
$outputFilePrefix = Join-Path -Path $PSScriptRoot -ChildPath "test_output"
# ----------------------------

function New-DummyVideo {
    param(
        [string]$Path
    )
    Write-Host "Creating dummy video file at '$Path'..." -ForegroundColor Yellow
    # Create a short, low-resolution test pattern video. It's fast and requires no external files.
    $arguments = @(
        '-y',                  # Overwrite output file if it exists
        '-v', 'warning'
        '-f', 'lavfi',         # libavfilter input device
        '-i', 'testsrc=duration=2:size=640x360:rate=30', # 2-second test pattern
        '-c:v', 'libx264',     # Common, fast software encoder
        '-pix_fmt', 'yuv420p', # Standard pixel format
        $Path
    )
    # Using Start-Process to hide the verbose ffmpeg output for this setup step
    $process = Start-Process ffmpeg -ArgumentList $arguments -Wait -NoNewWindow -PassThru
    if ($process.ExitCode -ne 0) {
        Write-Error "Failed to create dummy video file. Please check your ffmpeg installation."
        exit 1
    }
    Write-Host "Dummy video created successfully." -ForegroundColor Green
}

function New-DummyShader {
    param(
        [string]$Path
    )
    Write-Host "Creating passthrough shader file at '$Path'..." -ForegroundColor Yellow
    # This is a minimal libplacebo-compatible GLSL shader that just passes the texture through.
    # It's needed for the '-vf' filter chain to work.
    $shaderContent = @"
// Passthrough shader
vec4 hook_main(vec2 p) {
    return HOOK_tex(p);
}
"@
    try {
        Set-Content -Path $Path -Value $shaderContent -Encoding UTF8
        Write-Host "Shader file created successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to create shader file at '$Path'. Check permissions."
        exit 1
    }
}

# --- Main Script ---

# 1. Check for Prerequisites
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "ffmpeg not found. Please ensure it is installed and in your system's PATH."
    exit 1
}

# 2. Setup Temporary Files
New-DummyVideo -Path $dummyInputFile
if ($doGenerateShader) { New-DummyShader -Path $ShaderFilePath }

# 3. Discover Available GPU Codecs
Write-Host "`nDiscovering available GPU encoders..." -ForegroundColor Cyan
$gpuIdentifiers = 'nvenc|amf|qsv|vulkan|vaapi'
try {
    # We look for lines that start with " V" (Video encoder) and contain a GPU identifier.
    $allEncoders = ffmpeg -hide_banner -encoders 2>&1
    $retrievedCodecs = $allEncoders | Select-String -Pattern $gpuIdentifiers | ForEach-Object {
        ($_.Line.Trim() -split '\s+')[1]
    } | Sort-Object -Unique

    if ($retrievedCodecs.Count -eq 0) {
        Write-Error "No potential GPU encoders found (NVENC, AMF, QSV, Vulkan, VAAPI). Exiting."
        # Cleanup before exiting
        Remove-Item $dummyInputFile, $ShaderFilePath -ErrorAction SilentlyContinue
        exit 1
    }
    Write-Host "Found $($retrievedCodecs.Count) potential GPU codecs to test:" -ForegroundColor Green
    $retrievedCodecs | ForEach-Object { Write-Host " - $_" }
}
catch {
    Write-Error "Failed to execute 'ffmpeg -encoders'. $_"
    exit 1
}


# 4. & 5. Test Each Codec and Collect Successful Ones
Write-Host "`nStarting encoder tests..." -ForegroundColor Cyan
$successfulCodecs = @()

foreach ($currentCodec in $retrievedCodecs) {
    Write-Host "--- Testing codec: $currentCodec ---" -ForegroundColor Yellow
    $outputFile = "${outputFilePrefix}_${currentCodec}.mkv"
    
    # Construct the argument list for ffmpeg
    $ffmpegArgs = @(
        '-y',
        '-stats',
        '-v', 'warning',
        '-i', $dummyInputFile,
        '-init_hw_device', 'vulkan',
        '-vf', "format=yuv420p,hwupload,libplacebo=w=1280:h=720:upscaler=bilinear:custom_shader_path='$escapedShaderPath',format=yuv420p",
        '-map', '0:v',
        '-map', '0:a?',
        '-map', '0:s?',
        '-map', '0:d?',
        '-c:a', 'copy',
        '-c:s', 'copy',
        '-map', '0:t?',
        '-c:v', $currentCodec,
        '-qp', '24',
        $outputFile
    )

    Write-Debug "ffmpeg $($ffmpegArgs -join ' ')"

    try {
        # Execute the command
        & ffmpeg $ffmpegArgs

        # Check the exit code of the last command
        if ($LASTEXITCODE -eq 0) {
            Write-Host "SUCCESS: Codec '$currentCodec' succeeded." -ForegroundColor Green
            $successfulCodecs += $currentCodec
        }
        else {
            Write-Host "FAILURE: Codec '$currentCodec' failed with exit code $LASTEXITCODE." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "FAILURE: Command for codec '$currentCodec' threw an exception." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
    finally {
        # Clean up the specific output file for this test run
        if (Test-Path $outputFile) {
            Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# 6. Categorize Successful Codecs
$categorizedCodecs = @{
    'H.264'      = [System.Collections.Generic.List[string]]::new()
    'H.265/HEVC' = [System.Collections.Generic.List[string]]::new()
    'AV1'        = [System.Collections.Generic.List[string]]::new()
    'Other'      = [System.Collections.Generic.List[string]]::new()
}

foreach ($codec in $successfulCodecs) {
    switch -Wildcard ($codec) {
        '*264*'      { $categorizedCodecs['H.264'].Add($codec) }
        '*hevc*'     { $categorizedCodecs['H.265/HEVC'].Add($codec) }
        '*265*'      { $categorizedCodecs['H.265/HEVC'].Add($codec) }
        '*av1*'      { $categorizedCodecs['AV1'].Add($codec) }
        default      { $categorizedCodecs['Other'].Add($codec) }
    }
}

# 7. Report Final Results
Write-Host "`n"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "      FFMPEG GPU ENCODER REPORT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($successfulCodecs.Count -eq 0) {
    Write-Host "`nNo GPU encoders completed the test successfully." -ForegroundColor Red
}
else {
    foreach ($category in $categorizedCodecs.Keys) {
        if ($categorizedCodecs[$category].Count -gt 0) {
            Write-Host "`n[$category]" -ForegroundColor White
            $categorizedCodecs[$category] | ForEach-Object { Write-Host "  - $_" -ForegroundColor Green }
        }
    }
}

# 8. Suggest Usable Encoder Profiles
Write-Host "`n"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "      USABLE ENCODER PROFILES" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "Based on the successful tests, you can use the following profiles with 'glsl-transcode.ps1' or in 'config.json':"

$suggestedProfiles = [System.Collections.Generic.List[string]]::new()

foreach ($codec in $successfulCodecs) {
    $deviceName = $null
    if ($codec -like '*_nvenc') { $deviceName = 'nvidia' }
    elseif ($codec -like '*_amf') { $deviceName = 'amd' }
    elseif ($codec -like '*_qsv') { $deviceName = 'intel' }
    elseif ($codec -like '*_vulkan') { $deviceName = 'vulkan' }
    elseif ($codec -like '*_vaapi') { $deviceName = 'vaapi' }

    if (-not $deviceName) { continue }

    $encoderName = $null
    switch -Wildcard ($codec) {
        '*264*'      { $encoderName = 'h264' }
        '*hevc*'     { $encoderName = 'h265' }
        '*265*'      { $encoderName = 'h265' }
        '*av1*'      { $encoderName = 'av1' }
    }

    if ($encoderName) {
        $encoderProfile = "${deviceName}_${encoderName}"
        if (-not $suggestedProfiles.Contains($encoderProfile)) {
            $suggestedProfiles.Add($encoderProfile)
        }
    }
}

if ($suggestedProfiles.Count -gt 0) {
    $suggestedProfiles | Sort-Object | ForEach-Object { Write-Host "  - $_" -ForegroundColor Green }
} else {
    Write-Host "No corresponding encoder profiles found for the successful codecs." -ForegroundColor Yellow
}


# 9. Cleanup
Write-Host "`nCleaning up temporary files..." -ForegroundColor Yellow
Remove-Item $dummyInputFile -ErrorAction SilentlyContinue
if ($doGenerateShader) { Remove-Item $ShaderFilePath -ErrorAction SilentlyContinue }
Write-Host "Done."
