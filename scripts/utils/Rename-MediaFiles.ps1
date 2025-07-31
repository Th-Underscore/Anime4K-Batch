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
    (Optional) Determines the episode offset for this season, to work with absolute numbering.
    e.g. Season 2 starts at "Episode 25" because Season 1 had 24 episodes.
    Overrides auto-detection of the first episode number.
    If you want to default to the episode number no matter what, use -NoDetectFirstEpisode.
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

.PARAMETER CombineData
    (Switch) Retrieves data from both filename and title metadata. The priority of source/episode depends on the -UseTitle flag.

.PARAMETER EditTitle
    (Switch) Edits the file's title metadata instead of the filename itself.

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
    [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true, HelpMessage = "The path to a directory of media files, or a direct path to one or more media files. Defaults to the current directory.")]
    [string[]]$Path = (Get-Location).Path,

    [Parameter(Mandatory = $false, HelpMessage = "Enter the season number (e.g., 1, 01, 2). Auto-detected if not provided.")]
    [string]$SeasonNumber,

    [Parameter(Mandatory = $false, HelpMessage = "Provide a custom regex. The episode number must be in the first capture group `(...)` and the rest of the filename in the second capture group `(...)`. Set capture group 2 to `()` to be empty.")]
    [string]$Regex = '(?i)(?:S?\d+[\s_\.]*(?:E|x)|(?:Season[\s_\.]*\d+)?E(?:p(?:isode)?)?|-)|(?:Season[\s_\.]*\d+))[\s_\.]*(\d+\.\d+|\d+)(.*)',

    [Parameter(Mandatory = $false, HelpMessage = "List of file extensions to process. Defaults to .mkv, .mp4, .avi, .mov, .webm.")]
    [string]$Extensions = '.mkv, .mp4, .avi, .mov, .webm',

    [Parameter(Mandatory = $false, HelpMessage = "Sets the episode offset for this season, to work with absolute numbering.")][Alias('EpisodeOne')][Alias('Offset')]
    [int]$FirstEpisode,

    [Parameter(Mandatory = $false, HelpMessage = "Uses the video title metadata instead of the file name.")]
    [switch]$UseTitle,

    [Parameter(Mandatory = $false, HelpMessage = "Orders the files alphabetically instead of using a detected episode number.")]
    [switch]$OrderByAlphabet,

    [Parameter(Mandatory = $false, HelpMessage = "Disables auto-detection of the first episode number for calculating an offset.")]
    [switch]$NoDetectFirstEpisode,

    [Parameter(Mandatory = $false, HelpMessage = "Combines retrieved data from both filename and title metadata.")]
    [switch]$CombineData,

    [Parameter(Mandatory = $false, HelpMessage = "Edits the file's title metadata instead of the filename.")]
    [switch]$EditTitle
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

if ($EditTitle) {
    $ffmpegPath = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffmpegPath) {
        Write-Error "ffmpeg.exe not found. Please ensure it is in your system's PATH."
        return
    }
}

# --- Script Configuration ---
# Default (Strict) Regex
# (?i)                  - Makes the entire match case-insensitive.
# (?:...)               - Matches the entire prefix before the episode number.
#                       - Contains three main alternatives, separated by | (OR).
#   --- Alternative 1 ---
#   S?\d+                  - Matches a season number (e.g., "S01", "1") optionally preceeded by 'S'.
#   [\s_\.]*               - Matches any space or possible separators.
#   (?:E|x)                - Matches 'E' or 'x' as an episode indicator (e.g., "S01E", "1x").
#   - OR -
#   --- Alternative 2 ---
#   (?:Season[\s_\.]*\d+)? - Optionally matches "Season" followed by a number (e.g., "Season 01", "season_1").
#   E(?:p(?:isode)?)?      - Matches an episode indicator like "e", "ep", "Episode", or "-".
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

# --- Path Validation and File Gathering ---
$files = @()
$singlePath = $null

if ($Path.Count -eq 1 -and (Test-Path -LiteralPath $Path[0] -PathType Container)) {
    $singlePath = $Path[0]
}

foreach ($p in $Path) {
    if (Test-Path -LiteralPath $p -PathType Container) {
        $files += Get-ChildItem -LiteralPath $p -File | Where-Object { $videoExtensions -contains $_.Extension }
    }
    elseif (Test-Path -LiteralPath $p -PathType Leaf) {
        $fileObject = Get-Item -LiteralPath $p
        if ($videoExtensions -contains $fileObject.Extension) {
            $files += $fileObject
        }
    }
    else {
        Write-Warning "Path '$p' is not a valid file or directory."
    }
}
$files = $files | Sort-Object -Property FullName -Unique

