<#
.SYNOPSIS
Functions to inventory Power Apps (Canvas and Model-Driven) and their connectors.

.DESCRIPTION
This script uses PAC CLI and Power Apps PowerShell cmdlets to list applications
and identify their connections. It assumes prior authentication to the Power Platform
and that necessary modules (Microsoft.PowerApps.Administration.PowerShell, Microsoft.PowerApps.PowerShell.Apps)
are installed.
#>

#Requires -Version 5.1

# Ensure the Power Apps admin module is available
# Users should install this: Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -Force
# And: Install-Module Microsoft.PowerApps.PowerShell.Apps -Scope CurrentUser -Force

Function Get-PowerPlatformAppsInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$EnvironmentId # Optional: Specify environment ID if not using default from pac auth
    )

    Write-Host "Starting Power Apps inventory..."
    $allAppsData = [System.Collections.Generic.List[object]]::new()

    # --- Get Canvas Apps ---
    Write-Host "Fetching Canvas Apps..."
    try {
        # Ensure PowerApps admin cmdlets are available
        Import-Module Microsoft.PowerApps.Administration.PowerShell -ErrorAction SilentlyContinue
        Import-Module Microsoft.PowerApps.PowerShell.Apps -ErrorAction SilentlyContinue

        if (-not (Get-Command Get-AdminPowerApp -ErrorAction SilentlyContinue)) {
            Write-Error "Required Power Apps Admin cmdlets (e.g., Get-AdminPowerApp) not found. Please install the Microsoft.PowerApps.Administration.PowerShell module."
            # Fallback to PAC CLI for basic list if cmdlets are missing
            $canvasAppsPac = pac canvas list --json | ConvertFrom-Json
            if ($canvasAppsPac) {
                 Write-Warning "Using PAC CLI for Canvas App list due to missing PowerShell cmdlets. Connector details will be limited."
                 foreach ($appPac in $canvasAppsPac) {
                    $appEntry = [PSCustomObject]@{
                        AppName         = $appPac.name
                        AppId           = $appPac.appId
                        AppType         = "Canvas App (PAC CLI basic)"
                        EnvironmentId   = $appPac.environmentId # Assuming PAC CLI output provides this
                        Owner           = "N/A (PAC CLI basic)"
                        CreatedTime     = "N/A (PAC CLI basic)"
                        LastModifiedTime= "N/A (PAC CLI basic)"
                        Connectors      = @()
                    }
                    $allAppsData.Add($appEntry)
                 }
            }
        } else {
            # Using Power Apps Admin cmdlets for more details
            $adminAppsParams = @{}
            if ($EnvironmentId) { $adminAppsParams.EnvironmentName = $EnvironmentId }

            $canvasApps = Get-AdminPowerApp @adminAppsParams | Where-Object { $_.AppType -eq 'CanvasApp' }

            foreach ($app in $canvasApps) {
                Write-Host "Processing Canvas App: $($app.DisplayName) ($($app.AppName))"
                $connectors = @()
                try {
                    # Get connections for the app
                    # Note: Get-AdminPowerAppConnection is for specific app, Get-AdminConnection is broader
                    $appConnections = Get-AdminPowerAppConnection -AppName $app.AppName -ErrorAction SilentlyContinue
                    if ($appConnections) {
                        foreach ($conn in $appConnections) {
                            # Attempt to get more specific connector details
                            $connectorDetail = Get-AdminConnector -ConnectorName $conn.ConnectorName -ErrorAction SilentlyContinue
                            $connectorDisplayName = if ($connectorDetail) { $connectorDetail.DisplayName } else { $conn.ConnectorName }

                            $connectionInfo = [PSCustomObject]@{
                                Name = $conn.ConnectorName
                                DisplayName = $connectorDisplayName
                                Type = $conn.ApiId # This often gives the type like '/providers/Microsoft.PowerApps/apis/shared_sharepointonline'
                            }
                            $connectors += $connectionInfo
                        }
                    } else {
                        Write-Warning "No direct connections found or error retrieving for app: $($app.DisplayName)"
                    }
                }
                catch {
                    Write-Warning "Could not retrieve connections for Canvas App $($app.DisplayName). Error: $($_.Exception.Message)"
                }

                $appEntry = [PSCustomObject]@{
                    AppName          = $app.DisplayName
                    AppId            = $app.AppName # AppName is the GUID for Get-AdminPowerApp
                    AppType          = "Canvas App"
                    EnvironmentId    = $app.EnvironmentName
                    Owner            = $app.OwnerPrincipalName
                    CreatedTime      = $app.CreatedTime
                    LastModifiedTime = $app.LastModifiedTime
                    Connectors       = $connectors
                }
                $allAppsData.Add($appEntry)
            }
        }
    }
    catch {
        Write-Error "Failed to retrieve Canvas Apps. Error: $($_.Exception.Message)"
    }

    # --- Get Model-Driven Apps ---
    Write-Host "Fetching Model-Driven Apps..."
    try {
        # PAC CLI is generally better for Model-Driven App listing
        $modelDrivenApps = pac modeldriven list --json | ConvertFrom-Json
        if ($modelDrivenApps) {
            foreach ($app in $modelDrivenApps) {
                Write-Host "Processing Model-Driven App: $($app.name) ($($app.uniqueName))"
                # Model-driven apps primarily connect to Dataverse.
                # Specific external connectors are usually via Cloud Flows or Custom Pages with Canvas Apps.
                # Listing those would require deeper inspection or separate flow inventory.
                # For now, we'll list Dataverse as the primary implicit connection.
                $mdaConnectors = @([PSCustomObject]@{
                    Name        = "Dataverse"
                    DisplayName = "Microsoft Dataverse"
                    Type        = "Dataverse" # Internal
                })

                # You could try 'pac modeldriven show --app-id $($app.appId) --json' for more details
                # and parse that if needed, but it doesn't directly list "connectors" in the canvas app sense.
                # For example, sitemap might reveal entities used.

                $appEntry = [PSCustomObject]@{
                    AppName          = $app.name
                    AppId            = $app.appId
                    AppType          = "Model-Driven App"
                    EnvironmentId    = $app.environmentUrl # May need parsing if it's a full URL
                    Owner            = "N/A (Use PAC Admin List for owner if needed)" # PAC modeldriven list doesn't give owner easily
                    CreatedTime      = $app.createdOn # Check exact field name from pac output
                    LastModifiedTime = $app.modifiedOn # Check exact field name from pac output
                    Connectors       = $mdaConnectors
                }
                $allAppsData.Add($appEntry)
            }
        } else {
            Write-Warning "No Model-Driven Apps found or error retrieving them via PAC CLI."
        }
    }
    catch {
        Write-Error "Failed to retrieve Model-Driven Apps. Error: $($_.Exception.Message)"
    }

    Write-Host "Power Apps inventory complete."
    return $allAppsData
}

