function New-IntuneAssignmentJson {
<#
.SYNOPSIS
Creates Microsoft Intune Assignment JSON files from CSV input.
.DESCRIPTION
This function creates Intune Assignment JSON files from CSV input containing PolicyId, GroupId, and AssignmentType columns.
.PARAMETER InputFilePath
Mandatory. The path to the input CSV file.
.PARAMETER OutputFilePath
Mandatory. The path to the output JSON file.
.NOTES
Requires:
- Microsoft.Graph PowerShell SDK (e.g., Invoke-MgGraphRequest, Get-MgContext)
- Microsoft.Graph.DeviceManagement permissions to read and write configuration policies.
.EXAMPLE
New-IntuneAssignmentJson -InputFilePath "C:\temp\IntuneAssignments.csv" -OutputFilePath "C:\temp\IntuneAssignment.json"
Creates an Intune Assignment JSON file from the specified CSV input.
.LINK
 https://learn.microsoft.com/en-us/powershell/microsoftgraph/overview
    #> 

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$InputFilePath,
        [Parameter(Mandatory = $true)]
        [string]$OutputFilePath
    )

    # Validate CSV Exists
    if (-not (Test-Path $InputFilePath)) { 
        Write-Error "CSV file not found at $InputFilePath" 
    }

    $rows = Import-Csv -Path $InputFilePath

    if (-not $rows) { 
        Write-Error "CSV file contains no rows."
    }

    # Validate Required Columns
    if (-not $rows[0].PolicyId) {
        Write-Error "CSV must contain a PolicyId column."
    }

    if (-not $rows[0].GroupId) {
        Write-Error "CSV must contain a GroupId column."
    }

    if (-not $rows[0].AssignmentType) {
        Write-Error "CSV must contain an AssignmentType column (include/exclude)."
    }

    # Validate Single PolicyId
    $policyIds = @($rows | Select-Object -ExpandProperty PolicyId -Unique)

    if ($policyIds.Count -ne 1) {
        Write-Error "CSV must contain only one PolicyId."
    }

    $PolicyId = [string]$policyIds[0]

    $assignments = @()

    foreach ($row in $rows) {

        $groupId = $row.GroupId.Trim()
        $assignmentType = $row.AssignmentType.Trim().ToLower()

        if ($assignmentType -notin @("include", "exclude")) {
            Write-Error "AssignmentType must be either 'include' or 'exclude'. Found: $assignmentType"
        }

        $isAllDevices = $groupId -eq "adadadad-808e-44e2-905a-0b7873a8a531"
        $isAllUsers = $groupId -eq "acacacac-9df4-4c7d-9d50-4ef0226f57a9"
        $isExclusion = $assignmentType -eq "exclude"

        if ($isExclusion -and ($isAllDevices -or $isAllUsers)) {
            Write-Error "Exclusions cannot be applied to All Devices or All Users."
        }

        # Determine OData Type
        $odataType = if ($isAllDevices) {
            "#microsoft.graph.allDevicesAssignmentTarget"
        }
        elseif ($isAllUsers) {
            "#microsoft.graph.allUsersAssignmentTarget"
        }
        elseif ($isExclusion) {
            "#microsoft.graph.exclusionGroupAssignmentTarget"
        }
        else {
            "#microsoft.graph.groupAssignmentTarget"
        }

        # Handle Filters
        $filterId = $null
        $filterType = "none"

        if (-not $isExclusion) {
            if ($row.FilterId) { $filterId = $row.FilterId.Trim() }
            if ($row.FilterType) { $filterType = $row.FilterType.Trim() }
        }

        # Build Assignment Object
        $assignments += [PSCustomObject]@{
            source   = "direct"
            id       = "${PolicyId}_$groupId"
            sourceId = $PolicyId
            target   = [PSCustomObject]@{
                "@odata.type"                              = $odataType
                groupId                                    = if ($isAllDevices -or $isAllUsers) { $null } else { $groupId }
                deviceAndAppManagementAssignmentFilterId   = $filterId
                deviceAndAppManagementAssignmentFilterType = $filterType
            }
        }
    }

    # Build Final JSON
    $jsonOutput = [PSCustomObject]@{
        "@odata.context" = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$PolicyId')/assignments"
        value            = $assignments
    } | ConvertTo-Json -Depth 10

    # Ensure output directory exists
    $directory = Split-Path $OutputFilePath -Parent
    if (-not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $jsonOutput | Set-Content -Path $OutputFilePath -Encoding UTF8 -Force

    Write-Host "Assignment JSON created at $OutputFilePath"

    return $jsonOutput
}