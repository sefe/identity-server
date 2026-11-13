[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$SecretsConfig,
    [Parameter(Mandatory)][string]$ConfigDirectory,
    [Parameter(Mandatory)][string]$TargetRoot,
    [string]$SecretsPathOverride = ""
)

. (Join-Path $PSScriptRoot "Common.ps1")
$source = [string]$SecretsConfig.source
$values = @{}
if ($source -eq "none") {
    return $values
}

$mappingProperties = @($SecretsConfig.mappings.PSObject.Properties)
$sourceKeys = @($mappingProperties | ForEach-Object { [string]$_.Value })
$sourceKeys += @($SecretsConfig.required_keys | ForEach-Object { [string]$_ })
$sourceKeys = @($sourceKeys | Select-Object -Unique)

if ($source -eq "environment") {
    foreach ($key in $sourceKeys) {
        $value = [Environment]::GetEnvironmentVariable($key)
        if ($null -ne $value) {
            $values[$key] = $value
        }
    }
}
elseif ($source -eq "file") {
    $configuredPath = if ($SecretsPathOverride) {
        [System.IO.Path]::GetFullPath($SecretsPathOverride)
    }
    else {
        Resolve-QaFoundryPath -Root $ConfigDirectory -Path ([string]$SecretsConfig.path)
    }
    if (-not (Test-Path $configuredPath -PathType Leaf)) {
        throw "Secrets file does not exist: $configuredPath"
    }
    $configuredPath = (Resolve-Path $configuredPath).Path
    if (-not $SecretsConfig.allow_inside_target -and
        (Test-PathWithinRoot -Candidate $configuredPath -Root $TargetRoot)) {
        throw "Secrets file must be outside the target repository."
    }
    $format = [string]$SecretsConfig.format
    if ($format -eq "auto") {
        $format = if ([System.IO.Path]::GetExtension($configuredPath) -eq ".json") {
            "json"
        }
        else {
            "env"
        }
    }
    if ($format -eq "json") {
        $json = Get-Content -Path $configuredPath -Raw | ConvertFrom-Json -Depth 20
        foreach ($property in $json.PSObject.Properties) {
            if ($property.Value -isnot [string]) {
                throw "Secret '$($property.Name)' must be a string."
            }
            $values[$property.Name] = [string]$property.Value
        }
    }
    elseif ($format -eq "env") {
        foreach ($line in @(Get-Content -Path $configuredPath)) {
            $trimmed = $line.Trim()
            if (-not $trimmed -or $trimmed.StartsWith("#")) {
                continue
            }
            if ($trimmed -notmatch "^([A-Z_][A-Z0-9_]*)=(.*)$") {
                throw "Invalid secrets env line. Only KEY=VALUE is supported."
            }
            $value = $Matches[2].Trim()
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $values[$Matches[1]] = $value
        }
    }
    else {
        throw "Unsupported secrets format: $format"
    }
}
else {
    throw "Unsupported secrets source: $source"
}

foreach ($key in @($SecretsConfig.required_keys)) {
    if (-not $values.ContainsKey([string]$key) -or
        [string]::IsNullOrWhiteSpace([string]$values[[string]$key])) {
        throw "Required secret is unavailable: $key"
    }
}

$providerEnvironment = @{}
foreach ($mapping in $mappingProperties) {
    $sourceKey = [string]$mapping.Value
    if ($values.ContainsKey($sourceKey)) {
        $providerEnvironment[$mapping.Name] = [string]$values[$sourceKey]
    }
}
return $providerEnvironment
