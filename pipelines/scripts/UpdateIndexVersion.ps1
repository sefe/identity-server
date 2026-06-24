param (
    [string]$filePath,
    [string]$version
)

if (-not $filePath) {
    throw "Please provide correct path to the file."
}
if (-not $version) {
    throw "Please provide the new version number."
}

Write-Host "Original content of ${filePath}:"
Get-Content $filePath | ForEach-Object { Write-Host $_ }
Write-Host "Updating Version to: $version"

(Get-Content $filePath) -replace '\?v=1\.0\.0\.0', "?v=$version" | Set-Content $filePath

Write-Host "Updated content of ${filePath}:"
Get-Content $filePath | ForEach-Object { Write-Host $_ }
