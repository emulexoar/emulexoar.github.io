<#
.SYNOPSIS
Functions to inventory Power Automate Cloud Flows and their connectors.

.DESCRIPTION
This script uses Power Apps/Automate Administration PowerShell cmdlets (primarily Get-AdminFlow)
or PAC CLI to list cloud flows and identify their connections. It assumes prior
authentication to the Power Platform and that the Microsoft.PowerApps.Administration.PowerShell
module is installed.
#>

#Requires -Version 5.1

# Ensure the Power Apps admin module is available
# Users should install this: Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -Force

Function Get-PowerAutomateFlowsInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$EnvironmentName # Optional: Specify environment ID/Name if not using default context.
                                # Get-AdminFlow uses EnvironmentName parameter.
    )

    Write-Host "Starting Power Automate Flows inventory..."
    $allFlowsData = [System.Collections.Generic.List[object]]::new()

    try {
        Import-Module Microsoft.PowerApps.Administration.PowerShell -ErrorAction SilentlyContinue
        if (-not (Get-Command Get-AdminFlow -ErrorAction SilentlyContinue)) {
            Write-Error "Required cmdlet Get-AdminFlow not found. Please install the Microsoft.PowerApps.Administration.PowerShell module."
            Write-Warning "Attempting fallback to PAC CLI for flow listing (connector details might be limited without definition parsing)."

            $pacFlowsParams = @("--json")
            if ($EnvironmentName) {
                $pacFlowsParams += "--environment", $EnvironmentName
            }
            $flowsPac = pac flow list @pacFlowsParams | ConvertFrom-Json

            if ($flowsPac) {
                foreach ($flowPac in $flowsPac) {
                    # Basic info from 'pac flow list'. For connectors, 'pac flow show' and parsing definition would be needed.
                    $flowEntry = [PSCustomObject]@{
                        FlowName         = $flowPac.name # Or properties.displayName
                        FlowId           = $flowPac.name # 'name' is often the GUID in PAC output
                        AppType          = "Cloud Flow (PAC CLI basic)"
                        EnvironmentName  = $EnvironmentName # Or derive if possible from pac output
                        Owner            = "N/A (PAC CLI basic - requires Get-AdminFlow or specific parsing)"
                        CreatedTime      = "N/A (PAC CLI basic)"
                        LastModifiedTime = "N/A (PAC CLI basic)"
                        State            = "N/A (PAC CLI basic)"
                        Connectors       = @() # Needs 'pac flow show' and definition parsing
                        IsSolutionFlow   = $flowPac.properties.isSolution # Example, check actual PAC output
                    }
                    $allFlowsData.Add($flowEntry)
                }
            } else {
                Write-Warning "PAC CLI flow list also failed or returned no data."
            }
            return $allFlowsData # Return here as Get-AdminFlow is not available
        }

        # Using Get-AdminFlow for richer details
        $adminFlowsParams = @{}
        if ($EnvironmentName) {
            # Get-AdminFlow expects environment name (GUID)
            $adminFlowsParams.EnvironmentName = $EnvironmentName
        } else {
            # If no environment specified, it may use a default or require it.
            # Consider getting the default environment from PAC auth if needed.
            # $currentPacAuth = pac auth list --json | ConvertFrom-Json | Where-Object {$_.isActive}
            # if ($currentPacAuth) { $adminFlowsParams.EnvironmentName = $currentPacAuth.environmentId } # May need adjustment
            Write-Host "No specific environment provided; Get-AdminFlow will use its default context or might require EnvironmentName."
        }

        # Get-AdminFlow might require explicit environment, or it might list from all environments user has access to
        # Depending on permissions, this could be a lot of data.
        # Add -ApiVersion if specific version is needed, e.g. -ApiVersion '2016-11-01'
        $flows = Get-AdminFlow @adminFlowsParams -ErrorAction SilentlyContinue

        if (-not $flows) {
            Write-Warning "No flows found or error retrieving them with Get-AdminFlow."
            if ($LASTEXITCODE -ne 0 -and $Error.Count -gt 0) {
                Write-Warning "Error details: $($Error[0].ToString())"
            }
             # Try with a common API version if it failed without one
            Write-Host "Retrying Get-AdminFlow with explicit ApiVersion '2016-11-01'"
            $adminFlowsParams.ApiVersion = '2016-11-01'
            $flows = Get-AdminFlow @adminFlowsParams -ErrorAction SilentlyContinue
            if (-not $flows) {
                 Write-Warning "Still no flows found with explicit ApiVersion."
            }
        }


        foreach ($flow in $flows) {
            Write-Host "Processing Flow: $($flow.DisplayName) ($($flow.FlowName))"
            $connectors = @()
            try {
                # Connectors are typically in $flow.Internal.properties.connectionReferences
                # This structure can vary based on flow type (e.g. Solution-aware vs non-solution aware)
                $connectionReferences = $null
                if ($flow.Internal.properties.connectionReferences) {
                    $connectionReferences = $flow.Internal.properties.connectionReferences
                } elseif ($flow.properties.connectionReferences) { # Some structures might have it here
                     $connectionReferences = $flow.properties.connectionReferences
                }


                if ($connectionReferences) {
                    foreach ($connRef in $connectionReferences) {
                        $connectorDisplayName = $connRef.displayName
                        $connectionApiId = $connRef.apiId
                        $connectionType = $connRef.connectionApiId # Sometimes used

                        if (-not $connectorDisplayName -and $connRef.connectionName) {
                            # Fallback or attempt to get more details if only connectionName (GUID) is present
                            # This might require another call like Get-AdminConnection -ConnectionName $connRef.connectionName -ConnectorName $connRef.id (or similar)
                            # For simplicity, we'll use what's available directly.
                            $connectorDisplayName = $connRef.id.Split('/')[-1] # Heuristic for connector type from ID
                        }

                        # Try to get a more friendly name from the API ID
                        if ($connectionApiId -match "/providers/Microsoft.PowerApps/apis/(.*)") {
                            $friendlyName = $Matches[1]
                            if ($friendlyName -eq 'shared_logicflows') { $friendlyName = 'Child Flow'} # Example refinement
                        } else {
                            $friendlyName = $connectionApiId
                        }


                        $connectorEntry = [PSCustomObject]@{
                            Name        = $connRef.id # Or $connRef.connectionName
                            DisplayName = $connectorDisplayName # This is often the actual connection's name
                            ApiId       = $connectionApiId # e.g., /providers/Microsoft.PowerApps/apis/shared_sharepointonline
                            Type        = $friendlyName # Extracted type
                        }
                        $connectors += $connectorEntry
                    }
                } else {
                    Write-Warning "No connection references found directly in flow properties for: $($flow.DisplayName)"
                }
            }
            catch {
                Write-Warning "Could not parse connections for Flow $($flow.DisplayName). Error: $($_.Exception.Message)"
            }

            $flowEntry = [PSCustomObject]@{
                FlowName         = $flow.DisplayName
                FlowId           = $flow.FlowName # This is the GUID
                AppType          = "Cloud Flow"
                EnvironmentName  = $flow.EnvironmentName # Environment GUID
                Owner            = $flow.CreatedBy.UserPrincipalName # Or $flow.Internal.properties.creator.userPrincipalName
                CreatedTime      = $flow.CreatedTime
                LastModifiedTime = $flow.LastModifiedTime
                State            = $flow.State # e.g., Started, Stopped
                Connectors       = $connectors
                IsSolutionFlow   = if($flow.Internal.properties.environmentWorkflowSolutionId){ $true } else { $false } # Heuristic
            }
            $allFlowsData.Add($flowEntry)
        }
    }
    catch {
        Write-Error "Failed to retrieve Power Automate Flows. Error: $($_.Exception.Message)"
    }

    Write-Host "Power Automate Flows inventory complete."
    return $allFlowsData
}

