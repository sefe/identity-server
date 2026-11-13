function Get-FoundryGitHubContext {
    param([Parameter(Mandatory)][object]$Settings, [hashtable]$Environment = @{})
    $repository = [string]$Settings.repository
    if ($repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'GitHub repository must be owner/repository.' }
    $name = [string]$Settings.auth_env
    if (-not $Environment.ContainsKey($name) -or [string]::IsNullOrWhiteSpace([string]$Environment[$name])) {
        throw "GitHub access requires mapped credential '$name'."
    }
    $token = ([string]$Environment[$name]).Trim()
    if ($token -match '\s' -or $token -match '^\$\(') { throw 'Invalid GitHub credential format.' }
    return [pscustomobject]@{
        repository = $repository
        headers = @{Authorization="Bearer $token"; Accept='application/vnd.github+json'; 'X-GitHub-Api-Version'='2022-11-28'}
        gitAuthorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("x-access-token:$token"))
    }
}

function Invoke-FoundryGitHub {
    param([Parameter(Mandatory)][object]$Context, [ValidateSet('GET','POST','PATCH')][string]$Method='GET',
          [Parameter(Mandatory)][AllowEmptyString()][string]$Path, [object]$Body, [switch]$AllowNotFound)
    if ($Path -match '(^/|://|\\|(?:^|/)\.\.(?:/|$))') { throw 'GitHub API path must stay repository-relative.' }
    $args = @{Method=$Method; Uri="https://api.github.com/repos/$($Context.repository)/$Path";
              Headers=$Context.headers; TimeoutSec=60; MaximumRedirection=0; ErrorAction='Stop'}
    if ($PSBoundParameters.ContainsKey('Body')) { $args.ContentType='application/json'; $args.Body=$Body | ConvertTo-Json -Depth 50 -Compress }
    try { return Invoke-RestMethod @args }
    catch {
        $status = 0
        if ($_.Exception.PSObject.Properties.Name -contains 'Response' -and $null -ne $_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        if ($AllowNotFound -and $status -eq 404) { return $null }
        # Do not echo headers, payloads, credentials or provider error bodies into evidence.
        throw "GitHub $Method $Path failed (HTTP $status). Check repository access, token permissions and organization policy."
    }
}

function Get-FoundryGitHubDeliveryState {
    param([object]$Context, [string]$Branch, [string]$Base)
    $encoded = ($Branch.Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $ref = Invoke-FoundryGitHub -Context $Context -Path "git/ref/heads/$encoded" -AllowNotFound
    $head = [Uri]::EscapeDataString(($Context.repository.Split('/')[0] + ':' + $Branch))
    $baseQuery = [Uri]::EscapeDataString($Base)
    $prs = @(Invoke-FoundryGitHub -Context $Context -Path "pulls?state=all&head=$head&base=$baseQuery&per_page=100")
    $existing = @($prs | Where-Object { $_.head.ref -ceq $Branch -and $_.base.ref -ceq $Base } | Sort-Object number)
    return [pscustomobject]@{
        branchExists=($null -ne $ref); tip=$(if ($null -ne $ref) {[string]$ref.object.sha} else {''})
        pullRequestId=$(if ($existing.Count) {[string]$existing[-1].number} else {''})
        pullRequestStatus=$(if ($existing.Count) {[string]$existing[-1].state} else {''})
    }
}
