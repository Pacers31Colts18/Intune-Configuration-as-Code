function New-IntuneAssignmentJson {
    <#
    .SYNOPSIS
        Creates an Intune Device Configuration Policy assignment JSON file from CSV input.
    .DESCRIPTION
        Reads a CSV file containing PolicyId, GroupId, AssignmentType, and optional FilterId/FilterType
        columns and produces a JSON file in the format expected by the Graph API assignments endpoint.
        Returns a result object with FilePath and JsonData properties, consistent with
        Export-IntuneDeviceConfigurationPolicyAssignments.
    .PARAMETER InputFilePath
        Mandatory. Path to the input CSV file.
    .PARAMETER OutputFilePath
        Mandatory. Path where the output JSON file will be written.
    .NOTES
        CSV must contain exactly one unique PolicyId.
        AssignmentType must be 'include' or 'exclude'.
        Exclusions cannot target All Devices or All Users.
    .EXAMPLE
        New-IntuneAssignmentJson -InputFilePath "C:\temp\assignments.csv" -OutputFilePath "C:\temp\new-assignments.json"
    .LINK
        https://learn.microsoft.com/en-us/powershell/microsoftgraph/overview
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$InputFilePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputFilePath
    )

    if (-not (Test-Path $InputFilePath)) {
        throw "CSV file not found at '$InputFilePath'."
    }

    $Rows = Import-Csv -Path $InputFilePath

    if (-not $Rows) {
        throw "CSV file '$InputFilePath' contains no rows."
    }

    # Validate required columns exist
    $RequiredColumns = @("PolicyId", "GroupId", "AssignmentType")
    foreach ($Col in $RequiredColumns) {
        if ($null -eq $Rows[0].PSObject.Properties[$Col]) {
            throw "CSV must contain a '$Col' column."
        }
    }

    # Validate single PolicyId
    $PolicyIds = @($Rows | Select-Object -ExpandProperty PolicyId -Unique)
    if ($PolicyIds.Count -ne 1) {
        throw "CSV must contain exactly one unique PolicyId. Found: $($PolicyIds -join ', ')"
    }

    $PolicyId   = [string]$PolicyIds[0]
    $Assignments = @()

    foreach ($Row in $Rows) {

        $GroupId        = $Row.GroupId.Trim()
        $AssignmentType = $Row.AssignmentType.Trim().ToLower()

        if ($AssignmentType -notin @("include", "exclude")) {
            throw "AssignmentType must be 'include' or 'exclude'. Found: '$AssignmentType' in row for GroupId '$GroupId'."
        }

        $IsAllDevices = $GroupId -eq "adadadad-808e-44e2-905a-0b7873a8a531"
        $IsAllUsers   = $GroupId -eq "acacacac-9df4-4c7d-9d50-4ef0226f57a9"
        $IsExclusion  = $AssignmentType -eq "exclude"

        if ($IsExclusion -and ($IsAllDevices -or $IsAllUsers)) {
            throw "Exclusions cannot be applied to All Devices or All Users. GroupId: '$GroupId'."
        }

        $ODataType = if ($IsAllDevices) {
            "#microsoft.graph.allDevicesAssignmentTarget"
        } elseif ($IsAllUsers) {
            "#microsoft.graph.allUsersAssignmentTarget"
        } elseif ($IsExclusion) {
            "#microsoft.graph.exclusionGroupAssignmentTarget"
        } else {
            "#microsoft.graph.groupAssignmentTarget"
        }

        # Filters only apply to include assignments
        $FilterId   = $null
        $FilterType = "none"

        if (-not $IsExclusion) {
            if ($Row.PSObject.Properties["FilterId"]   -and $Row.FilterId)   { $FilterId   = $Row.FilterId.Trim() }
            if ($Row.PSObject.Properties["FilterType"] -and $Row.FilterType) { $FilterType = $Row.FilterType.Trim() }
        }

        $Assignments += [PSCustomObject]@{
            source   = "direct"
            id       = "${PolicyId}_${GroupId}"
            sourceId = $PolicyId
            target   = [PSCustomObject]@{
                "@odata.type"                              = $ODataType
                groupId                                    = if ($IsAllDevices -or $IsAllUsers) { $null } else { $GroupId }
                deviceAndAppManagementAssignmentFilterId   = $FilterId
                deviceAndAppManagementAssignmentFilterType = $FilterType
            }
        }
    }

    $OutputObject = [PSCustomObject]@{
        "@odata.context" = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$PolicyId')/assignments"
        value            = $Assignments
    }

    $JsonOutput = $OutputObject | ConvertTo-Json -Depth 10

    # Ensure output directory exists
    $Directory = Split-Path $OutputFilePath -Parent
    if ($Directory -and -not (Test-Path $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $JsonOutput | Set-Content -Path $OutputFilePath -Encoding UTF8 -Force

    Write-Host "New assignment JSON written to '$OutputFilePath'."

    return [PSCustomObject]@{
        FilePath = $OutputFilePath
        JsonData = $JsonOutput
    }
}
