<#
.SYNOPSIS
Functions to inventory Power BI workspaces, reports, datasets, and their data sources.

.DESCRIPTION
This script uses the MicrosoftPowerBIMgmt PowerShell module to connect to Power BI
service and gather information about artifacts and their underlying data connections.
It assumes prior authentication using Connect-PowerBIServiceAccount.
#>

#Requires -Version 5.1

# Ensure the Power BI module is available
# Users should install this: Install-Module MicrosoftPowerBIMgmt -Scope CurrentUser -Force

Function Get-PowerBIInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$IncludePersonalWorkspaces,

        [Parameter(Mandatory=$false)]
        [string[]]$SpecificWorkspaceNames, # Allow specifying specific workspace names to scan

        [Parameter(Mandatory=$false)]
        [switch]$ScanAllOrgWorkspaces # Requires Admin rights to list all workspaces
    )

    Write-Host "Starting Power BI inventory..."
    $allPowerBiData = [System.Collections.Generic.List[object]]::new()

    try {
        Import-Module MicrosoftPowerBIMgmt -ErrorAction SilentlyContinue
        Import-Module MicrosoftPowerBIMgmt.Workspaces -ErrorAction SilentlyContinue # For Get-PowerBIWorkspace
        Import-Module MicrosoftPowerBIMgmt.Reports -ErrorAction SilentlyContinue   # For Get-PowerBIReport
        Import-Module MicrosoftPowerBIMgmt.Datasets -ErrorAction SilentlyContinue  # For Get-PowerBIDataset, Get-PowerBIDatasource
        Import-Module MicrosoftPowerBIMgmt.Gateways -ErrorAction SilentlyContinue # For Get-PowerBIGateway

        if (-not (Get-Command Get-PowerBIWorkspace -ErrorAction SilentlyContinue)) {
            Write-Error "Required Power BI cmdlets not found. Please install the MicrosoftPowerBIMgmt module and its sub-modules (e.g., MicrosoftPowerBIMgmt.Workspaces)."
            return $allPowerBiData
        }

        $workspacesToScan = @()
        if ($ScanAllOrgWorkspaces) {
            Write-Host "Attempting to fetch all organization workspaces (requires Power BI Admin role)..."
            try {
                $workspacesToScan = Get-PowerBIWorkspace -Scope Organization -ErrorAction Stop
            } catch {
                Write-Warning "Failed to get organization workspaces. Error: $($_.Exception.Message). Ensure you have Power BI Admin permissions. Falling back to individual scope."
                $workspacesToScan = Get-PowerBIWorkspace -Scope Individual -ErrorAction SilentlyContinue
            }
        } elseif ($SpecificWorkspaceNames) {
            Write-Host "Fetching specified workspaces..."
            foreach ($wsName in $SpecificWorkspaceNames) {
                try {
                    $foundWs = Get-PowerBIWorkspace -Name $wsName -ErrorAction SilentlyContinue # May need -Scope Individual if not admin
                    if ($foundWs) { $workspacesToScan += $foundWs } else { Write-Warning "Workspace '$wsName' not found or not accessible."}
                } catch { Write-Warning "Error fetching workspace '$wsName': $($_.Exception.Message)" }
            }
        }
        else {
            Write-Host "Fetching workspaces accessible by the current user (excluding personal workspaces by default)..."
            $workspacesToScan = Get-PowerBIWorkspace -Scope Individual -ErrorAction SilentlyContinue # Lists workspaces user is member of
        }

        if (-not $IncludePersonalWorkspaces) {
            $workspacesToScan = $workspacesToScan | Where-Object { $_.Type -ne "PersonalGroup" }
        }

        if (-not $workspacesToScan) {
            Write-Warning "No workspaces found or accessible to scan based on the provided parameters."
            return $allPowerBiData
        }

        Write-Host "Found $($workspacesToScan.Count) workspaces to scan."

        foreach ($workspace in $workspacesToScan) {
            Write-Host "Processing Workspace: $($workspace.Name) (ID: $($workspace.Id))"

            # Get Datasets and their Data Sources
            $datasets = Get-PowerBIDataset -WorkspaceId $workspace.Id -ErrorAction SilentlyContinue
            foreach ($dataset in $datasets) {
                Write-Host "  Processing Dataset: $($dataset.Name) (ID: $($dataset.Id))"
                $dataSourcesOutput = @()
                try {
                    $dataSources = Get-PowerBIDatasource -DatasetId $dataset.Id -WorkspaceId $workspace.Id -ErrorAction SilentlyContinue
                    if ($dataSources) {
                        foreach ($ds in $dataSources) {
                            $connectionDetails = $ds.ConnectionDetails | ConvertTo-Json -Depth 3 -Compress # Get all details as JSON string
                            $dataSourceEntry = [PSCustomObject]@{
                                DataSourceName    = $ds.Name # This might be the table name for some sources
                                DataSourceType    = $ds.DatasourceType
                                ConnectionString  = $ds.ConnectionString
                                GatewayId         = $ds.GatewayId
                                ConnectionDetails = $connectionDetails # Raw details
                            }
                            $dataSourcesOutput += $dataSourceEntry
                        }
                    } else {
                         Write-Warning "    No data sources returned for dataset: $($dataset.Name)"
                    }
                }
                catch {
                    Write-Warning "    Error retrieving data sources for dataset $($dataset.Name): $($_.Exception.Message)"
                }

                $datasetItem = [PSCustomObject]@{
                    WorkspaceName = $workspace.Name
                    WorkspaceId   = $workspace.Id
                    ArtifactType  = "Dataset"
                    ArtifactName  = $dataset.Name
                    ArtifactId    = $dataset.Id
                    CreatedDate   = $dataset.CreatedDate
                    ConfiguredBy  = $dataset.ConfiguredBy # Might be blank
                    DataSources   = $dataSourcesOutput
                }
                $allPowerBiData.Add($datasetItem)
            }

            # Get Reports
            $reports = Get-PowerBIReport -WorkspaceId $workspace.Id -ErrorAction SilentlyContinue
            foreach ($report in $reports) {
                Write-Host "  Processing Report: $($report.Name) (ID: $($report.Id))"
                $reportItem = [PSCustomObject]@{
                    WorkspaceName = $workspace.Name
                    WorkspaceId   = $workspace.Id
                    ArtifactType  = "Report"
                    ArtifactName  = $report.Name
                    ArtifactId    = $report.Id
                    DatasetId     = $report.DatasetId # Link to the dataset
                    CreatedDate   = $report.CreatedDateTime
                    ModifiedDate  = $report.ModifiedDateTime
                    ReportType    = $report.ReportType # e.g. PowerBIReport, PaginatedReport
                    EmbedUrl      = $report.EmbedUrl
                }
                $allPowerBiData.Add($reportItem)
            }
        }
    }
    catch {
        Write-Error "Failed during Power BI inventory. Error: $($_.Exception.Message)"
    }

    Write-Host "Power BI inventory complete."
    return $allPowerBiData
}

