function Merge-IntuneAssignmentJson {
<#
.SYNOPSIS
Merges Intune Assignment JSON files.
.DESCRIPTION
This function merges two Intune Assignment JSON files into a single output file.
.PARAMETER OriginalAssignmentFile
The path to the original assignment JSON file.
.PARAMETER AdditionalAssignmentFile
The path to the additional assignment JSON file.
.PARAMETER OutputFile
The path to the output merged assignment JSON file.
.EXAMPLE
Merge-IntuneAssignmentJson -OriginalAssignmentFile "C:\temp\Original.json" -AdditionalAssignmentFile "C:\temp\Additional.json" -OutputFile "C:\temp\Merged.json"
Merges two Intune Assignment JSON files into a single output file.
#> 
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)]
        [string]$OriginalAssignmentFile,

        [Parameter(Mandatory = $false)]
        [string]$AdditionalAssignmentFile,

        [Parameter(Mandatory = $true)]
        [string]$OutputFile
    )

    # Initialize mergedAssignments
    $mergedAssignments = @()

    # Log the paths of the files being processed
    Write-Host "Merging Assignment Files..."
    Write-Host "Original Assignment File: $OriginalAssignmentFile"
    Write-Host "Additional Assignment File: $AdditionalAssignmentFile"

    # Load original file if it exists, otherwise start empty
    if (Test-Path $OriginalAssignmentFile) {
        Write-Host "Loading original assignment file..."
        $data1 = Get-Content $OriginalAssignmentFile -Raw | ConvertFrom-Json
        if ($data1.value) {
            $mergedAssignments += $data1.value
            $odataContext = $data1.'@odata.context'
        } else {
            Write-Warning "Original assignment file has no 'value'. Starting empty."
            $odataContext = ""
        }
    } else {
        Write-Warning "Original assignment file not found. Creating empty assignment JSON."
        $odataContext = ""
    }

    # Merge additional file if it exists
    if ($AdditionalAssignmentFile -and (Test-Path $AdditionalAssignmentFile)) {
        Write-Host "Loading additional assignment file..."
        $data2 = Get-Content $AdditionalAssignmentFile -Raw | ConvertFrom-Json
        if ($data2.value) {
            $mergedAssignments += $data2.value
        } else {
            Write-Warning "Additional file has no 'value'. Ignoring."
        }
    } elseif ($AdditionalAssignmentFile) {
        Write-Warning "Additional file not found. Ignoring."
    }

    # Remove duplicates by id
    if ($mergedAssignments.Count -gt 0) {
        $mergedAssignments = $mergedAssignments | Sort-Object id -Unique
    }

    # Build final JSON object
    $finalObject = [PSCustomObject]@{
        "@odata.context" = $odataContext
        value            = $mergedAssignments
    }

    # Ensure output directory exists
    $directory = Split-Path $OutputFile -Parent
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    # Save JSON
    $jsonOutput = $finalObject | ConvertTo-Json -Depth 10
    $jsonOutput | Set-Content -Path $OutputFile -Encoding UTF8 -Force

    Write-Host "Merged assignment JSON written to $OutputFile"
    return $jsonOutput
}