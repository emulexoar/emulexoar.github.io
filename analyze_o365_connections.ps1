<#
.SYNOPSIS
Functions to analyze previously collected inventory data to identify and highlight
SharePoint and other Office 365 connections.

.DESCRIPTION
This script takes arrays of inventory objects (from Power Apps, Power Automate, etc.)
as input and filters/flags items that use SharePoint or other O365 connectors.
It does not make new API calls but processes existing data.
#>

#Requires -Version 5.1

Function Get-O365ConnectedItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$PowerAppsInventory,

        [Parameter(Mandatory=$true)]
        [array]$PowerAutomateInventory,

        [Parameter(Mandatory=$false)] # Bots might call flows, so their 'CalledFlows' need checking
        [array]$CoPilotStudioBotsInventory,

        [Parameter(Mandatory=$true)] # Power BI data sources
        [array]$PowerBIInventory
        # Power Pages are primarily Dataverse; specific O365 via embedded apps/flows needs correlation.
    )

    Write-Host "Analyzing inventory data for SharePoint and O365 connections..."
    $o365ConnectedItems = [System.Collections.Generic.List[object]]::new()

    # Define O365 connector identifiers (keywords/ApiIds)
    # ApiId is often like '/providers/Microsoft.PowerApps/apis/shared_sharepointonline'
    # Type property in our custom objects often holds the 'shared_sharepointonline' part
    $sharePointIdentifiers = @("shared_sharepointonline", "sharepoint")
    $outlookIdentifiers = @("shared_office365", "shared_outlook", "office 365 outlook", "exchange") # shared_office365 is Office 365 Outlook
    $teamsIdentifiers = @("shared_teams", "microsoft teams")
    $plannerIdentifiers = @("shared_planner", "microsoft planner")
    $oneDriveIdentifiers = @("shared_onedriveforbusiness", "onedrive")
    $o365UsersIdentifiers = @("shared_office365users", "office 365 users") # Azure AD connector is separate but related
    $azureAdIdentifiers = @("shared_azuread", "azure ad") # For user/group type operations
    $excelIdentifiers = @("shared_excelonlinebusiness", "shared_excel", "excel online")

    $allO365Identifiers = $sharePointIdentifiers + $outlookIdentifiers + $teamsIdentifiers + $plannerIdentifiers + $oneDriveIdentifiers + $o365UsersIdentifiers + $azureAdIdentifiers + $excelIdentifiers

    # Helper function to check a single connector
    function Test-IsO365Connector {
        param ($connector)

        $connectorType = ""
        if ($connector.PSObject.Properties.Map{$_.Name} -contains 'Type') {
            $connectorType = $connector.Type.ToLower()
        }
        $connectorApiId = ""
        if ($connector.PSObject.Properties.Map{$_.Name} -contains 'ApiId') {
            $connectorApiId = $connector.ApiId.ToLower()
        }
        $connectorDisplayName = ""
        if ($connector.PSObject.Properties.Map{$_.Name} -contains 'DisplayName') {
            $connectorDisplayName = $connector.DisplayName.ToLower()
        }

        foreach ($id in $allO365Identifiers) {
            if (($connectorType -like "*$id*") -or `
                ($connectorApiId -like "*$id*") -or `
                ($connectorDisplayName -like "*$id*")) {

                # Determine specific O365 service
                $service = "Unknown O365"
                if ($sharePointIdentifiers | ForEach-Object {$id -eq $_}) {$service = "SharePoint"}
                elseif ($outlookIdentifiers | ForEach-Object {$id -eq $_}) {$service = "Outlook/Exchange"}
                elseif ($teamsIdentifiers | ForEach-Object {$id -eq $_}) {$service = "Microsoft Teams"}
                elseif ($plannerIdentifiers | ForEach-Object {$id -eq $_}) {$service = "Microsoft Planner"}
                elseif ($oneDriveIdentifiers | ForEach-Object {$id -eq $_}) {$service = "OneDrive"}
                elseif ($o365UsersIdentifiers | ForEach-Object {$id -eq $_}) {$service = "Office 365 Users"}
                elseif ($azureAdIdentifiers | ForEach-Object {$id -eq $_}) {$service = "Azure AD"}
                elseif ($excelIdentifiers | ForEach-Object {$id -eq $_}) {$service = "Excel Online"}

                return @{IsO365 = $true; Service = $service; MatchedId = $id; ConnectorDisplayName = $connector.DisplayName; ConnectorType = $connectorType }
            }
        }
        return @{IsO365 = $false}
    }

    # Process Power Apps
    Write-Host "Processing Power Apps inventory..."
    foreach ($app in $PowerAppsInventory) {
        $foundO365Connectors = [System.Collections.Generic.List[object]]::new()
        if ($app.Connectors) {
            foreach ($connector in $app.Connectors) {
                $testResult = Test-IsO365Connector -connector $connector
                if ($testResult.IsO365) {
                    $foundO365Connectors.Add($testResult)
                }
            }
        }
        if ($foundO365Connectors.Count -gt 0) {
            $app | Add-Member -MemberType NoteProperty -Name "O365ConnectionsDetail" -Value $foundO365Connectors -Force
            $o365ConnectedItems.Add($app)
        }
    }

    # Process Power Automate Flows
    Write-Host "Processing Power Automate Flows inventory..."
    foreach ($flow in $PowerAutomateInventory) {
        $foundO365Connectors = [System.Collections.Generic.List[object]]::new()
        if ($flow.Connectors) {
            foreach ($connector in $flow.Connectors) {
                $testResult = Test-IsO365Connector -connector $connector
                if ($testResult.IsO365) {
                    $foundO365Connectors.Add($testResult)
                }
            }
        }
        if ($foundO365Connectors.Count -gt 0) {
            $flow | Add-Member -MemberType NoteProperty -Name "O365ConnectionsDetail" -Value $foundO365Connectors -Force
            $o365ConnectedItems.Add($flow)
        }
    }

    # Process CoPilot Studio Bots (by checking their called flows)
    Write-Host "Processing CoPilot Studio Bots inventory (via their called flows)..."
    if ($CoPilotStudioBotsInventory) {
        foreach ($bot in $CoPilotStudioBotsInventory) {
            $botO365Connections = [System.Collections.Generic.List[object]]::new()
            if ($bot.CalledFlows) { # Assuming CalledFlows contains Flow IDs
                foreach ($calledFlowId in $bot.CalledFlows) {
                    $linkedFlow = $PowerAutomateInventory | Where-Object { $_.FlowId -eq $calledFlowId }
                    if ($linkedFlow -and $linkedFlow.O365ConnectionsDetail) { # Check if already processed and marked
                        $linkedFlow.O365ConnectionsDetail | ForEach-Object { $botO365Connections.Add($_) }
                    }
                }
            }
            if ($botO365Connections.Count -gt 0) {
                $bot | Add-Member -MemberType NoteProperty -Name "O365ConnectionsDetail" -Value ($botO365Connections | Select-Object * -Unique) -Force # Add unique connections
                $o365ConnectedItems.Add($bot)
            }
        }
    }

    # Process Power BI Inventory (Datasets)
    Write-Host "Processing Power BI inventory..."
    foreach ($item in $PowerBIInventory) {
        if ($item.ArtifactType -eq "Dataset" -and $item.DataSources) {
            $foundO365DataSources = [System.Collections.Generic.List[object]]::new()
            foreach ($dataSource in $item.DataSources) {
                # Power BI data source types are different, e.g., "SharePointList", "SharePointFolder", "Exchange", "ActiveDirectory"
                $dsTypeLower = $dataSource.DataSourceType.ToLower()
                $dsConnStringLower = $dataSource.ConnectionString.ToLower() # Connection string might hold clues too

                $service = $null
                if ($dsTypeLower -like "*sharepoint*") { $service = "SharePoint" }
                elseif ($dsTypeLower -like "*exchange*" -or $dsTypeLower -like "*office365*") { $service = "Outlook/Exchange" } # Office365 includes mail, calendar, contacts
                elseif ($dsTypeLower -like "*activedirectory*" -or $dsTypeLower -like "*azureactivedirectory*") { $service = "Azure AD" }
                elseif ($dsTypeLower -like "*excel*" -and ($dsConnStringLower -like "*sharepoint*" -or $dsConnStringLower -like "*onedrive*")) { $service = "Excel Online (via SharePoint/OneDrive)"}
                # Add more Power BI specific data source types as needed (e.g. OData feed from SP)

                if ($service) {
                    $foundO365DataSources.Add(@{
                        IsO365 = $true
                        Service = $service
                        DataSourceType = $dataSource.DataSourceType
                        ConnectionString = $dataSource.ConnectionString
                    })
                }
            }
            if ($foundO365DataSources.Count -gt 0) {
                $item | Add-Member -MemberType NoteProperty -Name "O365ConnectionsDetail" -Value $foundO365DataSources -Force
                $o365ConnectedItems.Add($item)
            }
        }
    }

    Write-Host "Analysis complete. Found $($o365ConnectedItems.Count) items with direct SharePoint/O365 connections or data sources."
    return $o365ConnectedItems
}

