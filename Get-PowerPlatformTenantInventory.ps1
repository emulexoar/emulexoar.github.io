<#
.SYNOPSIS
Master script to perform a comprehensive inventory of Power Platform assets
(Power Apps, Power Automate, CoPilot Studio, Power BI, Power Pages)
and their connections, focusing on O365 integrations.

.DESCRIPTION
This script orchestrates the execution of several specialized inventory scripts.
It handles authentication, data collection for various Power Platform components,
analyzes for O365 connections, and exports the findings to CSV files.

Prerequisites:
1. PowerShell 5.1
2. PAC CLI installed and in PATH.
3. Necessary PowerShell Modules installed (run `install_modules.ps1` first, then ensure
   Microsoft.PowerApps.Administration.PowerShell, Microsoft.PowerApps.PowerShell.Apps,
   and MicrosoftPowerBIMgmt and its submodules are installed if `install_modules.ps1` had issues).
   - Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -Force
   - Install-Module Microsoft.PowerApps.PowerShell.Apps -Scope CurrentUser -Force
   - Install-Module MicrosoftPowerBIMgmt -Scope CurrentUser -Force (and its sub-modules if needed)
4. Appropriate permissions to access the Power Platform environments and services.

.PARAMETER OutputDirectory
The directory where CSV inventory files will be saved. Defaults to a subdirectory "PowerPlatformInventory" in the script's location.

.PARAMETER EnvironmentUrl
The URL of your Power Platform (Dataverse/Dynamics 365) environment.
Example: "https://yourorg.crm.dynamics.com"

.PARAMETER SharePointAdminUrl
The URL of your SharePoint Admin Center. Required for SharePoint PnP connection.
Example: "https://yourtenant-admin.sharepoint.com"

.PARAMETER PowerBIncludePersonalWorkspaces
Switch to include personal workspaces in the Power BI scan.

.PARAMETER PowerBIScanAllOrgWorkspaces
Switch to scan all organization workspaces in Power BI (requires Power BI Admin role).

.EXAMPLE
.\Get-PowerPlatformTenantInventory.ps1 -EnvironmentUrl "https://myorg.crm.dynamics.com" -SharePointAdminUrl "https://mytenant-admin.sharepoint.com" -OutputDirectory "C:\Temp\Inventory"

#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "PowerPlatformInventory_$(Get-Date -Format 'yyyyMMddHHmmss')"),

    [Parameter(Mandatory=$true)]
    [string]$EnvironmentUrl, # e.g., "https://yourorg.crm.dynamics.com"

    [Parameter(Mandatory=$true)]
    [string]$SharePointAdminUrl, # e.g., "https://yourtenant-admin.sharepoint.com"

    [Parameter(Mandatory=$false)]
    [switch]$PowerBIncludePersonalWorkspaces,

    [Parameter(Mandatory=$false)]
    [switch]$PowerBIScanAllOrgWorkspaces
)