# Example Usage:
# Make sure you have authenticated using Connect-PowerPlatform from auth_functions.ps1 first.
# And ensure Microsoft.PowerApps.Administration.PowerShell module is installed.
# $flowsInventory = Get-PowerAutomateFlowsInventory #-EnvironmentName "your-environment-guid"
# $flowsInventory | Format-Table FlowName, Owner, State, @{Name="Connectors"; Expression={$_.Connectors.DisplayName -join '; '}}
# $flowsInventory | Export-Csv -Path "./powerautomate_flows_inventory.csv" -NoTypeInformation

Write-Host "Power Automate Flows inventory functions loaded."
Write-Host "Example: `$flows = Get-PowerAutomateFlowsInventory` (after authenticating)"
Write-Host "Then: `$flows | Export-Csv -Path './powerautomate_flows_inventory.csv' -NoTypeInformation`"
Write-Host "Ensure Microsoft.PowerApps.Administration.PowerShell module is installed (Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -Force)."

# Reminder for module installation
if (-not (Get-Command Get-AdminFlow -ErrorAction SilentlyContinue)) {
    Write-Warning "IMPORTANT: Get-AdminFlow cmdlet not found. Please install the required module by running:"
    Write-Warning "Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -Force"
}

# Note on Get-AdminFlow and Environments:
# Get-AdminFlow can be tricky with environments.
# - If no -EnvironmentName is specified, its behavior depends on the version and context.
#   It might list from a 'default' environment or all accessible environments.
# - It's often best to explicitly provide the -EnvironmentName (which is the GUID of the environment).
# - To get all environments first, one might use:
#   `$environments = Get-AdminPowerAppEnvironment`
#   `foreach ($env in $environments) { Get-PowerAutomateFlowsInventory -EnvironmentName $env.EnvironmentName }`
# This script version aims for simplicity, focusing on current/specified environment.
# The user might need to adapt it for multi-environment scanning.
# The 'Owner' field might also vary; $flow.CreatedBy.UserPrincipalName is common.
# Check actual object properties from Get-AdminFlow if fields are missing.
# $flow.Internal.properties can be a rich source but also complex.
# Connector parsing is based on common structures for `connectionReferences`.
# If a flow uses, for example, HTTP direct calls without a "connector" per se, that's harder to inventory this way.
# This focuses on declared connection references.
