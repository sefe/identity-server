param (
    [string]$BuildNumber
)

# Validate build number format
if ($BuildNumber -notmatch "\.\d+$") {
    Write-Host "Error: Build number must end with a dot followed by a build revision number (e.g., '1.2.3.4')."
    exit 1
}
# Extract the last part of the build number
$lastPart = $BuildNumber.Split('.')[-1]

# Get the current date in the format yy.M.d
$currentDate = Get-Date -Format "yy.M.d"

# Combine the date and the last part of the build number
$assemblyVersion = "$currentDate.$lastPart"

# Output the assembly version
Write-Host "Assembly Version: $assemblyVersion"

# Set the assemblyVersion variable in Azure DevOps
Write-Host "##vso[task.setvariable variable=assemblyVersion]$assemblyVersion"