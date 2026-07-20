param (
    [string]$assemblyInfoPath,
    [string]$assemblyVersion
)

if (-not $assemblyInfoPath) {
    throw "Please provide the path to the AssemblyInfo.cs file."
}
if (-not $assemblyVersion) {
    throw "Please provide the new version number."
}

Write-Host "Original content of ${assemblyInfoPath}:"
Get-Content $assemblyInfoPath | ForEach-Object { Write-Host $_ }
Write-Host "Updating Assembly Version to: $assemblyVersion"

#(Get-Content $assemblyInfoPath) -replace 'AssemblyVersion\(".*?"\)', "AssemblyVersion(`"$assemblyVersion`")" | Set-Content $assemblyInfoPath
(Get-Content $assemblyInfoPath) -replace 'AssemblyFileVersion\(".*?"\)', "AssemblyFileVersion(`"$assemblyVersion`")" | Set-Content $assemblyInfoPath
(Get-Content $assemblyInfoPath) -replace 'AssemblyInformationalVersion\(".*?"\)', "AssemblyInformationalVersion(`"$assemblyVersion`")" | Set-Content $assemblyInfoPath

Write-Host "Updated content of ${assemblyInfoPath}:"
Get-Content $assemblyInfoPath | ForEach-Object { Write-Host $_ }
