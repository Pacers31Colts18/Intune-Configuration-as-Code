function Merge-IntuneAssignmentJson {
    <#
    .SYNOPSIS
        Merges two Intune assignment JSON files into one, deduplicating by assignment id.
    .DESCRIPTION
        Loads assignments from an original file and an additional file, merges them,
        removes duplicates by id, and writes the result to an output file.
        Either source file can be absent — the function will warn and continue with
        whatever is available.
    .PARAMETER OriginalAssignmentFile
        Path to the existing/exported assignment JSON file.
    .PARAMETER AdditionalAssignmentFile
        Path to the new assignment JSON file to merge in.
    .PARAMETER OutputFile
        Mandatory. Path to write the merged output JSON file.
    .EXAMPLE
        Merge-IntuneAssignmentJson -OriginalAssignmentFile "C:\existing.json" -AdditionalAssignmentFile "C:\new.json" -OutputFile "C:\merged.json"
    #>

    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$OriginalAssignmentFile,

        [Parameter()]
        [string]$AdditionalAssignmentFile,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputFile
    )

    $MergedAssignments = @()
    $ODataContext      = ""

    # Load original
    if ($OriginalAssignmentFile -and (Test-Path $OriginalAssignmentFile)) {
        Write-Host "Loading original assignment file: '$OriginalAssignmentFile'"
        $Data = Get-Content $OriginalAssignmentFile -Raw | ConvertFrom-Json
        if ($Data.value) {
            $MergedAssignments += $Data.value
            $ODataContext = $Data.'@odata.context'
        } else {
            Write-Warning "Original assignment file has no 'value' array. Skipping."
        }
    } else {
        Write-Warning "Original assignment file not found or not specified. Starting with empty set."
    }

    # Load additional
    if ($AdditionalAssignmentFile -and (Test-Path $AdditionalAssignmentFile)) {
        Write-Host "Loading additional assignment file: '$AdditionalAssignmentFile'"
        $Data = Get-Content $AdditionalAssignmentFile -Raw | ConvertFrom-Json
        if ($Data.value) {
            $MergedAssignments += $Data.value
        } else {
            Write-Warning "Additional assignment file has no 'value' array. Skipping."
        }
    } else {
        Write-Warning "Additional assignment file not found or not specified. Skipping."
    }

    if ($MergedAssignments.Count -eq 0) {
        throw "No assignments found in either input file. Nothing to write."
    }

    # Deduplicate by id
    $MergedAssignments = $MergedAssignments | Sort-Object id -Unique

    $FinalObject = [PSCustomObject]@{
        "@odata.context" = $ODataContext
        value            = $MergedAssignments
    }

    $Directory = Split-Path $OutputFile -Parent
    if ($Directory -and -not (Test-Path $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $JsonOutput = $FinalObject | ConvertTo-Json -Depth 10
    $JsonOutput | Set-Content -Path $OutputFile -Encoding UTF8 -Force

    Write-Host "Merged assignment JSON written to '$OutputFile'."

    return [PSCustomObject]@{
        FilePath = $OutputFile
        JsonData = $JsonOutput
    }
}