function Get-QaFoundryChangeDeliveryIdentity {
    param([Parameter(Mandatory)][object[]]$Changes, [Parameter(Mandatory)][string]$TargetBranch)
    $isBootstrap = @($Changes | Where-Object { ([string]$_.path).Replace('\', '/') -match '(^|/)installation-plan\.json$' }).Count -gt 0
    if ($isBootstrap) {
        # Bootstrap is one installation transaction per target branch. Run-local
        # timestamps inside its plan must not create a second installation PR.
        $content = "bootstrap|$TargetBranch"
    }
    else {
        $content = ConvertTo-Json -Depth 100 -Compress -InputObject ([ordered]@{
            target = $TargetBranch
            changes = @($Changes | Sort-Object path -CaseSensitive | ForEach-Object {
                [ordered]@{
                    path = ([string]$_.path).Replace('\', '/')
                    operation = [string]$_.operation
                    content = if ($_.PSObject.Properties['content']) { [string]$_.content } else { '' }
                }
            })
        })
    }
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($content))).ToLowerInvariant()
    return [pscustomobject]@{ slug = $(if ($isBootstrap) { 'bootstrap-' } else { 'changes-' }) + $hash.Substring(0, 24); durable = $true }
}
