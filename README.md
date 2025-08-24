# Anime4K-Batch - Batch Video Upscaler

This batch script enhances the resolution of videos using GLSL shaders like [Anime4K](https://github.com/bloc97/Anime4K), leveraging the power of `ffmpeg` for processing. Once set up, the script can be called in [several ways](#installation--usage), however you'd like.

<img src="assets\image-1.png" alt="Custom context menu" height="279">

**This script provides a purely Windows-based alternative for the core upscaling logic of [Anime4K-GUI](https://github.com/mikigal/Anime4K-GUI), allowing for batch processing and customization via script editing.**

## Table of Contents

*   [Features](#features)
*   [Requirements](#requirements)
*   [Installation & Usage](#installation--usage)
*   [Configuration](#configuration)
*   [Extra Utilities](#extra-utilities)
*   [Limitations](#limitations)
*   [Credits](#credits)

### TL;DR

Run [`install-registry.bat`](./install_registry.bat), edit [`config.json`](./config.json), and right-click files in File Explorer.

## Features

*   Video upscaling using configurable GLSL shaders (e.g., Anime4K, FSRCNNX).
*   Batch processing of multiple video files or folders (optionally recursively).
*   Easy right-click context menu integration.
*   Command-line interface with options for customization.
*   Drag-and-drop support for files and folders.
*   Support for various video encoders: H.264, H.265, AV1 (CPU and GPU).
*   Hardware acceleration via NVIDIA NVENC (CUDA) and AMD AMF (OpenCL).
*   Preserves all audio and subtitle streams (requires MKV output for subtitles).
*   Supports MKV, MP4, and AVI container formats for input/output.
*   Automatic detection of `ffmpeg`/`ffprobe` via system PATH (can be disabled).
*   Optional subtitle extraction using [`extract-subs.bat`](#extract-subs-bat).
*   Optional default subtitle track prioritization using [`set-subs-priority.bat`](#set-subs-priority-bat).
*   Optional default audio track prioritization using [`set-audio-priority.bat`](#set-audio-priority-bat).
*   Optional audio transcoding using [`transcode-audio.bat`](#transcode-audio-bat).
*   Optional video remuxing using [`remux.bat`](#remux-bat).
*   Advanced episode file renaming using [`Rename-MediaFiles.ps1`](#Rename-MediaFiles-ps1).
*   Test for GPU codec support using [`Test-FFmpegGpuCodecs.ps1`](#Test-FFmpegGpuCodecs-ps1). There is a simple batch script for this, too: [`test-ffmpeg-gpu-codecs.bat`](./scripts/utils/test-ffmpeg-gpu-codecs.bat).

## Requirements

*   **Operating System**: Windows 10+
*   [**ffmpeg.exe** and **ffprobe.exe**](https://ffmpeg.org/download.html#build-windows): Required for video processing and analysis. Must be in the system PATH, the working directory, the installation folder, or specified within the script ([`scripts/glsl-transcode.bat`](./scripts/glsl-transcode.bat)). `--enable-vulkan --enable-libplacebo` should already be enabled in the build, but you can perform a quick test using the [`Test-FFmpegGpuCodecs.ps1`](#Test-FFmpegGpuCodecs-ps1) script.
*   **Vulkan**: Required for GLSL shader application.
*   **GLSL Shaders**: Standard Anime4K upscaling/sharpening shader files (`.glsl`) are provided in this repository.

Supported ffmpeg and ffprobe binaries can be found in [Releases](https://github.com/Th-Underscore/Anime4K-Batch/releases).

## Installation & Usage

First, download [the latest `Anime4K-Batch.zip`](https://github.com/Th-Underscore/Anime4K-Batch/releases/latest) (or clone the repository).

There are four main ways to install and use the [`Anime4K-Batch.bat`](./Anime4K-Batch.bat) script:

<details>
<summary><b>1. Add to Context Menu (Recommended)</b></summary>

1. **Standard**: Admin rights required.
    *   Execute [`install_registry.bat`](./install_registry.bat). That's it! The script should now be available whenever you right-click on video files and folders.
    *   This will add two main context menu entries:
        *   **`Anime4K-Batch`**: Executes scripts directly using the settings in `config.json`.
        *   **`Anime4K-Batch (Prompt)`**: Opens a command prompt, allowing you to enter additional command-line arguments for that specific run.
    *   If you wish to remove Anime4K-Batch from the context menu, execute [`uninstall_registry.bat`](./uninstall_registry.bat).
    *   _(Optional)_ To disable the new Windows 11 context menu for easier access, run this in Command Prompt (`cmd.exe`):

        ```cmd
        REG ADD "HKCU\Software\Classes\CLSID{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /ve /f
        ```
    * _(Optional)_ If you wish to add specific flags to the utility scripts (e.g., remux recursively using [`remux.bat`](./scripts/remux.bat)), edit the `\command` lines before executing `install_registry.bat`. For example (take note of the `-r`):

        ```cmd
        REG ADD "%ROOT_STORE%\Ani4K.Remux\command" /ve /d "\"%BASE_DIR%\scripts\remux.bat\" -r \"%%1\" & pause" /f
        ```

2. **Basic**: No admin rights required.
    *   Open PowerShell and set this variable to your path to the script:

        ```powershell
        $path = "C:\path\to\Anime4K-Batch.bat"
        ```

    *   Then execute this command:

        ```powershell
        New-Item -Path "Registry::HKEY_CURRENT_USER\Software\Classes\*\shell\Transcode with Anime4K\command" -Value "$path ""%1""" -Force; New-Item -Path "Registry::HKEY_CURRENT_USER\Software\Classes\directory\shell\Transcode content with Anime4K\command" -Value "$path ""%1""" -Force
        ```

    *   The script should now be available whenever you right-click on video files and folders.
    *   If you wish to remove Anime4K-Batch from the context menu, run the following command:

        ```powershell
        Remove-Item -Path "Registry::HKEY_CURRENT_USER\Software\Classes\*\shell\Transcode with Anime4K" -Force; Remove-Item -Path "Registry::HKEY_CURRENT_USER\Software\Classes\directory\shell\Transcode content with Anime4K" -Force
        ```

    *   _(Optional)_ To disable the new Windows 11 context menu for easier access:

        ```powershell
        New-Item -Path "Registry::HKEY_CURRENT_USER\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Value "" -Force
        ```

    </details>

</details>

<img src="assets\image-1.png" alt="Custom context menu" height="279">

<details>
<summary><b>2. Drag and Drop</b></summary>

*   Select one or more video files or folders containing videos.
*   Drag them directly onto the `Anime4K-Batch.bat` file icon. Processing will start with the settings defined in your configuration.

</details>

<img src="assets\image-2.png" alt="Dragging and dropping files" width="315">

<details>
<summary><b>3. Open with <code>Anime4K-Batch.bat</code></b></summary>

*   Right-click on a video file and select "Open with" from the context menu (not available for folders or multiple files).
*   Select "Choose an app on your PC".
*   Choose `Anime4K-Batch.bat` and click "Once".
*   The script will start with the settings defined in your configuration.

</details>

<img src="assets\image-3.png" alt="Open with" height="308">

<details>
<summary><b>4. Command Line</b></summary>

*   Open Command Prompt (`cmd.exe`) or PowerShell.
*   Navigate to the script's directory or use its absolute path.
*   Execute the script with optional flags and options, followed by paths to video files and/or folders.
*   Arguments are passed to the underlying script(s) ([`scripts/glsl-transcode.bat`](./scripts/glsl-transcode.bat) and optionally [`scripts/extract-subs.bat`](./scripts/extract-subs.bat)).

    ```batch
    C:\path\to\Anime4K-Batch.bat [options] [flags] "path\to\folder" "path\to\video.mkv" ...
    ```

#### Command Line Options & Flags

Using these options/flags override settings defined inside the script(s) *for that specific run*. Place them *before* the file/folder paths.

**Options & Flags:**

*   `-w <width>`: Override target width.
*   `-h <height>`: Override target height.
*   `-shader <file>`: Override shader filename (relative to shader path).
*   `-shaderpath <path>`: Override the base path for shaders.
*   `-codec-prof <type>`: Override encoder profile (e.g., nvidia_h265, cpu_av1).
*   `-cqp <value>`: Override the Constant Quantization Parameter (quality, 0-51).
*   `-container <type>`: Override output container format (`avi`, `mkv`, `mp4`).
*   `-suffix <string>`: Suffix to append after the base filename part (default: `_upscaled`).
*   `-sformat <string>`: Alias of `-format` option for `extract-subs.bat`.
*   `-acodec <type>`: Audio codec for transcoding (e.g., `aac`, `ac3`, `flac`). If not specified, audio will be copied.
*   `-abitrate <value>`: Audio bitrate for transcoding (e.g., `192k`, `256k`). Only applies if `-acodec` is specified.
*   `-achannels <value>`: Number of audio channels (e.g., `2` for stereo, `6` for 5.1). Only applies if `-acodec` is specified.
*   `-alang <list>`: Comma-separated audio language priority for `-aprioritize` (e.g., "jpn,eng").
*   `-atitle <list>`: Comma-separated audio title priority for `-aprioritize`.
*   `-slang <list>`: Comma-separated subtitle language priority for `-sprioritize`.
*   `-stitle <list>`: Comma-separated subtitle title priority for `-sprioritize`.
*   `-r`: **(Flag)** Process folders recursively.
*   `-f`: **(Flag)** Force overwrite if an output file with the target name already exists.
*   `-delete`: **(Flag)** Delete original file after successful transcode (USE WITH CAUTION!).
*   `-replace`: **(Flag)** Replace original file with processed version (USE WITH CAUTION!).
*   `-sprioritize`: **(Flag)** Set default subtitle track on the *input* file using `set-subs-priority.bat` before transcoding.
*   `-extract-subs`: **(Flag)** Extract subtitles using `extract-subs.bat` before transcoding.
*   `-aprioritize`: **(Flag)** Set default audio track on the *output* file using `set-audio-priority.bat` after transcoding.

#### Command Line Examples

These examples demonstrate various command-line possibilities. While some are based on the default settings, others showcase specific flags and options. Note that features like subtitle extraction and default audio setting require enabling them via flags (`-extract-subs`, `-aprioritize`, etc.) or modifying [`Anime4K-Batch.bat`](./Anime4K-Batch.bat) (see [Enabling Subtitle Extraction](#enabling-subtitle-extraction)). Note that, without editing the script, `Anime4K-Batch.bat` acts as an alias for [`glsl-transcode.bat`](./glsl-transcode.bat). Adjust paths and options as needed.

*   **Upscale to 4K, set default subtitle to English "Full" track, extract it, then set default audio to Japanese "Commentary" track:**
    ```batch
    Anime4K-Batch.bat -w 3840 -h 2160 -sprioritize -slang "eng" -stitle "Full" -extract-subs -aprioritize -alang "jpn" -atitle "Commentary" "C:\path\to\video.mkv"
    ```

*   **Upscale, extract subs without specifying language, and force overwrite:**
    ```batch
    Anime4K-Batch.bat -extract-subs -sformat "SOURCE.title" -f "C:\path\to\video.mkv"
    ```

*   **Upscale to 4K with CQP 24 and transcode audio to AAC with default English priority:**
    ```batch
    Anime4K-Batch.bat -w 3840 -h 2160 -cqp 24 -aprioritize -alang "eng" -acodec aac "C:\path\to\video.mkv"
    ```

*   **Transcode audio to AAC with a bitrate of 192k and 2 channels, while upscaling to 4K:**
    ```batch
    Anime4K-Batch.bat -w 3840 -h 2160 -acodec aac -abitrate 192k -achannels 2 "C:\path\to\video.mkv"
    ```

*   **Use default settings from glsl-transcode.bat but process folders recursively and extract subs:**
    ```batch
    Anime4K-Batch.bat -r -extract-subs "C:\path\to\folder" "C:\path\to\another\video.mp4"
    ```

*   **Upscale recursively, extract subtitles, set default audio, and delete original files after successful transcode (USE WITH CAUTION!):**
    ```batch
    Anime4K-Batch.bat -r -extract-subs -aprioritize -delete "C:\path\to\folder"
    ```

</details>

Note: Running the script twice in the same directory should double the worker threads/cores, without any conflict or additional overhead. From my experience (NVIDIA V100), GPU usage isn't maxed unless two processes are running at the same time.

Using this method, `Anime4K_ModeA_A-fast.glsl` (Fast) performs at more than double the speed of `Anime4K_ModeA_A.glsl` (HQ), whereas trying to run two HQ transcoding processes tends to cause a bottleneck with Graphics performance, due to the nature of GLSL shaders.

### Output

Upscaled video files are saved in the *same directory* as their corresponding input files. The filename will be the original name plus the configured `OUTPUT_SUFFIX` (default: `_upscaled`) in [`glsl-transcode.bat`](./scripts/glsl-transcode.bat). Extracted subtitles (if enabled) are also saved in the same directory, named according to the `-format` option in [`extract-subs.bat`](./scripts/extract-subs.bat).

## Configuration

The primary method for configuring Anime4K-Batch is by editing the `config.json` file, located in the root directory alongside `Anime4K-Batch.bat`. This file allows you to set persistent default values for nearly all script options, making it the recommended way to customize behavior.

Settings in `config.json` are automatically loaded by the scripts. For temporary overrides for a specific run, or for scripting particular behaviors, command-line flags can be used.

<details>
<summary><b>1. Using <code>config.json</code> (Recommended)</b></summary>

Edit the `config.json` file using any text editor. This file uses a simple JSON format to define various settings. Changes saved to `config.json` will apply to subsequent runs of `Anime4K-Batch.bat` and its associated scripts (like `glsl-transcode.bat`, `extract-subs.bat`, etc.), provided they support reading this configuration file.

**Example `config.json` structure:**
```json
{
    // --- Input/Output ---
    "Suffix": "_upscaled",           // Suffix to append to output filenames.
    "Container": "mkv",              // Output container format (e.g., 'mkv', 'mp4').
    "Force": false,                  // Force overwrite existing output files.
    "Recurse": false,                // Process folders recursively.

    // --- Transcoding Settings ---
    "TargetResolutionW": 3840,       // Target output width.
    "TargetResolutionH": 2160,       // Target output height.
    "ShaderFile": "Anime4K_ModeA_A-fast.glsl", // Shader filename located in ShaderBasePath.
    "EncoderProfile": "nvidia_h265", // Encoder profile (e.g., cpu_h264, nvidia_h265).
    "CQP": 24,                       // Constant Quantization Parameter (quality).

    // ... and many more settings.
    // For a full list and detailed descriptions, please refer to the actual 'config.json' file.
}
```
Ensure your `config.json` is valid JSON (single-line comments are permitted).
</details>

<details>
<summary><b>2. Command-Line Flags (Respective values override <code>config.json</code>)</b></summary>

You can override settings from `config.json` (and any internal script defaults) by providing command-line flags when executing `Anime4K-Batch.bat`. These flags apply *only* to that specific run and do not modify `config.json`.

This is useful for:
*   Testing different settings without changing your defaults.
*   Scripting specific one-off tasks.

For a comprehensive list of available command-line options and flags, their functions, and examples, please refer to the [Command Line Options & Flags](#command-line-options--flags) section under "Installation & Usage".

**Example:**
If `config.json` sets `TargetResolutionW` to `1920`, but you want to upscale a specific batch to `3840`, you can run:
```batch
Anime4K-Batch.bat -w 3840 "path\to\your\videos"
```

Additionally, you can modify the main `Anime4K-Batch.bat` script itself to include default flags in its execution line for `glsl-transcode.bat` or other sub-scripts. This is an older method but still functional. Flags set this way will also override `config.json` settings.
Example (editing `Anime4K-Batch.bat`):
```batch
:: Original line might be:
:: call "%~dp0\scripts\glsl-transcode.bat" %* ^
:: Modified to always
:: 1. Recurse and
:: 2. Force overwrite:
call "%~dp0\scripts\glsl-transcode.bat" -r -f %* ^
```
However, managing defaults through `config.json` is generally cleaner.
</details>

### Codecs compatibility table
|       | NVIDIA (NVENC) | AMD (AMF) | Intel (QSV) | CPU (x264/x265/SVT-AV1)  |
|:------|:--------------:|:---------:|:-----------:|:------------------------:|
| H.264 |       ✅       |    ✅    |     ✅     |            ✅            |
| H.265 |       ✅       |    ✅    |     ✅     |            ✅            |
| AV1   |       ⚠️       |    ⚠️    |     ✅     |            ✅            |

**Note on Hardware Acceleration:**
*   **VAAPI / Vulkan**: These methods should be compatible with all GPUs.
*   **NVIDIA/AMD AV1:** Supported only on RTX 4000+ and RX 7000+ series respectively.
*   **Intel QSV / VAAPI / Vulkan:** These methods are currently untested but are expected to work on compatible hardware.
*   You can verify your specific hardware and `ffmpeg` build compatibility by running the [`Test-FFmpegGpuCodecs.ps1`](#Test-FFmpegGpuCodecs-ps1) utility.

### Controlling Subtitles

Subtitle handling is managed by two separate flags that perform actions in a specific order:

1.  **`-sprioritize` (Optional):**
    *   This flag triggers [`set-subs-priority.ps1`](./scripts/powershell/set-subs-priority.ps1) to modify the **input file** in-place.
    *   It reorders the internal subtitle tracks based on language and title, marking the best match as default. This is useful for ensuring players select the correct subtitle track automatically.
    *   (optional) Use `-slang` and `-stitle` to specify priorities.

2.  **`-extract-subs` (Optional):**
    *   This flag triggers [`extract-subs.bat`](./scripts/powershell/extract-subs.ps1) to save subtitle tracks as external `.srt`, `.ass`, etc., files.
    *   This is highly recommended if your output container is `mp4`, which has poor subtitle support.
    *   If you also ran `-sprioritize`, the extracted files will reflect the new, correct track order.
    *   (optional) Use `-sformat` to control the output filename pattern.

### Setting Default Audio Priority

Similar to subtitle extraction, setting the default audio track priority using [`set-audio-priority.bat`](./scripts/set-audio-priority.bat) is primarily controlled via flags passed to [`glsl-transcode.bat`](./scripts/glsl-transcode.bat) (either directly or via [`Anime4K-Batch.bat`](./Anime4K-Batch.bat)).

1.  **Use the `-aprioritize` Flag (Optional):**
    *   (optional) Use `-slang` and `-stitle` to specify priorities.

## Extra Utilities

<details id="Join-Shaders-ps1">
<summary><b><code>Join-Shaders.ps1</code></b></summary>

This PowerShell script ([`Join-Shaders.ps1`](./scripts/utils/Join-Shaders.ps1)) allows you to combine multiple GLSL shaders into a single file compatible with `ffmpeg`'s `glsl` filter (and other applications like MPV). This is useful if you want to chain multiple shader effects for the `ShaderFile` setting in the config.

**MPV Shaderlist Format:** `~~/shader1.glsl;~~/shader2.glsl;~~/shader3.glsl`

**Standalone Usage / Command Line Options:**

```powershell
# Combine several Anime4K shaders from MPV's config folder into one file
C:\path\to\Join-Shaders.ps1 -BaseDir "$env:AppData\mpv\" -FileListString "~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Restore_CNN_M.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl;~~/shaders/Anime4K_AutoDownscalePre_x2.glsl;~~/shaders/Anime4K_AutoDownscalePre_x4.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl" -OutputFile ".\shaders\Anime4K_ComplexChain.glsl"
```

You could then use the flag `-shader Anime4K_ComplexChain.glsl` or set `"ShaderFile": "Anime4K_ModeA_A-fast.glsl"` in `config.json`.

**This is purely a PowerShell script and is not wrapped by a `.bat` file.**

</details>

<details id="extract-subs-bat">
<summary><b><code>extract-subs.bat</code></b></summary>

This batch script ([`extract-subs.bat`](./scripts/extract-subs.bat)) extracts subtitle tracks from video files using `ffprobe` and `ffmpeg`. It's designed to be run before [`glsl-transcode.bat`](./scripts/glsl-transcode.bat) if you want to preserve subtitles, especially when changing container formats (e.g., MKV to MP4).

See [Enabling Subtitle Extraction](#enabling-subtitle-extraction) (applies to both `Anime4K-Batch.bat` and `glsl-transcode.bat`).

**Standalone Usage / Command Line Options:**

You can also run [`extract-subs.bat`](./scripts/extract-subs.bat) directly.

```batch
C:\path\to\extract-subs.bat [options] [flags] "path\to\folder" "path\to\video.mkv" ...
```

*   `-format <string>`: Output filename format (default: `SOURCE.lang.title.dispo`, following [Jellyfin's naming convention](https://jellyfin.org/docs/general/server/media/external-files)). Placeholders:
    *   `SOURCE`: Original video filename (without extension).
    *   `lang`: Subtitle language code (e.g., `eng`, `jpn`).
    *   `title`: Subtitle track title, if available.
    *   `dispo`: Subtitle track disposition, if available (currently supports 'default' and 'forced').
*   `-suffix <string>`: Suffix to append after the base filename part (default: `_upscaled`).
    *   **Note:** When running `extract-subs.bat` standalone (not via `Anime4K-Batch.bat`), if you don't want *any* suffix added, use `-suffix ""`.
*   `-r`: **(Flag)** Process folders recursively.
*   `-f`: **(Flag)** Force overwrite existing subtitle files.

</details>

<details id="remux-bat">
<summary><b><code>remux.bat</code></b></summary>

This batch script ([`remux.bat`](./scripts/remux.bat)) remuxes video files into a different container format (e.g., MKV to MP4) while copying compatible streams (video, audio, subtitles, attachments, data) based on the target container's capabilities. It does *not* re-encode the video or audio, making it an extremely fast operation.

**Standalone Usage / Command Line Options:**

```batch
C:\path\to\remux.bat [options] [flags] "path\to\folder" "path\to\video.mkv" ...
```

*   `-container <string>`: Output container extension (default: `mp4`).
*   `-r`: **(Flag)** Process folders recursively.
*   `-f`: **(Flag)** Force overwrite existing output files.

</details>

<details id="transcode-audio-bat">
<summary><b><code>transcode-audio.bat</code></b></summary>

This batch script ([`transcode-audio.bat`](./scripts/transcode-audio.bat)) transcodes audio streams within video files to a specified codec and bitrate, while copying the video stream. This is useful for standardizing audio formats or reducing file size.

**Standalone Usage / Command Line Options:**

```batch
C:\path\to\transcode-audio.bat [options] [flags] "path\to\folder" "path\to\video.mkv" ...
```

*   `-codec <string>`: Target audio codec (default: `aac`).
*   `-bitrate <string>`: Target audio bitrate (default: `192k`).
*   `-delete`: **(Flag)** Delete original file after successful processing (mutually exclusive with `-replace`).
*   `-replace`: **(Flag)** Replace original file (mutually exclusive with `-delete`).
*   `-r`: **(Flag)** Process folders recursively.

</details>

<details id="set-audio-priority-bat">
<summary><b><code>set-audio-priority.bat</code></b></summary>

This batch script ([`set-audio-priority.bat`](./scripts/set-audio-priority.bat)) sets the default track based on language priority using `ffprobe` and `ffmpeg`. It remuxes the file, placing the highest priority audio track first and marking it as default. This is useful for ensuring media players select the desired language automatically.

It can be triggered automatically during transcode by using the `-aprioritize` flag in [`glsl-transcode.bat`](./scripts/glsl-transcode.bat). The language priority can be specified using the `-alang` flag and the title priority using the `-atitle` flag in `glsl-transcode.bat`.

**Standalone Usage / Command Line Options:**

```batch
C:\path\to\set-audio-priority.bat [options] [flags] "path\to\folder" "path\to\video.mkv" ...
```

*   `-lang "<list>"`: Comma-separated language priority (default: `"jpn,chi,kor,eng"`). Must be quoted if it contains commas.
*   `-title "<list>"`: Comma-separated title priority (e.g., `"Commentary,Surround"`). Must be quoted if it contains commas.
*   `-suffix <string>`: Suffix for the output filename (default: `_areordered`). Only used if `-replace` is not active.
*   `-r`: **(Flag)** Process folders recursively.
*   `-f`: **(Flag)** Force overwrite existing output files.
*   `-delete`: **(Flag)** Delete original file after successful processing (mutually exclusive with `-replace`).
*   `-replace`: **(Flag)** Replace original file with the processed version (enabled by default, mutually exclusive with `-delete`).

</details>

<details id="set-subs-priority-bat">
<summary><b><code>set-subs-priority.bat</code></b></summary>

This batch script ([`set-subs-priority.bat`](./scripts/set-subs-priority.bat)) sets the default subtitle track based on language and title priority. It remuxes the file, placing the highest priority subtitle track first and marking it as default. This is useful for ensuring media players select the desired language automatically.

It can be triggered automatically during transcode by using the `-sprioritize` flag in [`glsl-transcode.bat`](./scripts/glsl-transcode.bat). The language priority can be specified using the `-slang` flag and the title priority using the `-stitle` flag in `glsl-transcode.bat`.

**Standalone Usage / Command Line Options:**

```batch
C:\path\to\set-subs-priority.bat [options] [flags] "path\to\folder" "path\to\video.mkv" ...
```

*   `-lang "<list>"`: Comma-separated language priority (default: `"eng,jpn"`). Must be quoted if it contains commas.
*   `-title "<list>"`: Comma-separated title priority (e.g., `"Full,Dialogue,Signs"`). Must be quoted if it contains commas.
*   `-suffix <string>`: Suffix for the output filename (default: `_sreordered`). Only used if `-replace` is not active.
*   `-r`: **(Flag)** Process folders recursively.
*   `-f`: **(Flag)** Force overwrite existing output files.
*   `-delete`: **(Flag)** Delete original file after successful processing (mutually exclusive with `-replace`).
*   `-replace`: **(Flag)** Replace original file with the processed version (enabled by default, mutually exclusive with `-delete`).

</details>

<details id="Rename-MediaFiles-ps1">
<summary><b><code>Rename-MediaFiles.ps1</code></b></summary>

This PowerShell script ([`Rename-MediaFiles.ps1`](./scripts/utils/Rename-MediaFiles.ps1)) renames media files into a standard TV series format (`SxxExx`), which is useful for media servers like Plex or Jellyfin. It intelligently finds episode numbers (including decimals for specials) in existing filenames and reformats them.

The script can automatically detect the **season number** from the parent folder name (e.g., `My Show Season 1`) and the **starting episode number** from the files themselves (e.g., for absolute-ordered seasons that start at episode `25`). These can also be manually overridden.

**Standalone Usage / Command Line Options:**

```powershell
# Preview a rename for files in 'D:\TV Shows\My Series', auto-detecting the season and first episode.
C:\path\to\Rename-MediaFiles.ps1 -Path "D:\TV Shows\My Series" -WhatIf

# Rename files in current directory, auto-detecting the season and first episode.
C:\path\to\Rename-MediaFiles.ps1

# Rename files for Season 2, where the first episode is 25.
C:\path\to\Rename-MediaFiles.ps1 -SeasonNumber 2 -FirstEpisode 25 -Path "D:\TV Shows\My Series"
```

*   `-SeasonNumber <number>`: **(Optional)** The season number to use. If not provided, it's auto-detected from the parent folder name (`Season X` or `S_X_`).
*   `-Path <path>`: **(Optional)** The directory containing the files to rename. Defaults to the current directory.
*   `-Regex <pattern>` **(Optional)**: Provide a custom regex to find the episode number. The episode number must be the first capture group and the rest of the filename must be the second.
*   `-Extensions <exts>` **(Optional)**: Comma-separated list of file extensions to process.
*   `-FirstEpisode <number>`: **(Optional)** Sets the starting episode number for absolute numbering. Overrides auto-detection.
*   `-UseTitle`: **(Flag)** Use the video's title metadata instead of its filename to find the episode number. Requires `ffprobe`.
*   `-OrderByAlphabet`: **(Flag)** Ignore episode detection and rename files sequentially based on alphabetical order.
*   `-NoDetectFirstEpisode`: **(Flag)** Disables auto-detection of the first episode, assuming the first episode is `1`.
*    `-CombineData`: **(Flag)** Retrieves data from both filename and title metadata. The priority of source/episode depends on the `-UseTitle` flag.
*    `-EditTitle`: **(Flag)** Edits the file's title metadata instead of the filename.
*   `-WhatIf`: **(Flag)** Preview changes without actually renaming files. **Always use this first!**

**This is purely a PowerShell script and is not wrapped by a `.bat` file.**

</details>

<details id="Test-FFmpegGpuCodecs-ps1">
<summary><b><code>Test-FFmpegGpuCodecs.ps1</code></b></summary>

This PowerShell script ([`Test-FFmpegGpuCodecs.ps1`](./scripts/utils/Test-FFmpegGpuCodecs.ps1)) discovers, tests, and categorizes available FFmpeg GPU-accelerated video encoders. It automates checking your `ffmpeg` build and hardware for compatibility with various codecs (NVENC, AMF, QSV, etc.). This is useful for verifying that your setup can take advantage of hardware acceleration.

**Standalone Usage:**

```powershell
C:\path\to\Test-FFmpegGpuCodecs.ps1
```

The script will output a report of successful and failed codecs.

**This is purely a PowerShell script and is not wrapped by a `.bat` file.**

</details>

## Limitations

1.  **Subtitles:** If input files contain subtitle streams, you have a few options:
    *   Use `mkv` as the `Container` in [`config.json`](./config.json) to preserve them *within the video container*.
    *   Enable subtitle extraction to save them as separate files using [`extract-subs.bat`](./scripts/extract-subs.bat) (see [**Controlling Subtitles**](#controlling-subtitles)). This is recommended if outputting to e.g. `mp4` or `avi`, which have poor internal subtitle support.
2.  **HDR:** While the script attempts basic detection, proper HDR preservation is best handled by AV1 encoders (`cpu_av1`, `nvidia_av1`, `amd_av1`). Using other encoders with HDR input may result in non-HDR output.
3.  **Error Handling:** Basic checks are included, but complex `ffmpeg` errors might require manual inspection of the command output.

## Credits

*   Based on the core `ffmpeg` logic in [Anime4K-GUI](https://github.com/mikigal/Anime4K-GUI).
*   Utilizes [Anime4K](https://github.com/bloc97/Anime4K) GLSL shaders (or other compatible shaders provided by the user).
*   Relies heavily on the [FFmpeg](https://ffmpeg.org) project.
*   [Google](https://gemini.google.com) for Gemini, which was helpful in creating _this_ README :D
*   **Assets**: "Transcode" from [icon-icons](https://icon-icons.com/icon/recovery-convert/241031), "Extract" from [Veryicon](https://www.veryicon.com/icons/education-technology/edit-job-operator/extract-2.html), "Remux" from [The Noun Project](https://thenounproject.com/icon/remix-5641961/)
