function Set-IntuneDeviceConfigurationPolicyAssignment {
    <#
    .SYNOPSIS
        Applies Intune Device Configuration Policy assignments from a merged JSON file.
    .DESCRIPTION
        Reads a merged assignment JSON file and POSTs it to the Graph API assign endpoint
        for the policy identified by the sourceId in the file. Only a single PolicyId per
        file is supported.
    .PARAMETER InputFilePath
        Mandatory. Path to the merged assignment JSON file.
    .EXAMPLE
        Set-IntuneDeviceConfigurationPolicyAssignment -InputFilePath "C:\temp\merged-assignments.json"
    .LINK
        https://learn.microsoft.com/en-us/powershell/microsoftgraph/overview
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$InputFilePath
    )

    if (-not (Get-MgContext)) {
        throw "Not connected to Microsoft Graph. Run Connect-MgGraph first."
    }

    if (-not (Test-Path $InputFilePath)) {
        throw "File not found: '$InputFilePath'."
    }

    $JsonContent = Get-Content $InputFilePath -Raw | ConvertFrom-Json

    if (-not $JsonContent.value) {
        throw "JSON file '$InputFilePath' does not contain a 'value' array."
    }

    $PolicyIds = @($JsonContent.value | Select-Object -ExpandProperty sourceId -Unique)

    if ($PolicyIds.Count -eq 0) {
        throw "No 'sourceId' found in assignments in '$InputFilePath'."
    }

    if ($PolicyIds.Count -gt 1) {
        throw "Multiple sourceIds found in '$InputFilePath'. Only one PolicyId per file is supported."
    }

    $PolicyId = $PolicyIds[0]

    # The /assign endpoint only accepts { assignments: [ { target: {...} } ] }
    # Strip source, id, sourceId — they are rejected with 400 Bad Request.
    # Wrap in @() to guarantee a JSON array even when there is only one item.
    $AssignmentTargets = @($JsonContent.value | ForEach-Object {
        [PSCustomObject]@{ target = $_.target }
    })

    $Body = @{ assignments = $AssignmentTargets } | ConvertTo-Json -Depth 10

    try {
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$PolicyId/assign" -Body $Body -ContentType "application/json" -ErrorAction Stop
    }
    catch {
        throw "Failed to apply assignments for PolicyId '$PolicyId': $_"
    }

    Write-Host "Assignments applied successfully for PolicyId '$PolicyId'."
}
