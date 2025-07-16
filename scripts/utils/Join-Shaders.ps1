<#
.SYNOPSIS
Combines shader files specified in a semicolon-delimited string,
replacing a placeholder with a base directory path.

.PARAMETER BaseDir
The base directory path to replace the '~~' placeholder. (Mandatory)

.PARAMETER FileListString
A single string containing relative file paths separated by semicolons (;).
Each path should use '~~' as a placeholder for the BaseDir.
Example: "~~/shaders/file1.glsl;~~/shaders/file2.glsl" (Mandatory)

.PARAMETER OutputFile
The name for the combined output file. Defaults to 'combined_output.glsl'.

.EXAMPLE
.\Join-Shaders.ps1 -BaseDir "C:\MyShaders" -FileListString "~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Restore_CNN_M.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl"

.EXAMPLE
.\Join-Shaders.ps1 -BaseDir "C:\Projects\Shaders" -FileListString "~~/core/common.glsl;~~/effects/blur.glsl" -OutputFile "final_shader.glsl"
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$BaseDir,

    [Parameter(Mandatory=$true)]
    [string]$FileListString,

    [string]$OutputFile = "combined_output.glsl"
)

# Trim potential leading/trailing whitespace from BaseDir
$BaseDir = $BaseDir.Trim()
# Optional: Remove trailing slash/backslash if present to avoid double separators
$BaseDir = $BaseDir -replace '[\\/]$',''

Write-Host "Base Directory: $BaseDir"
Write-Host "File List String: $FileListString"
Write-Host "Output File: $OutputFile"

# Split the input string into individual relative paths
$RelativePathsWithPlaceholder = $FileListString.Split(';') | Where-Object { $_ -ne '' } # Filter out empty entries if there are double semicolons ;;

if ($RelativePathsWithPlaceholder.Count -eq 0) {
    Write-Error "No valid file paths found in the FileListString after splitting."
    exit 1
}

# Replace placeholder and create full paths
$FullPaths = @() # Create an empty array to store the full paths
foreach ($relPath in $RelativePathsWithPlaceholder) {
    # Trim whitespace from each part
    $trimmedRelPath = $relPath.Trim()
    if ($trimmedRelPath -like '~~*') {
        # Replace placeholder, handling both / and \ after ~~ potentially
        $pathSuffix = $trimmedRelPath.Substring(2).TrimStart('\/')
        $fullPath = Join-Path -Path $BaseDir -ChildPath $pathSuffix
        $FullPaths += $fullPath
    } else {
        Write-Warning "Skipping path '$trimmedRelPath' as it doesn't start with the '~~' placeholder."
    }
}

if ($FullPaths.Count -eq 0) {
    Write-Error "No paths remained after placeholder replacement and validation."
    exit 1
}

Write-Host "Files to combine (in order):"
$FullPaths | ForEach-Object { Write-Host "- $_" }

# Check if all source files exist
$missingFiles = $FullPaths | Where-Object { !(Test-Path -LiteralPath $_ -PathType Leaf) }
if ($missingFiles) {
    Write-Error "The following source files were not found:"
    $missingFiles | ForEach-Object { Write-Error "- $_" }
    exit 1
}

Write-Host "Combining shaders into $OutputFile..."

# Combine the files
try {
    Get-Content -Raw -LiteralPath $FullPaths | Set-Content -LiteralPath $OutputFile -NoNewline -ErrorAction Stop
    Write-Host "Successfully created $OutputFile"
} catch {
    Write-Error "Failed to combine files. Error: $($_.Exception.Message)"
    exit 1
}
