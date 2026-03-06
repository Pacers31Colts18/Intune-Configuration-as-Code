function Import-IntuneDeviceCompliancePolicy {
    <#
    .SYNOPSIS
        Imports Intune Device Compliance Policies from JSON files, creating new policies only.
    .DESCRIPTION
        Reads JSON files from a specified folder and creates new Intune Device Compliance
        Policies via Microsoft Graph. If a policy with the same name already exists, the file
        is skipped and a warning is emitted — use Test-IntuneDeviceCompliancePolicy first
        to catch conflicts before import.

        Supports -WhatIf for dry-run validation without hitting the Graph API.
    .PARAMETER FolderPath
        Mandatory. The path to the folder containing JSON files of Intune Device Compliance Policies.
    .NOTES
        Requires:
        - Microsoft.Graph PowerShell SDK (Invoke-MgGraphRequest, Get-MgContext)
        - DeviceManagementConfiguration.ReadWrite.All
    .EXAMPLE
        Import-IntuneDeviceCompliancePolicy -FolderPath "C:\temp\IntunePolicies"
    .EXAMPLE
        Import-IntuneDeviceCompliancePolicy -FolderPath "C:\temp\IntunePolicies" -WhatIf
    .LINK
        https://learn.microsoft.com/en-us/powershell/microsoftgraph/overview
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FolderPath
    )

    # Ensure Graph connection exists
    if (-not (Get-MgContext)) {
        Write-Error "Not connected to Microsoft Graph. Run Connect-MgGraph first."
        return
    }

    if (-not (Test-Path $FolderPath)) {
        Write-Error "Folder path '$FolderPath' does not exist."
        return
    }

    $JsonFiles = Get-ChildItem -Path $FolderPath -Filter *.json -File

    if (-not $JsonFiles) {
        Write-Error "No JSON files found in folder: $FolderPath"
        return
    }

    # Properties that are tenant-specific and must be stripped before import
    $PropertiesToRemove = @(
        "id",
        "createdDateTime",
        "lastModifiedDateTime",
        "version",
        "supportsScopeTags",
        "supportedScopeTags"
    )

    $Results = @()

    foreach ($File in $JsonFiles) {

        Write-Host "Processing: $($File.Name)"

        # Parse JSON
        try {
            $RawJson    = Get-Content -Path $File.FullName -Raw
            $JsonObject = $RawJson | ConvertFrom-Json
        }
        catch {
            Write-Warning "Could not parse '$($File.Name)' as JSON. Skipping."
            continue
        }

        # Strip read-only / tenant-specific properties
        foreach ($Prop in $PropertiesToRemove) {
            $JsonObject.PSObject.Properties.Remove($Prop)
        }

        $DisplayName = $JsonObject.displayName

        if (-not $DisplayName) {
            Write-Warning "Policy file '$($File.Name)' does not contain a 'displayName' property. Skipping."
            continue
        }

        # Check whether the policy already exists (skip rather than overwrite)
        try {
            $FilterUri = "https://graph.microsoft.com/beta/deviceManagement/devicecompliancePolicies?`$filter=displayName eq '$DisplayName'"
            $Existing  = Invoke-MgGraphRequest -Method GET -Uri $FilterUri -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to query existing policies for '$DisplayName'. Skipping. Error: $_"
            continue
        }

        if ($Existing.value.Count -gt 0) {
            Write-Warning "Policy '$DisplayName' already exists in tenant. Skipping — run Test-IntuneDeviceCompliancePolicy to review conflicts before import."
            continue
        }

        $Body = $JsonObject | ConvertTo-Json -Depth 20

        if ($PSCmdlet.ShouldProcess($DisplayName, "Create Intune Device Compliance Policy")) {

            try {
                $Created = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/devicecompliancePolicies" -Body $Body -ContentType "application/json" -ErrorAction Stop
            }
            catch {
                Write-Warning "Failed to create policy '$DisplayName'. Skipping. Error: $_"
                continue
            }

            $PolicyId = $Created.id

            if (-not $PolicyId) {
                Write-Warning "Policy '$DisplayName' was submitted but no ID was returned. Skipping."
                continue
            }

            Write-Host "Policy created: $DisplayName [$PolicyId]"

            $Results += [PSCustomObject]@{
                Name       = $DisplayName
                Id         = $PolicyId
                SourceFile = $File.Name
            }
        }
        else {
            # -WhatIf path — report what would happen without calling the API
            Write-Host "WhatIf: Would create policy '$DisplayName' from '$($File.Name)'"
        }
    }

    return $Results
}
