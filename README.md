# Anime4K-Batch - Batch Video Upscaler

This batch script enhances the resolution of videos using GLSL shaders like [Anime4K](https://github.com/bloc97/Anime4K), leveraging the power of `ffmpeg` for processing. Once set up, the script can be called in [several ways](#installation--usage), however you'd like.

<img src="assets\image-1.png" alt="Custom context menu" height="279">

**This script provides a purely Windows-based alternative for the core upscaling logic of [Anime4K-GUI](https://github.com/mikigal/Anime4K-GUI), allowing for batch processing and customization via script editing.**

## Table of Contents

*   [Features](#features)
*   [Requirements](#requirements)
*   [Configuration](#configuration)
*   [Installation & Usage](#installation--usage)
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
*   Optional subtitle extraction using [`extract-subs.bat`](./scripts/extract-subs.bat), configurable via [`Anime4K-Batch.bat`](./Anime4K-Batch.bat). See [Enabling Subtitle Extraction](#enabling-subtitle-extraction).
*   Optional default audio track prioritization using [`set-audio-priority.bat`](./scripts/set-audio-priority.bat), configurable via [`Anime4K-Batch.bat`](./Anime4K-Batch.bat). See [Setting Default Audio Priority](#setting-default-audio-priority).

## Requirements

*   **Operating System**: Windows 10+
*   [**ffmpeg.exe** and **ffprobe.exe**](https://ffmpeg.org/download.html#build-windows): Required for video processing and analysis. Must be in the system PATH, the working directory, the installation folder, or specified within the script ([`scripts/glsl-transcode.bat`](./scripts/glsl-transcode.bat)).
*   **GLSL Shaders**: Standard Anime4K upscaling/sharpening shader files (`.glsl`) are provided in this repository.

Supported ffmpeg and ffprobe binaries can be found in [Releases](https://github.com/Th-Underscore/Anime4K-Batch/releases).

## Installation & Usage

First, download [the latest `Anime4K-Batch.zip`](https://github.com/Th-Underscore/Anime4K-Batch/releases/latest) (or clone the repository).

There are four main ways to install and use the [`Anime4K-Batch.bat`](./Anime4K-Batch.bat) script:

<details>
<summary><b>1. Add to Context Menu (Recommended)</b></summary>

1. **Standard**: Admin rights required.
    *   Execute [`install_registry.bat`](./install_registry.bat). That's it! The script should now be available whenever you right-click on video files and folders.
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
*   `-alang <list>`: Comma-separated audio language priority for `-set-audio-priority` (e.g., "jpn,eng").
*   `-r`: **(Flag)** Process folders recursively.
*   `-f`: **(Flag)** Force overwrite if an output file with the target name already exists.
*   `-delete`: **(Flag)** Delete original file after successful transcode (USE WITH CAUTION!).
*   `-extract-subs`: **(Flag)** Extract subtitles using `extract-subs.bat` before transcoding. Passes `-f`, `-suffix`, and `-format` (`-sformat`) flags automatically.
*   `-set-audio-priority`: **(Flag)** Set default audio track on the *output* file using `set-audio-priority.bat` after transcoding. Passes `-f` and `-lang` (`-alang`) flags automatically.

#### Command Line Examples

These examples demonstrate various command-line possibilities. While some are based on the default settings, others showcase specific flags and options. Note that features like subtitle extraction and default audio setting require enabling them via flags (`-extract-subs`, `-set-audio-priority`) or modifying [`Anime4K-Batch.bat`](./Anime4K-Batch.bat) (see [Enabling Subtitle Extraction](#enabling-subtitle-extraction)). Note that, without editing the script, `Anime4K-Batch.bat` acts as an alias for [`glsl-transcode.bat`](./glsl-transcode.bat). Adjust paths and options as needed.

*   **Upscale everything in a folder recursively to 4K using ModeA_A HQ shader in MPV's config, force overwrite, extract subs, and set default audio priority to Japanese -> Russian -> English:**
    ```batch
    Anime4K-Batch.bat -w 3840 -h 2160 -shaderpath "%appdata%\mpv\shaders" -shader Anime4K_ModeA_A.glsl -r -f -extract-subs -set-audio-priority -alang "jpn,rus,eng" "C:\path\to\input\folder"
    ```
    *(This assumes you are calling `Anime4K-Batch.bat` which passes flags to `glsl-transcode.bat`. The `-extract-subs` and `-set-audio-priority` flags trigger the respective sub-scripts)*

*   **Upscale to 1080p, use a lower quality setting (higher CQP for smaller files), output as MP4, specify a custom shader folder (using default shader file), process folders recursively, extract subs, and set default audio (using default priority):**
    ```batch
    Anime4K-Batch.bat -w 1920 -h 1080 -cqp 32 -container mp4 -shaderpath "C:\MyCustomShaders" -r -extract-subs -set-audio-priority "C:\path\to\input"
    ```

*   **Upscale, extract subs without specifying language, and force overwrite:**
    ```batch
    Anime4K-Batch.bat -extract-subs -sformat "FILE.title" -f "C:\path\to\video.mkv"
    ```

*   **Upscale to 4K with CQP 24 and set default audio to English:**
    ```batch
    Anime4K-Batch.bat -w 3840 -h 2160 -cqp 24 -set-audio-priority -alang "eng" "C:\path\to\video.mkv"
    ```

*   **Use default settings from glsl-transcode.bat but process folders recursively and extract subs:**
    ```batch
    Anime4K-Batch.bat -r -extract-subs "C:\path\to\folder" "C:\path\to\another\video.mp4"
    ```

*   **Upscale recursively, extract subtitles, set default audio, and delete original files after successful transcode (USE WITH CAUTION!):**
    ```batch
    Anime4K-Batch.bat -r -extract-subs -set-audio-priority -delete "C:\path\to\folder"
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
    "Suffix": "_upscaled",         // Suffix to append to output filenames.
    "Container": "mkv",             // Output container format (e.g., 'mkv', 'mp4').
    "Force": false,                 // Force overwrite existing output files.
    "Recurse": false,               // Process folders recursively.

    // --- Transcoding Settings ---
    "TargetResolutionW": 3840,      // Target output width.
    "TargetResolutionH": 2160,      // Target output height.
    "ShaderFile": "Anime4K_ModeA_A-fast.glsl", // Shader filename located in ShaderBasePath.
    "EncoderProfile": "nvidia_h265",// Encoder profile (e.g., cpu_h264, nvidia_h265).
    "CQP": 24,                      // Constant Quantization Parameter (quality).

    // ... and many more settings.
    // For a full list and detailed descriptions, please refer to the actual 'config.json' file.
}
```
Ensure your `config.json` is valid JSON. You can find a template or the default `config.json` in the repository.
</details>

<details>
<summary><b>2. Command-Line Flags (Overrides <code>config.json</code>)</b></summary>

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
:: call "%~dp0\scripts\glsl-transcode.bat" %*
:: Modified to always recurse and force overwrite:
call "%~dp0\scripts\glsl-transcode.bat" -r -f %*
```
However, managing defaults through `config.json` is generally cleaner.
</details>

<details>
<summary><b>3. Editing Script Variables (Legacy / Advanced)</b></summary>

Prior to the widespread use of `config.json`, default settings were primarily managed by editing variables directly within the individual script files (e.g., in the `--- SETTINGS ---` section of `scripts/glsl-transcode.bat`).

If `config.json` is present and the script is designed to read it (which is the case for the core scripts), values from `config.json` will typically take precedence over these hardcoded internal script variables.

This legacy method might still be relevant for:
*   Scripts that have not been updated to use `config.json`.
*   Advanced users who want to inspect or modify the script's deepest default behaviors.
*   Situations where `config.json` might be missing or unreadable.

The following settings, for example, can be found and edited directly in [`scripts/glsl-transcode.bat`](./scripts/glsl-transcode.bat):

*   `TARGET_RESOLUTION_W`, `TARGET_RESOLUTION_H`: Desired output video dimensions (width and height).
*   `SHADER_FILE`: The specific `.glsl` shader file to use (relative to `SHADER_BASE_PATH`).
*   `ENCODER_PROFILE`: Selects the video codec and hardware acceleration (e.g., `nvidia_h265`, `cpu_av1`). See script comments for all options.
*   `CQP`: Constant Quantization Parameter for quality control (lower value = higher quality, larger file, range: -1 to 51).
*   `OUTPUT_FORMAT`: Output video container (`mkv`, `mp4`, `avi`). MKV is recommended for subtitle compatibility.
*   `OUTPUT_EXT`: Automatically set based on `OUTPUT_FORMAT`.
*   `SUB_FORMAT`: Filename format for extracted subtitles (used by `extract-subs.bat`).
*   `CPU_THREADS`: Number of threads for CPU encoders (0 for default).
*   `OUTPUT_SUFFIX`: Text added to the end of the output filename (before the extension).
*   `FFMPEG_PATH`, `FFPROBE_PATH`: Manually specify paths to `ffmpeg.exe` and `ffprobe.exe` if automatic detection fails or is disabled.
*   `SHADER_BASE_PATH`: The directory containing the shader files (defaults to `shaders\` relative to the script).
*   `DISABLE_WHERE_SEARCH`: Set to `1` to disable searching the system PATH for `ffmpeg`/`ffprobe`.
*   `DO_RECURSE`: Set to `1` to enable recursive folder processing by default.
*   `DO_FORCE`: Set to `1` to enable overwriting existing output files by default.
*   `DO_DELETE`: Set to `1` to enable deleting original files after successful transcoding by default (USE WITH CAUTION!).
*   `DO_EXTRACT_SUBS`: Set to `1` to enable subtitle extraction by default.
*   `DO_SET_DEFAULT_AUDIO`: Set to `1` to enable setting the default audio track by default.
*   `AUDIO_LANG_PRIORITY`: Comma-separated list of preferred audio languages for `DO_SET_DEFAULT_AUDIO` (e.g., `"jpn,eng"`).

It's generally recommended to use `config.json` for configuration, as direct script edits can be overwritten by updates to the scripts.
</details>

### Codecs compatibility table
|       | NVIDIA | AMD | Intel | CPU |
|:------|:------:|:---:|:-----:|:---:|
| H.264 |   ✅    |  ✅  |   ❌   |  ✅  |
| H.265 |   ✅    |  ✅  |   ❌   |  ✅  |
| AV1   |   ⚠️    |  ⚠️  |   ❌   |  ✅  |

**Hardware accelerated AV1 for NVIDIA and AMD is supported only on RTX 4000+ and RX 7000+ series respectively**

### Enabling Subtitle Extraction

By default, [`Anime4K-Batch.bat`](./Anime4K-Batch.bat) only runs the upscaling script ([`glsl-transcode.bat`](./scripts/glsl-transcode.bat)). There are two ways to enable subtitle extraction using [`extract-subs.bat`](./scripts/extract-subs.bat) before upscaling:

1.  **Use the `-extract-subs` Flag (Recommended):**
    *   Pass the `-extract-subs` flag when calling [`Anime4K-Batch.bat`](./Anime4K-Batch.bat) or [`glsl-transcode.bat`](./scripts/glsl-transcode.bat). This tells `glsl-transcode.bat` to trigger `extract-subs.bat` internally before it starts transcoding. This is useful for one-off extractions without extensively modifying `Anime4K-Batch.bat`.
    *   Optionally, pass the `-sformat <string>` argument (e.g., `-sformat FILE`) to set a custom output filename format. If `-sformat` is not provided, `extract-subs.bat` will use its internal default priority.
2.  **Modify `Anime4K-Batch.bat`:**
    *   Comment out the line: `:: call "%~dp0\scripts\glsl-transcode.bat" %*` (add `::` at the beginning).
    *   Create a new line: `call "%~dp0\scripts\extract-subs.bat" %*   &&   call "%~dp0\scripts\glsl-transcode.bat" %*`. This makes `Anime4K-Batch.bat` explicitly call `extract-subs.bat` first.

### Setting Default Audio Priority

Similar to subtitle extraction, setting the default audio track priority using [`set-audio-priority.bat`](./scripts/set-audio-priority.bat) is primarily controlled via flags passed to [`glsl-transcode.bat`](./scripts/glsl-transcode.bat) (either directly or via [`Anime4K-Batch.bat`](./Anime4K-Batch.bat)).

1.  **Use the `-set-audio-priority` Flag (Recommended):**
    *   Pass the `-set-audio-priority` argument when calling [`Anime4K-Batch.bat`](./Anime4K-Batch.bat) or [`glsl-transcode.bat`](./scripts/glsl-transcode.bat). This tells `glsl-transcode.bat` to trigger `set-audio-priority.bat` internally *after* it finishes transcoding the output file.
    *   Optionally, pass the `-alang "<list>"` flag (e.g., `-alang "jpn,eng"`) to specify the language priority. If `-alang` is not provided, `set-audio-priority.bat` will use its internal default priority. **MUST** be quoted when multiple languages are specified.

*(Note: Unlike subtitle extraction, there isn't a simple modification to `Anime4K-Batch.bat` to* always *run `set-audio-priority.bat` after transcoding without using the flag, as the audio setting needs to operate on the* output *file from the transcode step.)*

## Extra Utilities

<details>
<summary><b><code>Append-Shaders.ps1</code></b></summary>

This PowerShell script ([`Append-Shaders.ps1`](./scripts/Append-Shaders.ps1)) allows you to combine multiple GLSL shaders into a single file compatible with `ffmpeg`'s `glsl` filter (and potentially other applications like MPV). This is useful if you want to chain multiple shader effects for the `SHADER_FILE` setting in [`glsl-transcode.bat`](./scripts/glsl-transcode.bat).

**MPV Shaderlist Format:** `~~/shader1.glsl;~~/shader2.glsl;~~/shader3.glsl`

**Standalone Usage / Command Line Options:**

```powershell
# Combine several Anime4K shaders from MPV's config folder into one file
C:\path\to\Append-Shaders.ps1 -BaseDir "$env:AppData\mpv\" -FileListString "~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Restore_CNN_M.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl;~~/shaders/Anime4K_AutoDownscalePre_x2.glsl;~~/shaders/Anime4K_AutoDownscalePre_x4.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl" -OutputFile ".\shaders\Anime4K_ComplexChain.glsl"
```

You could then use the flag `-shader Anime4K_ComplexChain.glsl` or set `SHADER_FILE=Anime4K_ComplexChain.glsl` in `scripts/glsl-transcode.bat`.

</details>

<details>
<summary><b><code>extract-subs.bat</code></b></summary>

This batch script ([`extract-subs.bat`](./scripts/extract-subs.bat)) extracts subtitle tracks from video files using `ffprobe` and `ffmpeg`. It's designed to be run before [`glsl-transcode.bat`](./scripts/glsl-transcode.bat) if you want to preserve subtitles, especially when changing container formats (e.g., MKV to MP4).

See [Enabling Subtitle Extraction](#enabling-subtitle-extraction) (applies to both `Anime4K-Batch.bat` and `glsl-transcode.bat`).

**Standalone Usage / Command Line Options:**

You can also run [`extract-subs.bat`](./scripts/extract-subs.bat) directly.

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

</details>

<details>
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

<details>
<summary><b><code>set-audio-priority.bat</code></b></summary>

This batch script ([`set-audio-priority.bat`](./scripts/set-audio-priority.bat)) sets the default track based on language priority using `ffprobe` and `ffmpeg`. It remuxes the file, placing the highest priority audio track first and marking it as default. This is useful for ensuring media players select the desired language automatically.

It can be triggered automatically after transcoding by using the `-set-audio-priority` flag in [`glsl-transcode.bat`](./scripts/glsl-transcode.bat). The language priority can be specified using the `-alang` flag in `glsl-transcode.bat`.

**Standalone Usage / Command Line Options:**

```batch
C:\path\to\set-audio-priority.bat [options] [flags] "path\to\folder" "path\to\video.mkv" ...
```

*   `-lang "<list>"`: Comma-separated language priority (default: `"jpn,chi,kor,eng"`). Must be quoted if it contains commas.
*   `-suffix <string>`: Suffix for the output filename (default: `_reordered`). Only used if `-replace` is not active.
*   `-r`: **(Flag)** Process folders recursively.
*   `-f`: **(Flag)** Force overwrite existing output files.
*   `-delete`: **(Flag)** Delete original file after successful processing (mutually exclusive with `-replace`).
*   `-replace`: **(Flag)** Replace original file with the processed version (enabled by default, mutually exclusive with `-delete`).

</details>

## Limitations

1.  **Subtitles:** If input files contain subtitle streams, you have a few options:
    *   Use `mkv` as the `OUTPUT_FORMAT` in [`glsl-transcode.bat`](./scripts/glsl-transcode.bat) to preserve them *within the video container*.
    *   Enable subtitle extraction (either by modifying [`Anime4K-Batch.bat`](./Anime4K-Batch.bat) or using the `-extract-subs` flag in [`glsl-transcode.bat`](./scripts/glsl-transcode.bat)) to save them as separate files using [`extract-subs.bat`](./scripts/extract-subs.bat). This is recommended if outputting to `mp4` or `avi`, which have poor internal subtitle support.
2.  **HDR:** While the script attempts basic detection, proper HDR preservation is best handled by AV1 encoders (`cpu_av1`, `nvidia_av1`, `amd_av1`). Using other encoders with HDR input may result in non-HDR output.
3.  **Error Handling:** Basic checks are included, but complex `ffmpeg` errors might require manual inspection of the command output.

## Credits

*   Based on the core `ffmpeg` logic in [Anime4K-GUI](https://github.com/mikigal/Anime4K-GUI).
*   Utilizes [Anime4K](https://github.com/bloc97/Anime4K) GLSL shaders (or other compatible shaders provided by the user).
*   Relies heavily on the [FFmpeg](https://ffmpeg.org) project.
*   [Google](https://gemini.google.com) for Gemini, which was helpful in creating _this_ README :D
*   **Assets**: "Transcode" from [icon-icons](https://icon-icons.com/icon/recovery-convert/241031), "Extract" from [Veryicon](https://www.veryicon.com/icons/education-technology/edit-job-operator/extract-2.html), "Remux" from [The Noun Project](https://thenounproject.com/icon/remix-5641961/)
