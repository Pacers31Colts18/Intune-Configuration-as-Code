function New-IntuneAssignmentReport {
    <#
    .SYNOPSIS
        Generates a per-policy markdown report comparing existing, new, and merged assignments.
    .DESCRIPTION
        Takes the three assignment JSON files produced during the validate step and renders
        them as a markdown document with three labelled tables — existing, new, and merged.
        Each table resolves group display names and filter display names via extra Graph calls
        so reviewers see human-readable names rather than raw GUIDs.
        Returns a result object with FilePath and MarkdownContent properties.
    .PARAMETER PolicyId
        The GUID of the policy being reported on.
    .PARAMETER PolicyName
        The display name of the policy.
    .PARAMETER ExistingAssignmentFile
        Path to the exported existing-assignments JSON file. Optional — omit if the policy
        had no prior assignments.
    .PARAMETER NewAssignmentFile
        Mandatory. Path to the new-assignments JSON file built from the CSV.
    .PARAMETER MergedAssignmentFile
        Mandatory. Path to the merged-assignments JSON file.
    .PARAMETER OutputFolder
        Mandatory. Directory to write the markdown report file to.
    .EXAMPLE
        New-IntuneAssignmentReport -PolicyId "..." -PolicyName "My Policy" `
            -ExistingAssignmentFile "existing.json" -NewAssignmentFile "new.json" `
            -MergedAssignmentFile "merged.json" -OutputFolder "C:\staging\policyid"
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PolicyId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PolicyName,

        [Parameter()]
        [string]$ExistingAssignmentFile,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$NewAssignmentFile,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$MergedAssignmentFile,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputFolder
    )

    if (-not (Get-MgContext)) {
        throw "Not connected to Microsoft Graph. Run Connect-MgGraph first."
    }

    # ── Lookup caches so we don't repeat Graph calls ──────────────────────────
    $GroupCache  = @{}
    $FilterCache = @{}

    function Resolve-GroupName {
        param ([string]$Id)
        if (-not $Id) { return "_All Devices / All Users_" }
        if ($GroupCache.ContainsKey($Id)) { return $GroupCache[$Id] }
        try {
            $Group = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/groups/$Id" -ErrorAction Stop
            $Name  = $Group.displayName
        }
        catch {
            $Name = "_Unknown_"
        }
        $GroupCache[$Id] = $Name
        return $Name
    }

    function Resolve-FilterName {
        param ([string]$Id)
        if (-not $Id) { return "" }
        if ($FilterCache.ContainsKey($Id)) { return $FilterCache[$Id] }
        try {
            $Filter = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$Id" -ErrorAction Stop
            $Name   = $Filter.displayName
        }
        catch {
            $Name = "_Unknown_"
        }
        $FilterCache[$Id] = $Name
        return $Name
    }

    function Get-AssignmentType {
        param ([string]$ODataType)
        switch ($ODataType) {
            "#microsoft.graph.exclusionGroupAssignmentTarget" { return "Exclude" }
            "#microsoft.graph.allDevicesAssignmentTarget"     { return "Include" }
            "#microsoft.graph.allUsersAssignmentTarget"       { return "Include" }
            default                                           { return "Include" }
        }
    }

    # ── Render a single assignments array as a markdown table ─────────────────
    function ConvertTo-AssignmentTable {
        param ([array]$Assignments)

        if (-not $Assignments -or $Assignments.Count -eq 0) {
            return "_No assignments._`n"
        }

        $Header = "| Group Name | Group ID | Type | Filter Name | Filter ID | Filter Type |"
        $Divider = "|------------|----------|------|-------------|-----------|-------------|"
        $Rows = foreach ($A in $Assignments) {
            $Target     = $A.target
            $ODataType  = $Target.'@odata.type'
            $GroupId    = $Target.groupId
            $GroupName  = Resolve-GroupName -Id $GroupId
            $FilterId   = $Target.deviceAndAppManagementAssignmentFilterId
            $FilterType = $Target.deviceAndAppManagementAssignmentFilterType
            $FilterName = Resolve-FilterName -Id $FilterId
            $Type       = Get-AssignmentType -ODataType $ODataType

            $GroupIdDisplay  = if ($GroupId)  { $GroupId }  else { "_N/A_" }
            $FilterIdDisplay = if ($FilterId) { $FilterId } else { "_None_" }
            $FilterNmDisplay = if ($FilterName) { $FilterName } else { "_None_" }
            $FilterTyDisplay = if ($FilterType -and $FilterType -ne "none") { $FilterType } else { "_None_" }

            "| $GroupName | $GroupIdDisplay | $Type | $FilterNmDisplay | $FilterIdDisplay | $FilterTyDisplay |"
        }

        return ($Header, $Divider + $Rows) -join "`n"
    }

    # ── Load each JSON file ───────────────────────────────────────────────────
    $ExistingAssignments = @()
    if ($ExistingAssignmentFile -and (Test-Path $ExistingAssignmentFile)) {
        $Data = Get-Content $ExistingAssignmentFile -Raw | ConvertFrom-Json
        if ($Data.value) { $ExistingAssignments = $Data.value }
    }

    $NewAssignments = @()
    if (Test-Path $NewAssignmentFile) {
        $Data = Get-Content $NewAssignmentFile -Raw | ConvertFrom-Json
        if ($Data.value) { $NewAssignments = $Data.value }
    } else {
        throw "New assignment file not found: '$NewAssignmentFile'."
    }

    $MergedAssignments = @()
    if (Test-Path $MergedAssignmentFile) {
        $Data = Get-Content $MergedAssignmentFile -Raw | ConvertFrom-Json
        if ($Data.value) { $MergedAssignments = $Data.value }
    } else {
        throw "Merged assignment file not found: '$MergedAssignmentFile'."
    }

    # ── Build markdown ────────────────────────────────────────────────────────
    $RunDate  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm UTC")
    $SafeName = $PolicyName -replace '[\\/:*?"<>|]', '_'

    $Markdown  = "# Assignment Report: $PolicyName`n`n"
    $Markdown += "> **Policy ID:** \`$PolicyId\``n"
    $Markdown += "> **Generated:** $RunDate`n`n"
    $Markdown += "---`n`n"

    $Markdown += "## Existing Assignments ($($ExistingAssignments.Count))`n`n"
    $Markdown += (ConvertTo-AssignmentTable -Assignments $ExistingAssignments)
    $Markdown += "`n`n"

    $Markdown += "## New Assignments Being Added ($($NewAssignments.Count))`n`n"
    $Markdown += (ConvertTo-AssignmentTable -Assignments $NewAssignments)
    $Markdown += "`n`n"

    $Markdown += "## Final Merged Assignments ($($MergedAssignments.Count))`n`n"
    $Markdown += (ConvertTo-AssignmentTable -Assignments $MergedAssignments)
    $Markdown += "`n"

    # ── Write file ────────────────────────────────────────────────────────────
    if (-not (Test-Path $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }

    $FilePath = Join-Path $OutputFolder "$SafeName-$PolicyId-AssignmentReport.md"
    $Markdown | Set-Content -Path $FilePath -Encoding UTF8 -Force

    Write-Host "Assignment report written to '$FilePath'."

    return [PSCustomObject]@{
        FilePath        = $FilePath
        MarkdownContent = $Markdown
    }
}