# --- Season Number Detection ---
if (-not $PSBoundParameters.ContainsKey('SeasonNumber')) {
    if ($singlePath) {
        $parentDirName = (Get-Item -LiteralPath $singlePath).Name
        # Prioritize 'Season <number>' (strict) before falling back to 'S<number>' (loose)
        $seasonRegexStrict = 'Season[\s_\.]*(\d+)'
        $seasonRegexLoose = 'S[\s_\.]*(\d+)'

        if ($parentDirName -match $seasonRegexStrict) {
            $SeasonNumber = $matches[1]
            Write-Host "Auto-detected Season: $SeasonNumber" -ForegroundColor Yellow
        } elseif ($parentDirName -match $seasonRegexLoose) {
            $SeasonNumber = $matches[1]
            Write-Host "Auto-detected Season: $SeasonNumber" -ForegroundColor Yellow
        } else {
            $SeasonNumber = "0"
            Write-Host "Could not auto-detect season number. Defaulting to '0'." -ForegroundColor Yellow
        }
    } else {
        $SeasonNumber = "0"
        Write-Host "Could not auto-detect season number from multiple paths or file paths. Defaulting to '0'." -ForegroundColor Yellow
    }
}
# Format the season number to be two digits
$paddedSeason = $SeasonNumber.PadLeft(2, '0')

Write-Host "Starting file rename process." -ForegroundColor Cyan
Write-Host "Using Season: S$paddedSeason" -ForegroundColor Cyan
Write-Host "--------------------------------------------------"

if (-not $files) {
    Write-Warning "No video files with specified extensions found in the provided path(s)."
    return
}

# --- File Processing ---
$fileQueue = [System.Collections.Generic.List[object]]::new()

$shell = New-Object -ComObject Shell.Application
foreach ($file in $files) {
    $filename_text = $file.BaseName
    $title_text = ""

    if ($UseTitle -or $CombineData -or $EditTitle) {
        try {
            $folder = $shell.NameSpace($file.DirectoryName)
            $shellfile = $folder.ParseName($file.Name)
            $title_text = $folder.GetDetailsOf($shellfile, 21)
            if ([string]::IsNullOrWhiteSpace($title_text)) { $title_text = "" }
        }
        catch {
            Write-Warning "Failed to get title for '$($file.Name)'. It will be treated as empty."
            $title_text = ""
        }
    }

    $nameToParse = if ($UseTitle) {
        if ([string]::IsNullOrEmpty($title_text)) { $file.BaseName } else { $title_text }
    } else {
        $filename_text
    }

    $fileQueue.Add([pscustomobject]@{
        OriginalFile = $file
        NameToParse  = $nameToParse
        FilenameText = $filename_text
        TitleText    = $title_text
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

        if ($CombineData) {
            $getTrailingText = {
                param($text, $regex, $looseRegex)
                if ($text -match $regex -or $text -match $looseRegex) {
                    return $matches[2]
                }
                return ""
            }
            $trailingText_filename = & $getTrailingText -text $item.FilenameText -regex $regexToUse -looseRegex $looseRegex
            $trailingText_title = & $getTrailingText -text $item.TitleText -regex $regexToUse -looseRegex $looseRegex
            $trailingText = "$($trailingText_filename)$($trailingText_title)"
        } else {
            $trailingText = $matches[2]
        }

        if ($episodeOffset -ne 0) {
            $episodeNumber = [decimal]$episodeString - $episodeOffset
            $episodeString = $episodeNumber.ToString()
        }
    } else {
        Write-Warning "Could not find an episode number in '$($nameToParse)' for file '$($file.Name)'. Skipping."
        continue
    }

    $source = ""
    if ((-not $EditTitle) -and $file.BaseName -match '^(\[.*?\])') {
        $source = "$($matches[1]) "
    }

    $formattedEpisode = ""
    if ($episodeString -like '*.*') { # Don't pad decimals
        $formattedEpisode = $episodeString
    } else { # Pad integers
        $formattedEpisode = $episodeString.PadLeft(2, '0')
    }

    $newBaseName = "$($source)S$($paddedSeason)E$($formattedEpisode)$trailingText"

    if ($EditTitle) {
        $currentTitle = if ([string]::IsNullOrEmpty($item.TitleText)) { "" } else { $item.TitleText }
        if ($currentTitle -eq $newBaseName) {
            Write-Host "SKIP: Title for '$($file.Name)' is already correct." -ForegroundColor Green
            continue
        }
        if ($pscmdlet.ShouldProcess($file.FullName, "Set title to `"$newBaseName`"")) {
            $tempFile = [System.IO.Path]::GetTempFileName() + $file.Extension
            try {
                & ffmpeg -hide_banner -y -v error -i $file.FullName -metadata "title=$newBaseName" -map 0 -c copy $tempFile
                if ($LASTEXITCODE -ne 0) {
                    throw "ffmpeg failed to process '$($file.Name)'"
                }
                Move-Item -LiteralPath $tempFile -Destination $file.FullName -Force
            }
            catch {
                Write-Error "Failed to edit title for '$($file.Name)'. Error: $($_.Exception.Message)"
            }
            finally {
                if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile }
            }
        }
    }
    else {
        $newFileName = "$($newBaseName)$($file.Extension)"
        if ($file.Name -eq $newFileName) {
            Write-Host "SKIP: '$($file.Name)' is already in the correct format." -ForegroundColor Green
            continue
        }

        if ($pscmdlet.ShouldProcess($file.Name, "Rename to $newFileName")) {
            Rename-Item -LiteralPath $file.FullName -NewName $newFileName
        }
    }
}

Write-Host "--------------------------------------------------"
Write-Host "Processing complete." -ForegroundColor Cyan
