<#
.SYNOPSIS
    Renames media files in a directory to a standard SxxExx format, with support for decimal episodes and custom patterns.

.DESCRIPTION
    This script loops through video files in a directory and renames them to a "SxxExx.ext" format.
    It uses a robust default regular expression to find an episode number (including decimals like 1.5) in the filename.
    A season number must be provided by the user. The script also includes an optional parameter to use a custom regex
    for filenames that don't match the default pattern.

.PARAMETER SeasonNumber
    (Required) The season number to use for the files. It will be padded to two digits (e.g., '1' becomes '01').

.PARAMETER Path
    (Optional) The full path to the directory containing the media files.
    Default: . (current directory)

.PARAMETER Regex
    (Optional) Your own regular expression to find the episode number.
    Default: "(?i)(?:S?\d+[\s_\.]*(?:E|x)|(?:Season[\s_\.]*\d+)?(?:e|ep|Episode|-)|(?:Season[\s_\.]*\d+))[\s_\.]*(\d+\.\d+|\d+)(.*)"
    IMPORTANT: The episode number MUST be the first capture group in your regex (i.e., enclosed in the first set of parentheses), and the rest of the filename in the second capture group. Set capture group 2 to () to be empty.
    The loose regex is always applied as a fallback if the custom regex does not match: "(?i)(\d+\.\d+|\d+)(.*)"

.PARAMETER Extensions
    (Optional) The list of file extensions to process.
    Default: ".mkv, .mp4, .avi, .mov, .webm"

.PARAMETER FirstEpisode
    (Optional) Sets the episode offset for this season, to work with absolute numbering.
    e.g. Season 2 starts at "Episode 25" because Season 1 had 24 episodes.
    Overrides auto-detection of the first episode number.
    If you want to default to the episode number no matter what, use -NoDetectFirst.
    Not compatible with -OrderByAlphabet.

.PARAMETER UseTitle
    (Switch) Uses the video title metadata instead of the file name.

.PARAMETER OrderByAlphabet
    (Switch) Orders the files alphabetically instead of using a detected episode number.
    This follows -UseTitle if applied.

.PARAMETER NoDetectFirstEpisode
    (Switch) Disables auto-detection of the first episode number for calculating an offset.
    Use this if you want to default to the episode number no matter what. -FirstEpisode always overrides this.
    Not compatible with -OrderByAlphabet.

.EXAMPLE
    .\Rename-MediaFiles.ps1 -Season 1 -WhatIf
    DRY RUN: See what changes would be made for season 1 in the current directory.

.EXAMPLE
    .\Rename-MediaFiles.ps1 -SeasonNumber 1
    Rename files for season 1, including a file with episode 1.5.
    e.g., "My Show - 1.mkv" -> "S01E01.mkv"
    e.g., "My Show - 1.5 Special.mkv" -> "S01E1.5 Special.mkv"

.EXAMPLE
    .\Rename-MediaFiles.ps1 -S 1 -C 'Episode_(\d+)(.*)' -Path "D:\Videos\MyShow" -E "mkv, jpg, nfo"
    Use a custom regex for files named like "Show_Name_Episode_05.mp4", including generated thumbnails and metadata files (skips 'season.nfo').
    The '(\d+)' part is the required capture group 1, and capture group 2 will be the rest of the filename.
    For Jellyfin-generated files like thumbnails in particular, the '(.*)' captures the '-thumb' part of the filename.

