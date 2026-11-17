function Get-QaFoundryWorkItemDefaults {
    param([object]$Settings, [string]$Type, [string]$UserEmail,
        [string]$Path = (Join-Path $PSScriptRoot '../config/work-item-defaults.json'))
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [ordered]@{} }
    $configuration = Get-Content $Path -Raw | ConvertFrom-Json -Depth 30
    $matches = @($configuration.targets | Where-Object {
        $_.organization_url.TrimEnd('/') -ieq $Settings.organization_url.TrimEnd('/') -and
        $_.project -ieq $Settings.project -and $_.work_item_type -ieq $Type
    })
    if ($matches.Count -gt 1) { throw "Multiple work-item defaults match '$Type' in '$($Settings.project)'." }
    $fields = [ordered]@{}
    if ($matches.Count -eq 0) { return $fields }
    foreach ($property in $matches[0].fields.PSObject.Properties) {
        if ($property.Name -notmatch '^[A-Za-z][A-Za-z0-9_.]+$') { throw 'Invalid work-item field reference in defaults.' }
        $value = $property.Value
        if ($value -ceq '@authenticated-user') { $value = $UserEmail }
        if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) -or
            $value -is [pscustomobject] -or $value -is [array]) {
            throw "Work-item default '$($property.Name)' must have a nonempty scalar value."
        }
        $fields[$property.Name] = $value
    }
    return $fields
}
