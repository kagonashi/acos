param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [string]$BackupDir = (Join-Path $PSScriptRoot "backup"),

    [double]$LimitMB = 10,

    [double]$Threshold = 80,

    [int]$MaxFiles = 3
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    throw "Source folder does not exist: $Source"
}

if ($LimitMB -le 0 -or $Threshold -lt 0 -or $Threshold -gt 100) {
    throw "Invalid limit or threshold."
}

if ($MaxFiles -lt 1) {
    throw "MaxFiles must be at least 1."
}

$allFiles = @(
    Get-ChildItem -LiteralPath $Source -File -Recurse
)

$totalBytes = ($allFiles | Measure-Object -Property Length -Sum).Sum

if ($null -eq $totalBytes) {
    $totalBytes = 0
}

$folderSizeMB = $totalBytes / 1MB
$triggerMB = $LimitMB * $Threshold / 100

Write-Host ("Folder size: {0:N2} MB" -f $folderSizeMB)
Write-Host ("Threshold: {0:N2} MB" -f $triggerMB)

if ($folderSizeMB -le $triggerMB) {
    Write-Host "Threshold not exceeded. No archive created."
    return
}

$oldFiles = @(
    $allFiles |
        Sort-Object LastWriteTime, FullName |
        Select-Object -First $MaxFiles
)

if ($oldFiles.Count -eq 0) {
    Write-Host "No files available for archiving."
    return
}

New-Item -ItemType Directory -Path $BackupDir -Force |
    Out-Null

$archive = Join-Path $BackupDir (
    "backup_{0}.tar.gz" -f (Get-Date -Format "yyyyMMdd_HHmmss")
)

$temp = Join-Path ([System.IO.Path]::GetTempPath()) (
    "Lab_" + [guid]::NewGuid().ToString()
)

New-Item -ItemType Directory -Path $temp | Out-Null

try {
    $sourceFull = (Resolve-Path -LiteralPath $Source).Path

    foreach ($file in $oldFiles) {
        $relative = $file.FullName.Substring(
            $sourceFull.TrimEnd('\').Length
        ).TrimStart('\')

        $destination = Join-Path $temp $relative
        $parent = Split-Path -Parent $destination

        New-Item -ItemType Directory -Path $parent -Force |
            Out-Null

        Copy-Item -LiteralPath $file.FullName `
            -Destination $destination
    }

    & tar.exe -czf $archive -C $temp .

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create archive."
    }

    Write-Host "Archive created: $archive"
    Write-Host "Files archived: $($oldFiles.Count)"
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force `
        -ErrorAction SilentlyContinue
}