# Example Usage:
# Assume $powerApps, $powerAutomateFlows, $pvaBots, $pbiAssets are populated from previous scripts.
# $allInventoriesLoaded = $true # Set this after loading all .ps1 files and running their functions.
# if ($allInventoriesLoaded) {
#   . ./inventory_powerapps.ps1
#   . ./inventory_powerautomate.ps1
#   . ./inventory_copilotstudio.ps1
#   . ./inventory_powerbi.ps1
#
#   # Authenticate first (using functions from auth_functions.ps1)
#   # Connect-PowerPlatform -EnvironmentUrl "..."
#   # Connect-PowerBIServiceAccount
#   # ... etc.
#
#   Write-Host "Gathering Power Apps inventory..."
#   $powerAppsInventory = Get-PowerPlatformAppsInventory
#   Write-Host "Gathering Power Automate inventory..."
#   $powerAutomateInventory = Get-PowerAutomateFlowsInventory
#   Write-Host "Gathering CoPilot Studio Bots inventory..."
#   $coPilotBotsInventory = Get-CoPilotStudioBotsInventory
#   Write-Host "Gathering Power BI inventory..."
#   $powerBIInventory = Get-PowerBIInventory
#
#   $o365ImpactedItems = Get-O365ConnectedItems -PowerAppsInventory $powerAppsInventory `
#                                             -PowerAutomateInventory $powerAutomateInventory `
#                                             -CoPilotStudioBotsInventory $coPilotBotsInventory `
#                                             -PowerBIInventory $powerBIInventory
#
#   Write-Host "`n--- Items with SharePoint/O365 Connections ---"
#   $o365ImpactedItems | Format-Table AppName, FlowName, BotName, ArtifactName, AppType, WorkspaceName, @{N="O365 Services";E={($_.O365ConnectionsDetail.Service | Select-Object -Unique) -join '; '}} -AutoSize
#
#   $o365ImpactedItems | Export-Csv -Path "./o365_connected_inventory.csv" -NoTypeInformation
# } else {
#   Write-Warning "Run the individual inventory scripts first to populate the data."
# }

Write-Host "O365 Connection Analysis functions loaded."
Write-Host "Use Get-O365ConnectedItems with previously gathered inventory data."
Write-Host "Example: `$o365Items = Get-O365ConnectedItems -PowerAppsInventory \$apps -PowerAutomateInventory \$flows -PowerBIInventory \$pbi`"
Write-Host "The output items will have an added 'O365ConnectionsDetail' property."