# Example Usage:
# Make sure you have authenticated using Connect-PowerPlatform from auth_functions.ps1 first.
# $appsInventory = Get-PowerPlatformAppsInventory
# $appsInventory | Format-Table AppName, AppType, Owner, AppId, @{Name="Connectors"; Expression={$_.Connectors.DisplayName -join '; '}}
# $appsInventory | Export-Csv -Path "./powerapps_inventory.csv" -NoTypeInformation

Write-Host "Power Apps inventory functions loaded."
Write-Host "Example: `$apps = Get-PowerPlatformAppsInventory` (after authenticating)"
Write-Host "Then: `$apps | Export-Csv -Path './powerapps_inventory.csv' -NoTypeInformation`"
Write-Host "Ensure Microsoft.PowerApps.Administration.PowerShell and Microsoft.PowerApps.PowerShell.Apps modules are installed."

# Helper to remind about module installation for PowerApps
if (-not (Get-Command Get-AdminPowerApp -ErrorAction SilentlyContinue) -or -not (Get-Command Get-PowerAppConnection -ErrorAction SilentlyContinue)) {
    Write-Warning "IMPORTANT: Power Apps PowerShell cmdlets are not fully available. Please install them by running:"
    Write-Warning "Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -Force"
    Write-Warning "Install-Module Microsoft.PowerApps.PowerShell.Apps -Scope CurrentUser -Force"
}

# Note on EnvironmentId for Get-AdminPowerApp:
# If PAC CLI sets a default environment, Get-AdminPowerApp might use it.
# Otherwise, you might need to get environment details first (e.g., from `pac admin list`) and pass it.
# The `Get-AdminPowerApp` cmdlet without -EnvironmentName lists apps from the default env or the one set by `Set-AdminPowerAppEnvironment`.
# For cross-environment inventory, one would typically loop through environments.
# This script assumes working within the currently selected/default environment context.
# For listing all environments: Get-AdminPowerAppEnvironment
# Then loop: foreach ($env in (Get-AdminPowerAppEnvironment)) { Get-AdminPowerApp -EnvironmentName $env.EnvironmentName }
# This script aims for simplicity for the current environment context.

# A note on PAC CLI JSON output field names:
# I've used placeholders like 'createdOn', 'modifiedOn', 'environmentUrl' for model-driven apps from PAC.
# These need to be verified against actual JSON output of `pac modeldriven list --json`.
# Example `pac canvas list --json` output fields: name, appId, environmentId, etc.
# Example `pac modeldriven list --json` output fields: name, uniqueName, appId, solutionId etc.
# (Actual output may vary slightly with PAC CLI versions).
# The script would need adjustment if actual field names differ.
# For instance, `pac admin list --json` provides `environmentUrl` and `userPrincipalName` for owners of environments.
# `pac admin list-apps --environment <env-id> --json` could be an alternative way to get apps with some admin details.
# This script prioritizes `Get-AdminPowerApp` for Canvas apps for richer details from PS cmdlets.
# If `Get-AdminPowerApp` fails, it falls back to `pac canvas list`.
