[CmdletBinding()]
param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
    [Parameter(Mandatory)][object]$Convention
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($null -eq $Convention -or -not $Convention.detected) { return $true }

$required = "$($Convention.prefix)$($Convention.separator)$($Convention.segment)$($Convention.separator)"
if ([string]::IsNullOrWhiteSpace($Name) -or
    -not $Name.StartsWith($required, [StringComparison]::Ordinal) -or
    $Name.Length -le $required.Length) {
    throw ("Agent named an automation project '$Name', which does not follow this repository's " +
        "convention. Every automation project must be named $($Convention.template), for example " +
        "$($Convention.example). Rename it to start with '$required'.")
}
return $true
