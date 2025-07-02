<#
.SYNOPSIS
Functions to inventory CoPilot Studio (Power Virtual Agents) bots.

.DESCRIPTION
This script uses Power Platform Administration PowerShell cmdlets (primarily Get-AdminPowerAppBot)
and potentially PAC CLI to list CoPilot Studio bots and gather their details.
It assumes prior authentication to the Power Platform and that the
Microsoft.PowerApps.Administration.PowerShell module is installed.
#>

#Requires -Version 5.1

# Ensure the Power Apps admin module is available
# Users should install this: Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -Force

Function Get-CoPilotStudioBotsInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$EnvironmentName # Optional: Specify environment ID/Name (GUID)
    )

    Write-Host "Starting CoPilot Studio (PVA) Bots inventory..."
    $allBotsData = [System.Collections.Generic.List[object]]::new()

    try {
        Import-Module Microsoft.PowerApps.Administration.PowerShell -ErrorAction SilentlyContinue
        if (-not (Get-Command Get-AdminPowerAppBot -ErrorAction SilentlyContinue)) {
            Write-Error "Required cmdlet Get-AdminPowerAppBot not found. Please install the Microsoft.PowerApps.Administration.PowerShell module."
            Write-Warning "Attempting fallback to PAC CLI for PVA bot listing (details might be limited)."

            $pacPvaParams = @("pva", "list", "--json")
            if ($EnvironmentName) {
                # PAC pva list might not take --environment directly, it might use the active pac environment.
                # Or it might have a specific parameter. Let's assume it uses active env for now or user sets it.
                # Check `pac pva list --help` for exact params.
                # For now, this script will assume `pac pva list` uses the environment set by `pac auth select`.
                Write-Host "PAC pva list will use the currently selected PAC environment. Ensure it's set correctly if you need a specific one."
            }

            # Execute pac pva list. Ensure pac is in PATH.
            $rawPacPvaOutput = Invoke-Expression "pac $($pacPvaParams -join ' ')"
            $botsPac = $rawPacPvaOutput | ConvertFrom-Json -ErrorAction SilentlyContinue

            if ($botsPac) {
                foreach ($botPac in $botsPac) { # Iterate through the actual items if $botsPac is an array
                    # The structure of 'pac pva list --json' output needs to be known.
                    # Assuming fields like: id, name, environmentId, createdOn, modifiedOn
                    # This is a guess, actual field names from `pac pva list --json` must be verified.
                    $botEntry = [PSCustomObject]@{
                        BotName          = $botPac.name # Or $botPac.displayName, $botPac.schemaName
                        BotId            = $botPac.id   # Or $botPac.botId
                        AppType          = "CoPilot Studio Bot (PAC CLI basic)"
                        EnvironmentId    = $botPac.environmentId # Or derive from context
                        Owner            = "N/A (PAC CLI basic)"
                        CreatedTime      = $botPac.createdOn
                        LastModifiedTime = $botPac.modifiedOn
                        State            = $botPac.status # e.g. published
                        Connectors       = @() # Requires 'pac pva show --id <id> --json' and parsing definition
                        CalledFlows      = @() # Requires parsing definition
                    }
                    $allBotsData.Add($botEntry)
                }
            } else {
                Write-Warning "PAC CLI 'pva list' failed or returned no data. Raw output: $rawPacPvaOutput"
            }
            return $allBotsData # Return here as Get-AdminPowerAppBot is not available
        }

        # Using Get-AdminPowerAppBot for richer details
        $adminBotParams = @{}
        if ($EnvironmentName) {
            $adminBotParams.EnvironmentName = $EnvironmentName
        } else {
            Write-Host "No specific environment provided for Get-AdminPowerAppBot; it will use its default context or might require EnvironmentName."
        }

        $bots = Get-AdminPowerAppBot @adminBotParams -ErrorAction SilentlyContinue

        if (-not $bots) {
            Write-Warning "No CoPilot Studio bots found or error retrieving them with Get-AdminPowerAppBot."
            if ($LASTEXITCODE -ne 0 -and $Error.Count -gt 0) {
                Write-Warning "Error details: $($Error[0].ToString())"
            }
        }

        foreach ($bot in $bots) {
            Write-Host "Processing CoPilot Studio Bot: $($bot.DisplayName) ($($bot.BotId))"

            $connectors = @() # Connections used directly by the bot itself (e.g. Bot Framework Skills)
            $calledFlows = @() # Power Automate flows called by the bot

            # Details about connections and called flows are not directly in Get-AdminPowerAppBot output.
            # This typically requires inspecting the bot's definition.
            # 'pac pva show --id $($bot.BotId) --environment $($bot.EnvironmentName) --json' could get the definition.
            # Then, parse the JSON for flow IDs (skills) or other connector info.
            # This parsing can be complex. For now, we'll note this limitation.

            Write-Host "INFO: For Bot '$($bot.DisplayName)', detailed connector and called flow information requires parsing the bot definition (e.g., using 'pac pva show' and processing its JSON output)."
            # Example of what might be found in a definition (conceptual):
            # - Flow IDs used as skills.
            # - References to QnA Maker knowledge bases.
            # - Configuration for connected Bot Framework Skills.

            # Placeholder for future enhancement:
            # try {
            #     $botDefinitionJson = pac pva show --id $bot.BotId --environment $bot.EnvironmentName --json | ConvertFrom-Json
            #     # Parse $botDefinitionJson for flow IDs, skill manifest URLs, etc.
            #     # Add them to $calledFlows or $connectors arrays.
            #     # e.g., if $botDefinitionJson.skills contains flow IDs:
            #     # foreach ($skill in $botDefinitionJson.skills) { if ($skill.type -eq 'PowerAutomateFlow') { $calledFlows += $skill.id } }
            # } catch { Write-Warning "Could not retrieve or parse definition for bot $($bot.DisplayName)"}


            $botEntry = [PSCustomObject]@{
                BotName          = $bot.DisplayName
                BotId            = $bot.BotId
                AppType          = "CoPilot Studio Bot"
                EnvironmentId    = $bot.EnvironmentName # Environment GUID
                Owner            = $bot.OwnerPrincipalName # Or other owner fields if available
                CreatedTime      = $bot.CreatedTime
                LastModifiedTime = $bot.LastModifiedTime
                State            = $bot.Status # e.g., Published, NotPublished (check actual values)
                Connectors       = $connectors # Would be populated by definition parsing
                CalledFlows      = $calledFlows # Would be populated by definition parsing
            }
            $allBotsData.Add($botEntry)
        }
    }
    catch {
        Write-Error "Failed to retrieve CoPilot Studio Bots. Error: $($_.Exception.Message)"
    }

    Write-Host "CoPilot Studio (PVA) Bots inventory complete."
    return $allBotsData
}

