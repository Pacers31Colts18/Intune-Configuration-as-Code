function Export-IntuneDeviceConfigurationPolicyAssignments {
    <#
    .SYNOPSIS
        Exports Intune Device Configuration Policy assignments to a JSON file.
    .DESCRIPTION
        Retrieves the assignments for a given policy from Microsoft Graph and writes them
        to a JSON file in the specified output folder. Returns a result object with
        FilePath and JsonData properties.
    .PARAMETER PolicyId
        Mandatory. The GUID of the Intune Device Configuration Policy.
    .PARAMETER OutputFolder
        Optional. Directory to write the JSON file to. Defaults to the current directory.
    .EXAMPLE
        Export-IntuneDeviceConfigurationPolicyAssignments -PolicyId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -OutputFolder "C:\temp"
    .LINK
        https://learn.microsoft.com/en-us/powershell/microsoftgraph/overview
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PolicyId,

        [Parameter()]
        [string]$OutputFolder = $pwd
    )

    if (-not (Get-MgContext)) {
        throw "Not connected to Microsoft Graph. Run Connect-MgGraph first."
    }

    # Get policy metadata
    try {
        $PolicyResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$PolicyId" -ErrorAction Stop
    }
    catch {
        throw "Policy '$PolicyId' not found in tenant: $_"
    }

    Write-Verbose "Policy name: $($PolicyResponse.name)"

    # Get assignments
    try {
        $AssignmentsResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$PolicyId/assignments" -ErrorAction Stop
    }
    catch {
        throw "Failed to retrieve assignments for policy '$PolicyId': $_"
    }

    $Json = $AssignmentsResponse | ConvertTo-Json -Depth 100

    if (-not (Test-Path $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }

    $SafeId   = $PolicyId -replace '[\\/:*?"<>|]', '_'
    $SafeName = $PolicyResponse.name -replace '[\\/:*?"<>|]', '_'
    $FilePath = Join-Path $OutputFolder "$SafeName-$SafeId-Assignments.json"

    $Json | Set-Content -Path $FilePath -Encoding UTF8 -Force

    Write-Host "Assignments exported to '$FilePath'."

    return [PSCustomObject]@{
        FilePath = $FilePath
        JsonData = $Json
    }
}