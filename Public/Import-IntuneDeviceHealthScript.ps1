function Import-IntuneDeviceHealthScript {
<#
.SYNOPSIS
Imports a single Intune Device Health Script from a flat folder.
.DESCRIPTION
Reads a JSON metadata file and detection/remediation PowerShell scripts from a single folder.
Creates a new Device Health Script in Intune if one with the same displayName does not already exist.
Supports -WhatIf for dry-run validation.
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

    Write-Host "Processing folder: $FolderPath"

    # Find JSON metadata file
    $JsonFile = Get-ChildItem -Path $FolderPath -Filter *.json -File | Select-Object -First 1
    if (-not $JsonFile) {
        Write-Error "No JSON metadata file found in folder."
        return
    }

    # Parse JSON — strip @odata.context and @odata.nextLink
    try {
        $RawJson = Get-Content -Path $JsonFile.FullName -Raw
        $RawJson = $RawJson -replace '"[^"]*@odata\.context"\s*:\s*"[^"]*",?\s*', ''
        $RawJson = $RawJson -replace '"[^"]*@odata\.nextLink"\s*:\s*"[^"]*",?\s*', ''
        $JsonObject = $RawJson | ConvertFrom-Json
    }
    catch {
        Write-Error "Could not parse '$($JsonFile.Name)' as JSON."
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
        "highestAvailableVersion",
        "isGlobalScript"
    )

    foreach ($Prop in $PropertiesToRemove) {
        $JsonObject.PSObject.Properties.Remove($Prop)
    }

    $DisplayName = $JsonObject.displayName
    if (-not $DisplayName) {
        Write-Error "JSON file does not contain a 'displayName' property."
        return
    }

    # Detection script — mandatory
    $DetectionScript = Get-ChildItem -Path $FolderPath -Filter "DetectionScript.ps1" -File | Select-Object -First 1
    if (-not $DetectionScript) {
        Write-Error "DetectionScript.ps1 not found."
        return
    }

    $DetectionBytes = [System.IO.File]::ReadAllBytes($DetectionScript.FullName)
    $JsonObject.detectionScriptContent = [Convert]::ToBase64String($DetectionBytes)

    # Remediation script — optional
    $RemediationScript = Get-ChildItem -Path $FolderPath -Filter "RemediationScript.ps1" -File | Select-Object -First 1
    if ($RemediationScript) {
        $RemediationBytes = [System.IO.File]::ReadAllBytes($RemediationScript.FullName)
        $JsonObject.remediationScriptContent = [Convert]::ToBase64String($RemediationBytes)
    }
    else {
        $JsonObject.remediationScriptContent = ""
    }

    # Check if script already exists
    try {
        $FilterUri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts?`$filter=displayName eq '$DisplayName'"
        $Existing = Invoke-MgGraphRequest -Method GET -Uri $FilterUri -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to query existing scripts. Error: $_"
        return
    }

    if ($Existing.value.Count -gt 0) {
        Write-Warning "Script '$DisplayName' already exists in tenant. Aborting."
        return
    }

    $Body = $JsonObject | ConvertTo-Json -Depth 20

    if ($PSCmdlet.ShouldProcess($DisplayName, "Create Intune Device Health Script")) {
        try {
            $Created = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts" -Body $Body -ContentType "application/json" -ErrorAction Stop
        }
        catch {
            Write-Error "Failed to create script '$DisplayName'. Error: $_"
            return
        }

        Write-Host "Script created: $DisplayName [$($Created.id)]"
        return $Created
    }
    else {
        Write-Host "WhatIf: Would create script '$DisplayName'"
    }
}