# --- Setup ---
$ErrorActionPreference = "SilentlyContinue" # Can be changed to "Stop" for debugging script development
$startTime = Get-Date

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputDirectory)) {
    Write-Host "Creating output directory: $OutputDirectory"
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
Write-Host "Inventory files will be saved to: $OutputDirectory"

# --- Dot-source helper scripts ---
Write-Host "Loading helper scripts..."
try {
    . (Join-Path $PSScriptRoot "auth_functions.ps1")
    . (Join-Path $PSScriptRoot "inventory_powerapps.ps1")
    . (Join-Path $PSScriptRoot "inventory_powerautomate.ps1")
    . (Join-Path $PSScriptRoot "inventory_copilotstudio.ps1")
    . (Join-Path $PSScriptRoot "inventory_powerbi.ps1")
    . (Join-Path $PSScriptRoot "inventory_powerpages.ps1")
    . (Join-Path $PSScriptRoot "analyze_o365_connections.ps1")
    Write-Host "Helper scripts loaded successfully."
}
catch {
    Write-Error "Failed to load one or more helper scripts. Ensure they are in the same directory as this master script. Error: $($_.Exception.Message)"
    exit 1
}

# --- Authentications ---
Write-Host "`n--- Starting Authentications ---"
$powerPlatformConnected = Connect-PowerPlatform -EnvironmentUrl $EnvironmentUrl
# $spoConnected = Connect-SPOnline -SharePointAdminUrl $SharePointAdminUrl # Needed if SharePoint specific actions are taken beyond what connectors report
$graphApiConnected = Connect-GraphAPI # For Azure AD context if needed by cmdlets
$pbiConnected = Connect-PBI

if (-not $powerPlatformConnected) {
    Write-Error "Failed to connect to Power Platform. Halting script. Check PAC CLI authentication and environment URL."
    exit 1
}
if (-not $pbiConnected) {
    Write-Warning "Failed to connect to Power BI Service. Power BI inventory will be skipped or incomplete."
}
# Add more checks as needed

# --- Inventory Collection ---
Write-Host "`n--- Starting Inventory Collection ---"

# Power Apps
Write-Host "Gathering Power Apps inventory..."
$powerAppsInventory = Get-PowerPlatformAppsInventory # Add -EnvironmentId if PAC context isn't enough
Export-Csv -Path (Join-Path $OutputDirectory "01_powerapps_inventory.csv") -InputObject $powerAppsInventory -NoTypeInformation -Force
Write-Host "Power Apps inventory saved to 01_powerapps_inventory.csv"

# Power Automate Flows
Write-Host "Gathering Power Automate Flows inventory..."
# Get-AdminFlow often needs EnvironmentName (GUID). We can attempt to get it from PAC's current context or require it as a param.
$currentPacAuth = pac auth list --json | ConvertFrom-Json | Where-Object {$_.isActive}
$currentEnvironmentId = $null
if ($currentPacAuth -and $currentPacAuth.environmentId) {
    $currentEnvironmentId = $currentPacAuth.environmentId
    Write-Host "Using current PAC CLI environment for Flows: $currentEnvironmentId"
} else {
    Write-Warning "Could not determine current PAC CLI environment ID. Flow inventory might be incomplete or use a default context."
    # Or prompt/require $EnvironmentId as a parameter for the script / pass to Get-PowerAutomateFlowsInventory
}
$powerAutomateInventory = Get-PowerAutomateFlowsInventory -EnvironmentName $currentEnvironmentId # Pass Env ID if available/needed
Export-Csv -Path (Join-Path $OutputDirectory "02_powerautomate_flows_inventory.csv") -InputObject $powerAutomateInventory -NoTypeInformation -Force
Write-Host "Power Automate Flows inventory saved to 02_powerautomate_flows_inventory.csv"

# CoPilot Studio (PVA) Bots
Write-Host "Gathering CoPilot Studio Bots inventory..."
$coPilotBotsInventory = Get-CoPilotStudioBotsInventory -EnvironmentName $currentEnvironmentId # Pass Env ID if available/needed
Export-Csv -Path (Join-Path $OutputDirectory "03_copilot_studio_bots_inventory.csv") -InputObject $coPilotBotsInventory -NoTypeInformation -Force
Write-Host "CoPilot Studio Bots inventory saved to 03_copilot_studio_bots_inventory.csv"

# Power BI
if ($pbiConnected) {
    Write-Host "Gathering Power BI inventory..."
    $powerBIInventory = Get-PowerBIInventory -IncludePersonalWorkspaces:$PowerBIncludePersonalWorkspaces -ScanAllOrgWorkspaces:$PowerBIScanAllOrgWorkspaces

    # Custom export for Power BI to make DataSources more readable
    $powerBIInventoryForCsv = $powerBIInventory | Select-Object *, @{
        Name='DataSourcesSummary';
        Expression={
            if ($_.DataSources) {
                ($_.DataSources | ForEach-Object { "$($_.DataSourceType) - Conn: $($_.ConnectionString) - GW: $($_.GatewayId)" }) -join " | "
            } else { "" }
        }
    }
    $powerBIInventoryForCsv | Export-Csv -Path (Join-Path $OutputDirectory "04_powerbi_inventory.csv") -NoTypeInformation -Force
    Write-Host "Power BI inventory saved to 04_powerbi_inventory.csv"
} else {
    Write-Warning "Skipping Power BI inventory due to authentication failure."
    $powerBIInventory = @() # Empty array
}

# Power Pages
Write-Host "Gathering Power Pages sites inventory..."
$powerPagesInventory = Get-PowerPagesSitesInventory # Assumes PAC CLI context is set
Export-Csv -Path (Join-Path $OutputDirectory "05_powerpages_inventory.csv") -InputObject $powerPagesInventory -NoTypeInformation -Force
Write-Host "Power Pages sites inventory saved to 05_powerpages_inventory.csv"


# --- Analyze for O365 Connections ---
Write-Host "`n--- Analyzing for SharePoint and O365 Connections ---"
$o365ConnectedItems = Get-O365ConnectedItems -PowerAppsInventory $powerAppsInventory `
                                             -PowerAutomateInventory $powerAutomateInventory `
                                             -CoPilotStudioBotsInventory $coPilotBotsInventory `
                                             -PowerBIInventory $powerBIInventory
                                             # Power Pages are implicitly Dataverse; O365 via embedded/flows needs correlation already noted in its own inventory.

# Custom export for O365 connected items to make O365ConnectionsDetail more readable
$o365ConnectedItemsForCsv = $o365ConnectedItems | Select-Object *, @{
    Name='O365ConnectionsSummary';
    Expression={
        if ($_.O365ConnectionsDetail) {
            ($_.O365ConnectionsDetail | ForEach-Object { "$($_.Service) (Connector: $($_.ConnectorDisplayName), Type: $($_.ConnectorType), DSType: $($_.DataSourceType))" }) -join " | "
        } else { "" }
    }
}
$o365ConnectedItemsForCsv | Export-Csv -Path (Join-Path $OutputDirectory "06_o365_connected_items.csv") -NoTypeInformation -Force
Write-Host "Analysis of O365 connected items saved to 06_o365_connected_items.csv"

# --- Summary ---
Write-Host "`n--- Inventory Summary ---"
Write-Host "Power Apps Found: $($powerAppsInventory.Count)"
Write-Host "Power Automate Flows Found: $($powerAutomateInventory.Count)"
Write-Host "CoPilot Studio Bots Found: $($coPilotBotsInventory.Count)"
Write-Host "Power BI Assets Found (Reports/Datasets): $($powerBIInventory.Count)"
Write-Host "Power Pages Sites Found: $($powerPagesInventory.Count)"
Write-Host "Total Items Identified with SharePoint/O365 Connections: $($o365ConnectedItems.Count)"

$endTime = Get-Date
Write-Host "`nInventory script finished."
Write-Host "Total execution time: $($endTime - $startTime)"
Write-Host "All reports saved in: $OutputDirectory"

# --- End of Script ---
# Remember to review the generated CSV files. For very complex connector details (e.g., specific SharePoint list IDs used in a Flow),
# manual inspection of the app/flow definition or more advanced parsing (not covered here) might be needed.
# This script provides a high-level inventory crucial for migration planning.
# Ensure all prerequisite modules (PAC CLI, PowerShell modules) are installed and functional in your PS 5.1 environment.
