# Anime4K-Batch.bat - Command-Line Batch Video Upscaler

This batch script enhances the resolution of videos using GLSL shaders like [Anime4K](https://github.com/bloc97/Anime4K), leveraging the power of `ffmpeg` for processing. It's designed for command-line and drag-and-drop batch operations.

**This script provides a command-line interface for the core upscaling logic, based on Anime4K-GUI, allowing for batch processing and customization via script editing.**

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Configuration](#configuration)
- [Usage](#usage)
- [Limitations](#limitations)
- [Credits](#credits)

## Features

*   Video upscaling using configurable GLSL shaders (e.g., Anime4K, FSRCNNX).
*   Batch processing of multiple video files or folders (optionally recursively).
*   Command-line interface with options for customization.
*   Drag-and-drop support for files and folders.
*   Support for various video encoders: H.264, H.265, AV1 (CPU and GPU).
*   Hardware acceleration via NVIDIA NVENC (CUDA) and AMD AMF (OpenCL).
*   Preserves all audio and subtitle streams (requires MKV output for subtitles).
*   Supports MP4, AVI, and MKV container formats for input/output.
*   Automatic detection of `ffmpeg`/`ffprobe` via system PATH (can be disabled).

## Requirements

*   **Operating System**: Windows
*   **ffmpeg.exe**: Required for video processing. Must be in the system PATH, the working directory, or its location specified within the script.
*   **ffprobe.exe**: Required for video analysis. Must be in the system PATH or its location specified within the script.
*   **GLSL Shaders**: Upscaling shader files (e.g., `.glsl`) are provided in this repository.

## Configuration

Core settings are configured by editing the `SETTINGS` section directly within the `Anime4K-Batch.bat` script file:

*   `TARGET_RESOLUTION_W`, `TARGET_RESOLUTION_H`: Desired output video dimensions.
*   `SHADER_FILE`: The specific `.glsl` shader file to use (relative to `SHADER_BASE_PATH`).
*   `SHADER_BASE_PATH`: The directory containing the shader files.
*   `ENCODER_PROFILE`: Selects the video codec and hardware acceleration (e.g., `nvidia_h264`, `cpu_av1`, `amd_h265`), set to `nvidia_h265` by default. See script comments for options.
*   `CQP`: Constant Quantization Parameter for quality control (lower value = higher quality, larger file).
*   `OUTPUT_FORMAT`: Output video container (`mkv`, `mp4`, `avi`). MKV is recommended for subtitle compatibility.
*   `OUTPUT_SUFFIX`: Text added to the end of the output filename (before the extension).
*   `FFMPEG_PATH`, `FFPROBE_PATH`: Manually specify paths if automatic detection fails or is disabled.
*   `CPU_THREADS`: Limit CPU core usage for CPU-based encoders.

### Codecs compatibility table
|       | NVIDIA | AMD | Intel | CPU |
|:------|:------:|:---:|:-----:|:---:|
| H.264 |   ✅    |  ✅  |   ❌   |  ✅  |
| H.265 |   ✅    |  ✅  |   ❌   |  ✅  |
| AV1   |   ⚠️    |  ⚠️  |   ❌   |  ✅  |

**Hardware accelerated AV1 for NVIDIA and AMD is supported only on RTX 4000+ and RX 7000+ series respectively**

## Usage

There are two main ways to use the script:

1.  **Drag and Drop:**
    *   Select one or more video files or folders containing videos.
    *   Drag them directly onto the `Anime4K-Batch.bat` file icon. Processing will start with the settings defined inside the script.

    <img src="image.png" alt="Dragging files onto Anime4K-Batch.bat" width="288">

3. **Open with `Anime4K-Batch.bat`:**
    *   Right-click on a video file or folder and select "Open with" from the context menu.

    <img src="image-1.png" alt="Open with" height="288">

    *   The script will start with the settings defined inside the script.

4. **Add to Context Menu:**
    *   Execute this command in elevated PowerShell: `New-Item -Path "Registry::HKEY_CURRENT_USER\Software\Classes\*\shell\Open with Anime4K-Batch\command" -Force; Set-ItemProperty -Path "Registry::HKEY_CURRENT_USER\Software\Classes\*\shell\Open with Anime4K-Batch\command" -Name "(Default)" -Value "C:\path\to\Anime4K-Batch.bat"` (replace with the path to the script).
    *   The script should now be available whenever you right-click on video files and folders.
    
    <img src="image-2.png" alt="Open with" height="288">

### Command Line Options & Flags

Options allow overriding settings defined inside the script *for that specific run*. Flags modify behavior.

*   `-w <width>`: Override target width.
*   `-h <height>`: Override target height.
*   `-shader <file>`: Override shader filename (relative to shader path).
*   `-shaderpath <path>`: Override the base path for shaders.
*   `-cqp <value>`: Override the Constant Quantization Parameter (quality).
*   `-r`: **(Flag)** Process folders recursively. *Must be placed immediately before the folder path it applies to.*
*   `-f`: **(Flag)** Force overwrite if an output file with the target name already exists. *Must be placed immediately before the file/folder path it applies to.*
*   `-no-where`: **(Flag)** Disable automatic searching for `ffmpeg`/`ffprobe` in the system PATH; rely solely on paths set in the script.

### Output

Upscaled video files are saved in the *same directory* as their corresponding input files. The filename will be the original name plus the configured `OUTPUT_SUFFIX` (default: `_upscaled`).

## Limitations

1.  **Subtitles:** If input files contain subtitle streams, you *must* use `mkv` as the `OUTPUT_FORMAT` to preserve them. Other formats like `mp4` may discard subtitles.
2.  **HDR:** While the script attempts basic detection, proper HDR preservation is best handled by AV1 encoders (`cpu_av1`, `nvidia_av1`, `amd_av1`). Using other encoders with HDR input may result in non-HDR output.
3.  **Error Handling:** Basic checks are included, but complex `ffmpeg` errors might require manual inspection of the command output.

## Credits

*   Based on the core `ffmpeg` logic in [Anime4K-GUI](https://github.com/mikigal/Anime4K-GUI).
*   Utilizes [Anime4K](https://github.com/bloc97/Anime4K) GLSL shaders (or other compatible shaders provided by the user).
*   Relies heavily on the [FFmpeg](https://ffmpeg.org) project.
*   [Google](https://gemini.google.com) for Gemini, which was helpful in creating _this_ README :D
