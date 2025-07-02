<#
.SYNOPSIS
Functions to inventory Power Pages sites.

.DESCRIPTION
This script uses PAC CLI (pac power-pages list) to list Power Pages sites.
Power Pages are primarily connected to Dataverse. Other integrations (embedded apps, flows)
would need to be correlated with other inventory parts.
It assumes prior authentication to the Power Platform (via PAC CLI).
#>

#Requires -Version 5.1

# PAC CLI should be installed and authenticated.

Function Get-PowerPagesSitesInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$EnvironmentId # Optional: PAC CLI usually operates on the currently selected environment.
                               # Explicit environment targeting with `pac power-pages list` might need --environment parameter.
    )

    Write-Host "Starting Power Pages sites inventory..."
    $allSitesData = [System.Collections.Generic.List[object]]::new()

    try {
        # Ensure pac command is available
        if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
            Write-Error "PAC CLI command (pac) not found. Please ensure it is installed and in your PATH."
            return $allSitesData
        }

        $pacPpParams = @("power-pages", "list", "--json")

        # The 'pac power-pages list' command typically uses the environment selected via 'pac auth select'.
        # If an --environment parameter is supported by this specific command, it could be added here.
        # For now, we assume the user has selected the correct environment in PAC CLI.
        if ($EnvironmentId) {
            Write-Warning "The -EnvironmentId parameter is provided, but 'pac power-pages list' typically uses the environment set by 'pac auth select'. Ensure the correct environment is active in PAC CLI. If 'pac power-pages list' supports an --environment flag, this script may need updating."
            # Example if --environment was supported: $pacPpParams += "--environment", $EnvironmentId
        }

        Write-Host "Executing: pac $($pacPpParams -join ' ')"
        $rawPacPpOutput = Invoke-Expression ($pacPpParams -join ' ') # Could also use & $PacPath $PacPpParams
        $sitesPac = $rawPacPpOutput | ConvertFrom-Json -ErrorAction SilentlyContinue

        if ($LASTEXITCODE -ne 0 -or -not $sitesPac) {
            Write-Warning "PAC CLI 'power-pages list' command failed or returned no/invalid JSON data."
            Write-Warning "Raw output: $rawPacPpOutput"
            # Attempt with older 'paportal list' as a fallback for environments that might not have migrated fully
            # or if the user is on an older PAC CLI version.
            Write-Host "Attempting fallback with 'pac paportal list --json'..."
            $pacPaPortalParams = @("paportal", "list", "--json")
            # if ($EnvironmentId) { $pacPaPortalParams += "--environment", $EnvironmentId } # Check if supported

            $rawPacPaPortalOutput = Invoke-Expression ($pacPaPortalParams -join ' ')
            $sitesPac = $rawPacPaPortalOutput | ConvertFrom-Json -ErrorAction SilentlyContinue

            if ($LASTEXITCODE -ne 0 -or -not $sitesPac) {
                Write-Warning "PAC CLI 'paportal list' fallback also failed or returned no/invalid JSON data."
                Write-Warning "Raw output for paportal: $rawPacPaPortalOutput"
                return $allSitesData
            } else {
                Write-Host "Successfully listed sites using 'pac paportal list' (fallback)."
            }
        }

        # The structure of 'pac power-pages list --json' output needs to be known.
        # Common fields might include: websiteId, name, portalUrl, stateCode, createdOn, modifiedOn
        # This is a guess, actual field names must be verified from PAC CLI output.
        # The output of `pac power-pages list` is often an array of objects.
        # If $sitesPac is a single object with a property containing the array (e.g., $sitesPac.value), adjust accordingly.

        $sitesToProcess = $sitesPac
        if ($sitesPac -is [pscustomobject] -and $sitesPac.PSObject.Properties.Name -contains "value") {
            # Handle cases where JSON is like { "value": [...] }
            $sitesToProcess = $sitesPac.value
        } elseif ($sitesPac -isnot [array] -and $sitesPac) {
            # Handle cases where a single site is returned not in an array
            $sitesToProcess = @($sitesPac)
        }


        if ($sitesToProcess -isnot [array]) {
             Write-Warning "Converted PAC output is not an array as expected. Output: $($sitesToProcess | ConvertTo-Json -Depth 3)"
             return $allSitesData
        }


        foreach ($site in $sitesToProcess) {
            # Verify actual field names from `pac power-pages list --json` or `pac paportal list --json`
            $siteName = $site.name `
                -or $site.Name `
                -or $site.adx_name # Common Dataverse field name for website name
            $siteId = $site.websiteId `
                -or $site.WebsiteId `
                -or $site.powerPagesWebsiteId `
                -or $site.adx_websiteid # Common Dataverse field name for website ID
            $portalUrl = $site.portalUrl `
                -or $site.url `
                -or $site.adx_primarydomainname
            $createdOn = $site.createdOn `
                -or $site.createdTime `
                -or $site.adx_createdon
            $modifiedOn = $site.modifiedOn `
                -or $site.modifiedTime `
                -or $site.adx_modifiedon
            $status = $site.status `
                -or $site.stateCode `
                -or $site.statecode # (0 for Active, 1 for Inactive often)

            # The primary connection is always Dataverse for the current environment.
            $primaryConnection = [PSCustomObject]@{
                Name        = "Dataverse"
                DisplayName = "Microsoft Dataverse (Current Environment)"
                Type        = "Dataverse"
            }

            $siteEntry = [PSCustomObject]@{
                SiteName         = $siteName
                SiteId           = $siteId
                AppType          = "Power Pages Site"
                PortalUrl        = $portalUrl
                EnvironmentId    = $EnvironmentId # This would be the environment PAC CLI is targeting
                CreatedTime      = $createdOn
                LastModifiedTime = $modifiedOn
                Status           = $status
                PrimaryConnector = $primaryConnection
                Notes            = "Other integrations (embedded Power Apps, custom JS, backend Flows) need to be correlated with other inventory parts. Site Settings (adx_sitesetting) might contain external service configurations."
            }
            $allSitesData.Add($siteEntry)
        }
    }
    catch {
        Write-Error "Failed to retrieve Power Pages sites. Error: $($_.Exception.Message)"
    }

    Write-Host "Power Pages sites inventory complete."
    return $allSitesData
}

# Example Usage:
# Make sure you have authenticated using Connect-PowerPlatform (which sets up PAC CLI context) from auth_functions.ps1 first.
# $ppagesInventory = Get-PowerPagesSitesInventory
# $ppagesInventory | Format-Table SiteName, PortalUrl, Status
# $ppagesInventory | Export-Csv -Path "./powerpages_inventory.csv" -NoTypeInformation

Write-Host "Power Pages sites inventory functions loaded."
Write-Host "Example: `$sites = Get-PowerPagesSitesInventory` (after authenticating PAC CLI)"
Write-Host "Then: `$sites | Export-Csv -Path './powerpages_inventory.csv' -NoTypeInformation`"
Write-Host "Ensure PAC CLI is installed, authenticated, and the correct environment is selected."
Write-Host "Alternative PowerShell module for Power Pages: Microsoft.PowerPlatform.PowerPages.Administration (cmdlet Get-PowerPagesSite)."
Write-Host "This script uses 'pac power-pages list' and falls back to 'pac paportal list'."

# To check PAC CLI environment context:
# pac auth list
# pac org who
