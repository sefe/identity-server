[CmdletBinding()]
param([Parameter(Mandatory)][object]$Workflow)

$stages = @($Workflow.stages)
$ids = @($stages | ForEach-Object { [string]$_.id })
if (@($ids | Select-Object -Unique).Count -ne $ids.Count) {
    throw "Workflow stage IDs must be unique."
}

$resolved = [System.Collections.Generic.List[object]]::new()
$remaining = [System.Collections.Generic.List[object]]::new()
foreach ($stage in $stages) {
    $remaining.Add($stage)
}

while ($remaining.Count -gt 0) {
    $progress = $false
    foreach ($stage in @($remaining)) {
        $dependencies = if ($stage.PSObject.Properties.Name -contains "depends_on") {
            @($stage.depends_on | ForEach-Object { [string]$_ })
        }
        else {
            @()
        }
        foreach ($dependency in $dependencies) {
            if ($dependency -notin $ids) {
                throw "Stage '$($stage.id)' depends on unknown stage '$dependency'."
            }
        }
        $resolvedIds = @($resolved | ForEach-Object { [string]$_.id })
        if (@($dependencies | Where-Object { $_ -notin $resolvedIds }).Count -eq 0) {
            $resolved.Add($stage)
            $null = $remaining.Remove($stage)
            $progress = $true
        }
    }
    if (-not $progress) {
        $blockedIds = @($remaining | ForEach-Object { [string]$_.id }) -join ", "
        throw "Workflow contains a dependency cycle involving: $blockedIds"
    }
}

return @($resolved)

