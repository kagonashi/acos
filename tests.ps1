$ErrorActionPreference = "Stop"

$script = Join-Path $PSScriptRoot "main.ps1"
$testRoot = Join-Path $env:TEMP "LabTests"

$passed = 0
$failed = 0

function Test-Result {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    try {
        & $Action
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:passed++
    }
    catch {
        Write-Host "[FAIL] $Name : $_" -ForegroundColor Red
        $script:failed++
    }
}

if (Test-Path $testRoot) {
    Remove-Item $testRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $testRoot | Out-Null

#                                                               Test 1: Проверка отсутствия исходной папки
Test-Result "Missing source directory" {
    $missing = Join-Path $testRoot "missing"

    try {
        & $script -Source $missing
        throw "Expected an error, but the script succeeded."
    }
    catch {
        if ($_.Exception.Message -like "*Expected an error*") {
            throw
        }
    }
}

#                                                            Test 2: Лимит не превышен, папка не создается
Test-Result "Small folder does not create archive" {
    $source = Join-Path $testRoot "small"
    $backup = Join-Path $testRoot "small-backup"

    New-Item -ItemType Directory -Path $source | Out-Null
    Set-Content (Join-Path $source "test.txt") "hello"

    & $script -Source $source -BackupDir $backup -LimitMB 10 -Threshold 80 -MaxFiles 3

    $archives = @(Get-ChildItem $backup -Filter "*.tar.gz" -ErrorAction SilentlyContinue)

    if ($archives.Count -ne 0) {
        throw "Unexpected archive was created."
    }
}

#                                                        Test 3: Лимит превышен, папка создается
Test-Result "Large folder creates archive with three files" {
    $source = Join-Path $testRoot "large"
    $backup = Join-Path $testRoot "large-backup"

    New-Item -ItemType Directory -Path $source | Out-Null

    $data = New-Object byte[] (8.5 * 1MB)
    [System.IO.File]::WriteAllBytes(
        (Join-Path $source "large.bin"),
        $data
    )

    1..3 | ForEach-Object {
        Set-Content (Join-Path $source "file$_.txt") "test"
    }

    & $script -Source $source -BackupDir $backup -LimitMB 10 -Threshold 80 -MaxFiles 3

    $archives = @(Get-ChildItem $backup -Filter "*.tar.gz")

    if ($archives.Count -ne 1) {
        throw "Expected exactly one archive."
    }

    $contents = @(& tar.exe -tzf $archives[0].FullName)

    if ($LASTEXITCODE -ne 0) {
        throw "Cannot read the archive."
    }

    $files = @($contents | Where-Object { $_ -match '\.(txt|bin)$' })

    if ($files.Count -ne 3) {
        throw "Expected 3 archived files, got $($files.Count)."
    }
}

Write-Host ""
Write-Host "Passed: $passed"
Write-Host "Failed: $failed"

Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue

if ($failed -gt 0) {
    exit 1
}

exit 0