# Example Usage:
# Make sure you have authenticated using Connect-PowerPlatform from auth_functions.ps1 first.
# And ensure Microsoft.PowerApps.Administration.PowerShell module is installed.
# $pvaBotsInventory = Get-CoPilotStudioBotsInventory #-EnvironmentName "your-environment-guid"
# $pvaBotsInventory | Format-Table BotName, Owner, State, EnvironmentId
# $pvaBotsInventory | Export-Csv -Path "./copilot_studio_bots_inventory.csv" -NoTypeInformation

Write-Host "CoPilot Studio (PVA) Bots inventory functions loaded."
Write-Host "Example: `$bots = Get-CoPilotStudioBotsInventory` (after authenticating)"
Write-Host "Then: `$bots | Export-Csv -Path './copilot_studio_bots_inventory.csv' -NoTypeInformation`"
Write-Host "Ensure Microsoft.PowerApps.Administration.PowerShell module is installed."
Write-Host "Note: Detailed connector/flow usage within bots currently requires manual parsing of bot definitions (e.g., via 'pac pva show')."

# Reminder for module installation
if (-not (Get-Command Get-AdminPowerAppBot -ErrorAction SilentlyContinue)) {
    Write-Warning "IMPORTANT: Get-AdminPowerAppBot cmdlet not found. Please install the required module by running:"
    Write-Warning "Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -Force"
}
