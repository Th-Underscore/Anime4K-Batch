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
    (Optional) The full path to the directory containing the media files. Defaults to the current directory.

.PARAMETER CustomRegex
    (Optional) Provide your own regular expression to find the episode number.
    IMPORTANT: The episode number MUST be the first capture group in your regex (i.e., enclosed in the first set of parentheses).

.EXAMPLE
    # DRY RUN: See what changes would be made for season 1 in the current directory.
    .\Rename-MediaFiles.ps1 -SeasonNumber 1 -WhatIf

.EXAMPLE
    # Rename files for season 1, including a file with episode 1.5.
    # e.g., "My Show - 1.mkv" -> "S01E01.mkv"
    # e.g., "My Show - 1.5 Special.mkv" -> "S01E1.5.mkv"
    .\Rename-MediaFiles.ps1 -SeasonNumber 1

.EXAMPLE
    # Use a custom regex for files named like "Show_Name_Episode_05.mp4"
    # The '(\d+)' part is the required capture group 1.
    .\Rename-MediaFiles.ps1 -SeasonNumber 1 -CustomRegex 'Episode_(\d+)' -Path "D:\Videos\MyShow"

.NOTES
    This script uses the -WhatIf parameter for safe testing. ALWAYS run with -WhatIf first!
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter the season number (e.g., 1, 01, 2).")]
    [string]$SeasonNumber,

    [Parameter(Mandatory = $false, HelpMessage = "Path to the directory with files. Defaults to the current directory.")]
    [string]$Path = (Get-Location).Path,

    [Parameter(Mandatory = $false, HelpMessage = "Provide a custom regex. The episode number must be in the first capture group `()`.")]
    [string]$CustomRegex
)

# --- Script Configuration ---
# Default Regex: Now handles decimals!
# (?i)                  - Makes the search case-insensitive.
# \b(?:e|ep|-)\s*       - Looks for a word boundary (\b) followed by 'e', 'ep', or '-' (a non-capturing group ?:).
# (?:\d+\.\d+|\d+)      - Groups a decimal number (e.g., 1.5) OR a whole number (e.g., 10). This is part of capture group 1.
#                         The decimal part `\d+\.\d+` MUST come first.
# (?:\s*-.*)?           - Optionally matches ' -' followed by any characters (.*). This is part of capture group 1.
$defaultRegex = '(?i)(?:e|ep|-|S\d+E)\s*((?:\d+\.\d+|\d+)(?:\s*-.*)?)'

# List of file extensions to process.
$videoExtensions = @('.mkv', '.mp4', '.avi', '.mov', '.webm')
# --- End Configuration ---

# Determine which regex to use
$regexToUse = $defaultRegex
if ($PSBoundParameters.ContainsKey('CustomRegex')) {
    Write-Host "Using custom regex provided by user: '$CustomRegex'" -ForegroundColor Yellow
    $regexToUse = $CustomRegex
}

# Validate the path exists
if (-not (Test-Path -Path $Path -PathType Container)) {
    Write-Error "Error: The specified path '$Path' does not exist or is not a directory."
    return
}

# Format the season number to be two digits
$paddedSeason = $SeasonNumber.PadLeft(2, '0')

Write-Host "Starting file rename process in directory: $Path" -ForegroundColor Cyan
Write-Host "Using Season: S$paddedSeason" -ForegroundColor Cyan
Write-Host "--------------------------------------------------"

# Get all files in the directory that match the extensions
$files = Get-ChildItem -Path $Path -File | Where-Object { $videoExtensions -contains $_.Extension }

if (-not $files) {
    Write-Warning "No video files with specified extensions found in '$Path'."
    return
}

# Loop through each file
foreach ($file in $files) {
    # Check if the file name matches our regex pattern
    if ($file.BaseName -match $regexToUse) {
        # The captured episode number is in $matches[1].
        $episodeString = $matches[1]
        $formattedEpisode = ""

        # Check if the episode is a decimal or whole number for correct formatting
        if ($episodeString -like '*.*') {
            # It's a decimal (e.g., "1.5"), so don't pad it.
            $formattedEpisode = $episodeString
        }
        else {
            # It's a whole number, so pad it to two digits.
            $formattedEpisode = $episodeString.PadLeft(2, '0')
        }

        # Construct the new file name
        $newFileName = "S$($paddedSeason)E$($formattedEpisode)$($file.Extension)"

        # Check if a rename is actually needed
        if ($file.Name -eq $newFileName) {
            Write-Host "SKIP: '$($file.Name)' is already in the correct format." -ForegroundColor Green
            continue
        }

        # Use the built-in ShouldProcess to handle -WhatIf and -Confirm
        if ($pscmdlet.ShouldProcess($file.Name, "Rename to $newFileName")) {
            Rename-Item -Path $file.FullName -NewName $newFileName
        }
    }
    else {
        # If the regex doesn't find a match, print a warning and skip the file.
        Write-Warning "Could not find an episode number in '$($file.Name)'. Skipping."
    }
}

Write-Host "--------------------------------------------------"
Write-Host "Processing complete." -ForegroundColor Cyan