.NOTES
    This script uses the -WhatIf parameter for safe testing. ALWAYS run with -WhatIf first!
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter the season number (e.g., 1, 01, 2).")]
    [string]$SeasonNumber,

    [Parameter(Mandatory = $false, HelpMessage = "Path to the directory with files. Defaults to the current directory.")]
    [string]$Path = (Get-Location).Path,

    [Parameter(Mandatory = $false, HelpMessage = "Provide a custom regex. The episode number must be in the first capture group `()` and the rest of the filename in the second capture group `()`. Set capture group 2 to `()` to be empty.")]
    [string]$Regex = '(?i)(?:S?\d+[\s_\.]*(?:E|x)|(?:Season[\s_\.]*\d+)?(?:e|ep|Episode|-)|(?:Season[\s_\.]*\d+))[\s_\.]*(\d+\.\d+|\d+)(.*)',

    [Parameter(Mandatory = $false, HelpMessage = "List of file extensions to process. Defaults to .mkv, .mp4, .avi, .mov, .webm.")]
    [string]$Extensions = '.mkv, .mp4, .avi, .mov, .webm',

    [Parameter(Mandatory = $false, HelpMessage = "Sets the episode offset for this season, to work with absolute numbering.")]
    [int]$FirstEpisode,

    [Parameter(Mandatory = $false, HelpMessage = "Uses the video title metadata instead of the file name.")]
    [switch]$UseTitle,

    [Parameter(Mandatory = $false, HelpMessage = "Orders the files alphabetically instead of using a detected episode number.")]
    [switch]$OrderByAlphabet,

    [Parameter(Mandatory = $false, HelpMessage = "Disables auto-detection of the first episode number for calculating an offset.")]
    [switch]$NoDetectFirstEpisode
)

# --- Parameter Validation ---
if ($OrderByAlphabet -and $PSBoundParameters.ContainsKey('FirstEpisode')) {
    Write-Error "'-OrderByAlphabet' and '-FirstEpisode' cannot be used together."
    return
}

if ($OrderByAlphabet -and $PSBoundParameters.ContainsKey('NoDetectFirstEpisode')) {
    Write-Error "'-OrderByAlphabet' and '-NoDetectFirstEpisode' cannot be used together."
    return
}

if ($UseTitle) {
    $ffprobePath = Get-Command ffprobe -ErrorAction SilentlyContinue
    if (-not $ffprobePath) {
        Write-Error "ffprobe.exe not found. Please ensure it is in your system's PATH."
        return
    }
}

# --- Script Configuration ---
# Default (Strict) Regex
# (?i)                  - Makes the entire match case-insensitive.
# (?:...)               - Matches the entire prefix before the episode number.
#                       - This non-capturing group contains three main alternatives, separated by | (OR).
#   --- Alternative 1 ---
#   S?\d+                  - Matches a season number (e.g., "S01", "1") optionally preceeded by 'S'.
#   [\s_\.]*               - Matches any space or possible separators.
#   (?:E|x)                - Matches 'E' or 'x' as an episode indicator (e.g., "S01E", "1x").
#   - OR -
#   --- Alternative 2 ---
#   (?:Season[\s_\.]*\d+)? - Optionally matches "Season" followed by a number (e.g., "Season 01", "season_1").
#   (?:e|ep|Episode|-)     - Matches an episode indicator like "e", "ep", "Episode", or "-".
#   - OR -
#   --- Alternative 3 ---
#   (?:Season[\s_\.]*\d+)  - Matches "Season" followed by a number (e.g., "Season 01", "season_1").
#
# [\s_\.]*              - Matches any space or possible separators.
#
# (\d+\.\d+|\d+)        - Capture Group 1: The episode number.
#                         Matches a decimal (e.g., 1.5) or a whole number (e.g., 1, 01).
#                         The decimal part `\d+\.\d+` MUST come first to be matched correctly.
#
# (.*)                  - Capture Group 2: The rest of the string.
#                         This greedily captures any remaining characters, which usually includes the
#                         episode title.
#
# Alternate (Loose) Regex
# (?i)              - Makes the entire match case-insensitive.
# (\d+\.\d+|\d+)    - Capture Group 1: Matches the first decimal or whole number.
# (.*)              - Capture Group 2: The rest of the string.

$looseRegex = '(?i)(\d+\.\d+|\d+)(.*)'

# List of file extensions to process.
$videoExtensions = $Extensions -split ',\s*' | ForEach-Object { $ext = $_.Trim().ToLower(); if (-not $ext.StartsWith('.')) { '.' + $ext } else { $ext } }
if ($videoExtensions.Count -eq 0) {
    Write-Error "No valid video extensions provided. Please specify at least one extension."
    return
}
if ($PSBoundParameters.ContainsKey('Extensions')) {
    Write-Host "Using custom extensions: $($videoExtensions -join ', ')" -ForegroundColor Yellow
}
# --- End Configuration ---

$regexToUse = $Regex
if ($PSBoundParameters.ContainsKey('Regex')) {
    Write-Host "Using custom regex provided by user: '$Regex'" -ForegroundColor Yellow
}