# Example Usage:
# Make sure you have authenticated using Connect-PowerBIServiceAccount from auth_functions.ps1 first.
# And ensure MicrosoftPowerBIMgmt module and its submodules are installed.

# Example 1: Scan workspaces user is a member of (excluding personal)
# $pbiInventory = Get-PowerBIInventory
# $pbiInventory | Export-Csv -Path "./powerbi_inventory.csv" -NoTypeInformation

# Example 2: Scan specific workspaces
# $pbiInventorySpecific = Get-PowerBIInventory -SpecificWorkspaceNames "Sales Analytics", "Marketing Reports"
# $pbiInventorySpecific | Export-Csv -Path "./powerbi_specific_inventory.csv" -NoTypeInformation

# Example 3: Scan all organization workspaces (requires Power BI Admin) and include personal workspaces
# $pbiInventoryAllOrg = Get-PowerBIInventory -ScanAllOrgWorkspaces -IncludePersonalWorkspaces
# $pbiInventoryAllOrg | Export-Csv -Path "./powerbi_all_org_inventory.csv" -NoTypeInformation

# To view dataset sources easily:
# $datasetsWithSources = $pbiInventory | Where-Object {$_.ArtifactType -eq "Dataset" -and $_.DataSources}
# $datasetsWithSources | Select-Object WorkspaceName, ArtifactName, @{N="DataSources"; E={$_.DataSources | Select-Object DataSourceType, ConnectionString, GatewayId | ConvertTo-Json -Compress}} | Format-Table -Wrap

Write-Host "Power BI inventory functions loaded."
Write-Host "Example: `$pbiInv = Get-PowerBIInventory` (after authenticating with Connect-PowerBIServiceAccount)"
Write-Host "Then: `$pbiInv | Export-Csv -Path './powerbi_inventory.csv' -NoTypeInformation`"
Write-Host "Ensure MicrosoftPowerBIMgmt module and its sub-modules are installed."

# Reminder for module installation
if (-not (Get-Command Get-PowerBIWorkspace -ErrorAction SilentlyContinue)) {
    Write-Warning "IMPORTANT: Power BI cmdlets like Get-PowerBIWorkspace not found. Please install/import the required modules by running:"
    Write-Warning "Install-Module MicrosoftPowerBIMgmt -Scope CurrentUser -Force"
    Write-Warning "Then, you might need to explicitly import sub-modules if they don't auto-load, e.g.:"
    Write-Warning "Import-Module MicrosoftPowerBIMgmt.Workspaces, MicrosoftPowerBIMgmt.Reports, MicrosoftPowerBIMgmt.Datasets, MicrosoftPowerBIMgmt.Gateways"
}
