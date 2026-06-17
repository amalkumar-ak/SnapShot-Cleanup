param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory=$true)]
    [string]$LandingZone,

    [Parameter(Mandatory=$true)]
    [int]$OlderThanDays,

    [Parameter(Mandatory=$false)]
    [bool]$Simulate = $true,

    [Parameter(Mandatory=$true)]
    [string]$ReportPath
)

# =====================================================================
# Landing Zone -> Subscription Mapping
# ---------------------------------------------------------------------
# TODO: Replace the placeholder subscription IDs below with the real
#       subscription GUIDs for your own environment.
#
#       To find a subscription GUID:
#           az account list --output table
#           # or
#           Get-AzSubscription
#
#       Add or remove landing zones as needed. The landing zone name
#       supplied via -LandingZone must match one of the entries here,
#       or the script will throw.
# =====================================================================
switch ($LandingZone) {

    "lz-sandbox" {
        $SubscriptionId = "00000000-0000-0000-0000-000000000001" #Update with your subscription ID
    }

    "lz-integration" {
        $SubscriptionId = "00000000-0000-0000-0000-000000000002" #Update with your subscription ID
    }

    "lz-dev" {
        $SubscriptionId = "00000000-0000-0000-0000-000000000003" #Update with your subscription ID
    }

    "lz-test" {
        $SubscriptionId = "00000000-0000-0000-0000-000000000004" #Update with your subscription ID
    }

    "lz-prod" {
        $SubscriptionId = "00000000-0000-0000-0000-000000000005" #Update with your subscription ID
    }

    default {
        throw "Invalid LandingZone provided: '$LandingZone'. Update the switch block in SnapShot-CleanUp.ps1 to add new landing zones."
    }
}

# =====================================================================
# Set Azure Context
# =====================================================================
Write-Host "====================================="
Write-Host "Setting Azure Context"
Write-Host "Subscription: $SubscriptionId"
Write-Host "====================================="

Set-AzContext `
    -SubscriptionId $SubscriptionId `
    -ErrorAction Stop

# =====================================================================
# Variables
# =====================================================================
$CutoffDate = (Get-Date).ToUniversalTime().Date.AddDays(-$OlderThanDays)

Write-Host ""
Write-Host "Resource Group : $ResourceGroup"
Write-Host "Older Than     : $OlderThanDays days"
Write-Host "Cutoff Date    : $CutoffDate"
Write-Host "Simulation     : $Simulate"
Write-Host ""

# =====================================================================
# Report Array
# =====================================================================
$Report = @()

# =====================================================================
# Get Snapshots
# =====================================================================
try {

    $Snapshots = Get-AzSnapshot `
        -ResourceGroupName $ResourceGroup `
        -ErrorAction Stop
}
catch {

    Write-Error "Failed to fetch snapshots from RG: $ResourceGroup"
    throw
}

# =====================================================================
# Process Snapshots
# =====================================================================
foreach ($Snapshot in $Snapshots) {

    # Skip newer snapshots
    if ($Snapshot.TimeCreated -ge $CutoffDate) {
        continue
    }

    # =================================================================
    # DoNotDelete Tag (case-insensitive value match)
    # =================================================================
    $DoNotDelete = $false

    if ($Snapshot.Tags -and $Snapshot.Tags.ContainsKey("DoNotDelete")) {

        if ($Snapshot.Tags["DoNotDelete"].ToString().ToLower() -eq "true") {
            $DoNotDelete = $true
        }
    }

    Write-Host "====================================="
    Write-Host "Snapshot Name : $($Snapshot.Name)"
    Write-Host "Created Date  : $($Snapshot.TimeCreated)"
    Write-Host "Protected     : $DoNotDelete"
    Write-Host "====================================="

    # =================================================================
    # Skip Protected Snapshots
    # =================================================================
    if ($DoNotDelete) {

        Write-Host "[SKIPPED] DoNotDelete=True" `
            -ForegroundColor Yellow

        $Report  = [PSCustomObject]@{
            LandingZone   = $LandingZone
            Subscription  = $SubscriptionId
            ResourceGroup = $ResourceGroup
            SnapshotName  = $Snapshot.Name
            CreatedDate   = $Snapshot.TimeCreated
            Status        = "Skipped-DoNotDelete"
            Simulation    = $Simulate
            ErrorMessage  = ""
        }

        continue
    }

    # =================================================================
    # Simulation Mode
    # =================================================================
    if ($Simulate -eq $true) {

        Write-Host "[SIMULATE] Would delete snapshot: $($Snapshot.Name)" `
            -ForegroundColor Yellow

        $Report  = [PSCustomObject]@{
            LandingZone   = $LandingZone
            Subscription  = $SubscriptionId
            ResourceGroup = $ResourceGroup
            SnapshotName  = $Snapshot.Name
            CreatedDate   = $Snapshot.TimeCreated
            Status        = "WouldDelete"
            Simulation    = $true
            ErrorMessage  = ""
        }

        continue
    }

    # =================================================================
    # Delete Snapshot
    # =================================================================
    try {

        Remove-AzSnapshot `
            -ResourceGroupName $ResourceGroup `
            -SnapshotName $Snapshot.Name `
            -Force `
            -ErrorAction Stop

        Write-Host "[DELETED] $($Snapshot.Name)" `
            -ForegroundColor Green

        $Report  = [PSCustomObject]@{
            LandingZone   = $LandingZone
            Subscription  = $SubscriptionId
            ResourceGroup = $ResourceGroup
            SnapshotName  = $Snapshot.Name
            CreatedDate   = $Snapshot.TimeCreated
            Status        = "Deleted"
            Simulation    = $false
            ErrorMessage  = ""
        }
    }
    catch {

        Write-Error "Failed deleting snapshot: $($Snapshot.Name)"
        Write-Error $_.Exception.Message

        $Report  = [PSCustomObject]@{
            LandingZone   = $LandingZone
            Subscription  = $SubscriptionId
            ResourceGroup = $ResourceGroup
            SnapshotName  = $Snapshot.Name
            CreatedDate   = $Snapshot.TimeCreated
            Status        = "DeleteFailed"
            Simulation    = $false
            ErrorMessage  = $_.Exception.Message
        }
    }
}

# =====================================================================
# Export Report
# =====================================================================
$Report | Export-Csv `
    -Path $ReportPath `
    -NoTypeInformation

Write-Host ""
Write-Host "====================================="
Write-Host "Report Exported"
Write-Host $ReportPath
Write-Host "====================================="
