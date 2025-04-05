# Anime4K-Batch - Batch Video Upscaler

This batch script enhances the resolution of videos using GLSL shaders like [Anime4K](https://github.com/bloc97/Anime4K), leveraging the power of `ffmpeg` for processing. Once set up, the script can be called in [several ways](#usage), however you'd like.

<img src="image-1.png" alt="Custom context menu" height="279">

**This script provides a purely Windows-based alternative for the core upscaling logic of [Anime4K-GUI](https://github.com/mikigal/Anime4K-GUI), allowing for batch processing and customization via script editing.**

## Table of Contents

*   [Features](#features)
*   [Requirements](#requirements)
*   [Configuration](#configuration)
*   [Usage](#usage)
*   [Extra Utilities](#extra-utilities)
*   [Limitations](#limitations)
*   [Credits](#credits)

## Features

*   Video upscaling using configurable GLSL shaders (e.g., Anime4K, FSRCNNX).
*   Batch processing of multiple video files or folders (optionally recursively).
*   Easy right-click context menu integration.
*   Command-line interface with options for customization.
*   Drag-and-drop support for files and folders.
*   Support for various video encoders: H.264, H.265, AV1 (CPU and GPU).
*   Hardware acceleration via NVIDIA NVENC (CUDA) and AMD AMF (OpenCL).
*   Preserves all audio and subtitle streams (requires MKV output for subtitles).
*   Supports MP4, AVI, and MKV container formats for input/output.
*   Automatic detection of `ffmpeg`/`ffprobe` via system PATH (can be disabled).
*   Optional subtitle extraction using `extract-subs.bat`, configurable via `Anime4K-Batch.bat` or the `-extract-subs` flag in `glsl-transcode.bat`.

## Requirements

*   **Operating System**: Windows 10+
*   [**ffmpeg.exe** and **ffprobe.exe**](https://ffmpeg.org/download.html#build-windows): Required for video processing and analysis. Must be in the system PATH, the working directory, or specified within the script (`glsl-transcode.bat`).
*   **GLSL Shaders**: Standard Anime4K upscaling/sharpening shader files (`.glsl`) are provided in this repository.

Supported ffmpeg and ffprobe binaries can be found in [Releases](https://github.com/Th-Underscore/Anime4K-Batch/releases).

## Usage

There are four main ways to use the `Anime4K-Batch.bat` script:

<details>
<summary><b>1. Add to Context Menu</b></summary>

*   Open PowerShell (user or admin) and set this variable to your path to the script:

    ```powershell
    $path = "C:\path\to\Anime4K-Batch.bat"
    ```

*   Then execute this command:

    ```powershell
    New-Item -Path "Registry::HKEY_CURRENT_USER\Software\Classes\*\shell\Transcode with Anime4K\command" -Value "$path ""%1""" -Force; New-Item -Path "Registry::HKEY_CURRENT_USER\Software\Classes\directory\shell\Transcode content with Anime4K\command" -Value "$path ""%1""" -Force
    ```

*   The script should now be available whenever you right-click on video files and folders.
*   If you wish to remove it from the context menu, run the following command:

    ```powershell
    Remove-Item -Path "Registry::HKEY_CURRENT_USER\Software\Classes\*\shell\Transcode with Anime4K" -Force; Remove-Item -Path "Registry::HKEY_CURRENT_USER\Software\Classes\directory\shell\Transcode content with Anime4K" -Force
    ```

*   _(Optional)_ To disable the new Windows 11 context menu for easier access:

    ```powershell
    New-Item -Path "Registry::HKEY_CURRENT_USER\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Value "" -Force
    ```

</details>

<img src="image-1.png" alt="Custom context menu" height="279">

<details>
<summary><b>2. Drag and Drop</b></summary>

*   Select one or more video files or folders containing videos.
*   Drag them directly onto the `Anime4K-Batch.bat` file icon. Processing will start with the settings defined in your configuration.

</details>

<img src="image-2.png" alt="Dragging and dropping files" width="315">

<details>
<summary><b>3. Open with <code>Anime4K-Batch.bat</code></b></summary>

*   Right-click on a video file and select "Open with" from the context menu (not available for folders or multiple files).
*   Select "Choose an app on your PC".
*   Choose `Anime4K-Batch.bat` and click "Once".
*   The script will start with the settings defined in your configuration.

</details>

<img src="image-3.png" alt="Open with" height="308">

<details>
<summary><b>4. Command Line</b></summary>

*   Open Command Prompt (`cmd.exe`) or PowerShell.
*   Navigate to the script's directory or use its absolute path.
*   Execute the script with optional flags and options, followed by paths to video files and/or folders.
*   Arguments are passed to the underlying script(s) (`glsl-transcode.bat` and optionally `extract-subs.bat`).

    ```batch
    C:\path\to\Anime4K-Batch.bat [options] [flags] "path\to\folder" "path\to\video.mkv" ...
    ```

#### Command Line Options & Flags

These options/flags override settings defined inside the script(s) *for that specific run*. Place them *before* the file/folder paths.

**Common Flags (affect both `glsl-transcode.bat` and `extract-subs.bat` if enabled):**

*   `-suffix <string>`: Suffix to append to the output filename (default: `_upscaled`).
*   `-r`: **(Flag)** Process folders recursively.
*   `-f`: **(Flag)** Force overwrite if an output file with the target name already exists.
*   `-no-where`: **(Flag)** Disable automatic searching for `ffmpeg`/`ffprobe` in the system PATH; rely solely on paths set in the script or binaries in the script's directory.

**`glsl-transcode.bat` Specific Options & Flags:**

*   `-w <width>`: Override target width.
*   `-h <height>`: Override target height.
*   `-shader <file>`: Override shader filename (relative to shader path).
*   `-shaderpath <path>`: Override the base path for shaders.
*   `-cqp <value>`: Override the Constant Quantization Parameter (quality, 0-51).
*   `-container <type>`: Override output container format (`avi`, `mkv`, `mp4`).
*   `-delete`: **(Flag)** Delete original file after successful transcode (USE WITH CAUTION!).
*   `-extract-subs`: **(Flag)** Extract subtitles using `extract-subs.bat` before transcoding. Passes `-f`, `-no-where`, `-suffix`, and `-format` flags automatically.

**`extract-subs.bat` Specific Options & Flags (only relevant if subtitle extraction is enabled *via Anime4K-Batch.bat*):**

*   `-format <string>`: Output filename format for subtitles (default: `FILE.lang.title`). Uses `FILE`, `lang`, `title` placeholders.

#### Command Line Examples

These examples demonstrate various command-line possibilities. While some are based on the default settings, others showcase specific flags and options. Note that features like subtitle extraction require enabling them in `Anime4K-Batch.bat` first (see [Enabling Subtitle Extraction](#enabling-subtitle-extraction)). Adjust paths and options as needed.

*   **Upscale everything in a folder recursively to 4K using a specific shader, force overwrite, and extract subs:**
    ```batch
    Anime4K-Batch.bat -w 3840 -h 2160 -shaderpath "%appdata%\mpv\shaders" -shader Anime4K_ModeA_A.glsl -r -f "C:\path\to\input\folder"
    ```
    *(Ensure subtitle extraction is enabled in `Anime4K-Batch.bat` OR use the `-extract-subs` flag if calling `glsl-transcode.bat` directly. Common flags like `-r` and `-f` are passed automatically when extraction is enabled either way.)*

*   **Upscale to 1080p, use slightly lower quality (higher CQP), output as MP4, specify custom shaders, process recursively:**
    ```batch
    Anime4K-Batch.bat -w 1920 -h 1080 -cqp 28 -container mp4 -shaderpath "C:\MyCustomShaders" -r "C:\path\to\input"
    ```
    *(Ensure subtitle extraction is enabled, e.g., in `Anime4K-Batch.bat`, if you want subtitles extracted)*

*   **Only extract subtitles recursively, forcing overwrite:**
    ```batch
    REM If ONLY extract-subs.bat is active in Anime4K-Batch.bat
    Anime4K-Batch.bat -r -f "C:\path\to\input"
    ```

*   **Upscale specific file to 4K (CQP 24), disable PATH check, extract subs:**
    ```batch
    Anime4K-Batch.bat -w 3840 -h 2160 -cqp 24 -no-where "C:\path\to\video.mkv"
    ```
    *(Ensure subtitle extraction is enabled, e.g., in `Anime4K-Batch.bat` or via the `-extract-subs` flag if calling `glsl-transcode.bat` directly)*

*   **Use default settings but process recursively:**
    ```batch
    Anime4K-Batch.bat -r "C:\path\to\folder" "C:\path\to\another\video.mp4"
    ```

*   **Upscale recursively and delete original files (USE WITH CAUTION!), extract subs first:**
    ```batch
    Anime4K-Batch.bat -r -delete "C:\path\to\folder"
    ```
    *(Ensure subtitle extraction is enabled, e.g., in `Anime4K-Batch.bat`)*

</details>

Note: Running the script twice in the same directory should double the worker threads/cores, without any conflict or additional overhead. From my experience (NVIDIA V100), GPU usage isn't maxed unless two processes are running at the same time.

Using this method, `Anime4K_ModeA_A-fast.glsl` (Fast) performs at more than double the speed of `Anime4K_ModeA_A.glsl` (HQ), whereas trying to run two HQ transcoding processes tends to cause a bottleneck with Graphics performance, due to the nature of GLSL shaders.

### Output

Upscaled video files are saved in the *same directory* as their corresponding input files. The filename will be the original name plus the configured `OUTPUT_SUFFIX` (default: `_upscaled`) in `glsl-transcode.bat`. Extracted subtitles (if enabled) are also saved in the same directory, named according to the `-format` option in `extract-subs.bat`.

## Configuration

There are two main methods of configuring the script.

<details>
<summary><b>Standard</b></summary>

Specifying these options/flags in [the main batch script](./Anime4K-Batch.bat?plain=1#L61) will determine the script's behaviour globally.

In the script, place these flags *before* the file/folder paths. See [Anime4K-Batch.bat](./Anime4K-Batch.bat) for a full guide.

**Common Flags (affect both `glsl-transcode.bat` and `extract-subs.bat` if enabled):**

*   `-r`: **(Flag)** Process folders recursively.
*   `-f`: **(Flag)** Force overwrite if an output file with the target name already exists.
*   `-no-where`: **(Flag)** Disable automatic searching for `ffmpeg`/`ffprobe` in the system PATH; rely solely on paths set in the script or binaries in the script's directory.

**Transcoding-Specific Options & Flags:**

*   `-w <width>`: Target width.
*   `-h <height>`: Target height.
*   `-shader <file>`: Shader filename (relative to shader path).
*   `-shaderpath <path>`: Base path for shaders.
*   `-codec-prof <type>`: Encoder profile (e.g., nvidia_h265, cpu_av1).
*   `-cqp <value>`: Constant Quantization Parameter (quality, 0-51).
*   `-container <type>`: Output container format (`avi`, `mkv`, `mp4`).
*   `-delete`: **(Flag)** Delete original file after successful transcode (USE WITH CAUTION!).
*   `-extract-subs`: **(Flag)** Extract subtitles using `extract-subs.bat` before transcoding.

**Subtitle Extraction–Specific Options & Flags (only relevant if extraction enabled *via Anime4K-Batch.bat*):**

*   `-format <string>`: Output filename format for subtitles (default: `FILE.lang.title`). Uses `FILE`, `lang`, `title` placeholders.

</details>

<details>
<summary><b>Alternative</b></summary>
Advanced settings are configured by editing the `--- SETTINGS ---` section directly within the `glsl-transcode.bat` script file:

*   `TARGET_RESOLUTION_W`, `TARGET_RESOLUTION_H`: Desired output video dimensions.
*   `SHADER_FILE`: The specific `.glsl` shader file to use (relative to `SHADER_BASE_PATH`).
*   `SHADER_BASE_PATH`: The directory containing the shader files.
*   `ENCODER_PROFILE`: Selects the video codec and hardware acceleration (e.g., `nvidia_h264`, `cpu_av1`, `amd_h265`), set to `nvidia_h265` by default. See script comments for a full list of options.
*   `CQP`: Constant Quantization Parameter for quality control (lower value = higher quality, larger file).
*   `OUTPUT_FORMAT`: Output video container (`mkv`, `mp4`, `avi`). MKV is recommended for subtitle compatibility.
*   `OUTPUT_SUFFIX`: Text added to the end of the output filename (before the extension, default: `_upscaled`).
*   `FFMPEG_PATH`, `FFPROBE_PATH`: Manually specify paths if automatic detection fails or is disabled.
*   `CPU_THREADS`: Limit CPU core usage for CPU-based encoders.
*   `RECURSE_NEXT`: Set to `1` to enable recursive folder processing by default, `0` otherwise.

</details>

### Codecs compatibility table
|       | NVIDIA | AMD | Intel | CPU |
|:------|:------:|:---:|:-----:|:---:|
| H.264 |   ✅    |  ✅  |   ❌   |  ✅  |
| H.265 |   ✅    |  ✅  |   ❌   |  ✅  |
| AV1   |   ⚠️    |  ⚠️  |   ❌   |  ✅  |

**Hardware accelerated AV1 for NVIDIA and AMD is supported only on RTX 4000+ and RX 7000+ series respectively**

### Enabling Subtitle Extraction

By default, `Anime4K-Batch.bat` only runs the upscaling script (`glsl-transcode.bat`). There are two ways to enable subtitle extraction using `extract-subs.bat` before upscaling:

1.  **Modify `Anime4K-Batch.bat` (Recommended for consistent behavior):**
    *   Comment out the line: `:: %~dp0\glsl-transcode.bat %*` (add `::` at the beginning).
    *   Uncomment the line: `%~dp0\extract-subs.bat %*   &&   %~dp0\glsl-transcode.bat %*` (remove `::` from the beginning). This makes `Anime4K-Batch.bat` explicitly call `extract-subs.bat` first.
2.  **Use the `-extract-subs` Flag:**
    *   Pass the `-extract-subs` flag when calling `Anime4K-Batch.bat` or `glsl-transcode.bat`. This tells `glsl-transcode.bat` to trigger `extract-subs.bat` internally before it starts transcoding. This is useful for one-off extractions without modifying `Anime4K-Batch.bat`.

## Extra Utilities

<details>
<summary><b><code>Append-Shaders.ps1</code></b></summary>

This PowerShell script allows you to combine multiple GLSL shaders into a single file compatible with `ffmpeg`'s `glsl` filter (and potentially other applications like MPV). This is useful if you want to chain multiple shader effects for the `SHADER_FILE` setting in `glsl-transcode.bat`.

**MPV Shaderlist Format:** `~~/shader1.glsl;~~/shader2.glsl;~~/shader3.glsl`

**Usage Example** (assuming the script is in the same directory as `Anime4K-Batch.bat`):

```powershell
# Combine several Anime4K shaders from MPV's config folder into one file
.\Append-Shaders.ps1 -BaseDir "$env:AppData\mpv\" -FileListString "~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Restore_CNN_M.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl;~~/shaders/Anime4K_AutoDownscalePre_x2.glsl;~~/shaders/Anime4K_AutoDownscalePre_x4.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl" -OutputFile ".\shaders\Anime4K_ComplexChain.glsl"
```

You could then use the flag `-shader Anime4K_ComplexChain.glsl` or set `SHADER_FILE=Anime4K_ComplexChain.glsl` in `glsl-transcode.bat`.

</details>

<details>
<summary><b><code>extract-subs.bat</code></b></summary>

This batch script extracts subtitle tracks from video files using `ffprobe` and `ffmpeg`. It's designed to be run before `glsl-transcode.bat` if you want to preserve subtitles, especially when changing container formats (e.g., MKV to MP4).

**How it's used:**

*   **Via `Anime4K-Batch.bat`:** Edit `Anime4K-Batch.bat` to uncomment the line that runs both `extract-subs.bat` and `glsl-transcode.bat`. See [Enabling Subtitle Extraction](#enabling-subtitle-extraction).
*   **Via `glsl-transcode.bat`:** Use the `-extract-subs` flag when calling `glsl-transcode.bat` (either directly or passed through `Anime4K-Batch.bat`). This flag makes `glsl-transcode.bat` call `extract-subs.bat` internally.

**Standalone Usage / Command Line Options:**

You can also run `extract-subs.bat` directly.

```batch
C:\path\to\extract-subs.bat [options] [flags] "path\to\folder" "path\to\video.mkv" ...
```

*   `-format <string>`: Output filename format (default: `FILE.lang.title`, following [Jellyfin's naming convention](https://jellyfin.org/docs/general/server/media/external-files)). Placeholders:
    *   `FILE`: Original video filename (without extension).
    *   `lang`: Subtitle language code (e.g., `eng`, `jpn`).
    *   `title`: Subtitle track title, if available.
*   `-suffix <string>`: Suffix to append after the base filename part (default: `_upscaled`).
    *   **Note:** When running `extract-subs.bat` standalone (not via `Anime4K-Batch.bat`), if you don't want *any* suffix added, use `-suffix ""`.
*   `-r`: **(Flag)** Process folders recursively.
*   `-f`: **(Flag)** Force overwrite existing subtitle files.
*   `-no-where`: **(Flag)** Disable automatic `ffmpeg`/`ffprobe` detection via PATH.

</details>

## Limitations

1.  **Subtitles:** If input files contain subtitle streams, you have a few options:
    *   Use `mkv` as the `OUTPUT_FORMAT` in `glsl-transcode.bat` to preserve them *within the video container*.
    *   Enable subtitle extraction (either by modifying `Anime4K-Batch.bat` or using the `-extract-subs` flag in `glsl-transcode.bat`) to save them as separate files. This is recommended if outputting to `mp4` or `avi`, which have poor internal subtitle support.
2.  **HDR:** While the script attempts basic detection, proper HDR preservation is best handled by AV1 encoders (`cpu_av1`, `nvidia_av1`, `amd_av1`). Using other encoders with HDR input may result in non-HDR output.
3.  **Error Handling:** Basic checks are included, but complex `ffmpeg` errors might require manual inspection of the command output.

## Credits

*   Based on the core `ffmpeg` logic in [Anime4K-GUI](https://github.com/mikigal/Anime4K-GUI).
*   Utilizes [Anime4K](https://github.com/bloc97/Anime4K) GLSL shaders (or other compatible shaders provided by the user).
*   Relies heavily on the [FFmpeg](https://ffmpeg.org) project.
*   [Google](https://gemini.google.com) for Gemini, which was helpful in creating _this_ README :D