# Validate the path exists
if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Error "Error: The specified path '$Path' does not exist or is not a directory."
    return
}

# Format the season number to be two digits
$paddedSeason = $SeasonNumber.PadLeft(2, '0')

Write-Host "Starting file rename process in directory: $Path" -ForegroundColor Cyan
Write-Host "Using Season: S$paddedSeason" -ForegroundColor Cyan
Write-Host "--------------------------------------------------"

# Get all files in the directory that match the extensions
$files = Get-ChildItem -LiteralPath $Path -File | Where-Object { $videoExtensions -contains $_.Extension }

if (-not $files) {
    Write-Warning "No video files with specified extensions found in '$Path'."
    return
}

# --- File Processing ---
$fileQueue = [System.Collections.Generic.List[object]]::new()

foreach ($file in $files) {
    $nameToParse = if ($UseTitle) {
        try {
            $title = ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 -i $file.FullName
            if ([string]::IsNullOrWhiteSpace($title)) { $file.BaseName } else { $title }
        }
        catch {
            Write-Warning "Failed to get title for '$($file.Name)'. Falling back to filename."
            $file.BaseName
        }
    } else {
        $file.BaseName
    }
    $fileQueue.Add([pscustomobject]@{
        OriginalFile = $file
        NameToParse  = $nameToParse
    })
}

if ($OrderByAlphabet) {
    $fileQueue = $fileQueue | Sort-Object NameToParse
}

# --- Episode Offset Calculation ---
$episodeOffset = 0
if ($PSBoundParameters.ContainsKey('FirstEpisode')) {
    $episodeOffset = $FirstEpisode - 1
    Write-Host "Using manual episode offset from -FirstEpisode: $episodeOffset" -ForegroundColor Yellow
} elseif (-not $NoDetectFirstEpisode) {
    $sortedFilesForDetection = $fileQueue | Sort-Object NameToParse
    foreach ($item in $sortedFilesForDetection) {
        if ($item.NameToParse -match $regexToUse -or $item.NameToParse -match $looseRegex) {
            $detectedFirstEpisode = [decimal]$matches[1]
            if ($detectedFirstEpisode -ge 1) {
                $episodeOffset = $detectedFirstEpisode - 1
                Write-Host "Auto-detected first episode: $detectedFirstEpisode. Using offset: $episodeOffset" -ForegroundColor Yellow
                break
            }
        }
    }
}

$episodeCounter = 1
foreach ($item in $fileQueue) {
    $file = $item.OriginalFile
    $nameToParse = $item.NameToParse
    $episodeString = ""
    $trailingText = ""

    if ($OrderByAlphabet) {
        $episodeString = $episodeCounter++
        $trailingText = "" # No trailing text in alphabet mode
    } elseif ($nameToParse -match $regexToUse -or $nameToParse -match $looseRegex) {
        $episodeString = $matches[1]
        $trailingText = $matches[2]

        if ($episodeOffset -ne 0) {
            $episodeNumber = [decimal]$episodeString - $episodeOffset
            $episodeString = $episodeNumber.ToString()
        }
    } else {
        Write-Warning "Could not find an episode number in '$($nameToParse)' for file '$($file.Name)'. Skipping."
        continue
    }

    $source = ""
    if ($file.BaseName -match '^(\[.*?\])') {
        $source = "$($matches[1]) "
    }

    $formattedEpisode = ""
    if ($episodeString -like '*.*') { # Don't pad decimals
        $formattedEpisode = $episodeString
    } else { # Pad integers
        $formattedEpisode = $episodeString.PadLeft(2, '0')
    }

    $newFileName = "$($source)S$($paddedSeason)E$($formattedEpisode)$trailingText$($file.Extension)"

    if ($file.Name -eq $newFileName) {
        Write-Host "SKIP: '$($file.Name)' is already in the correct format." -ForegroundColor Green
        continue
    }

    if ($pscmdlet.ShouldProcess($file.Name, "Rename to $newFileName")) {
        Rename-Item -LiteralPath $file.FullName -NewName $newFileName
    }
}

Write-Host "--------------------------------------------------"
Write-Host "Processing complete." -ForegroundColor Cyan