# Script to install required PowerShell modules

# Check if Install-Module is available
$installModuleAvailable = Get-Command Install-Module -ErrorAction SilentlyContinue
if ($installModuleAvailable) {
    Write-Host "INFO: Install-Module command is available."
} else {
    Write-Warning "WARN: Install-Module command not found. Attempting to install PowerShellGet."
    try {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop
        Install-Module PowerShellGet -Force -ErrorAction Stop
        Import-Module PowerShellGet -Force
        Write-Host "INFO: PowerShellGet should now be installed. Re-run this script."
        # We should exit here if PowerShellGet had to be installed, to give user a chance to re-run
        exit 1
    } catch {
        Write-Error "FATAL: Failed to install PowerShellGet. Please ensure it is installed manually. Error: $($_.Exception.Message)"
        exit 1
    }
}

# Function to install a module
function Install-ModuleIfNotExists {
    param(
        [string]$ModuleName
    )
    if (Get-Module -ListAvailable -Name $ModuleName) {
        Write-Host "INFO: Module '$ModuleName' is already installed."
    } else {
        Write-Host "INFO: Attempting to install module '$ModuleName'..."
        try {
            Install-Module $ModuleName -Scope CurrentUser -Force -Confirm:$false -SkipPublisherCheck -ErrorAction Stop
            Write-Host "SUCCESS: Module '$ModuleName' installed successfully."
        } catch {
            Write-Error "ERROR: Failed to install module '$ModuleName'. Error: $($_.Exception.Message)"
        }
    }
}

# Install SharePoint PnP PowerShell Online
Install-ModuleIfNotExists -ModuleName SharePointPnPPowerShellOnline

# Install Azure AD PowerShell
Install-ModuleIfNotExists -ModuleName AzureAD

# Install Power BI cmdlets
Install-ModuleIfNotExists -ModuleName MicrosoftPowerBIMgmt

Write-Host "`nINFO: Listing available modules post-installation attempts:"
Write-Host "-----------------------------------------------------"
Get-Module -ListAvailable SharePointPnPPowerShellOnline | Select-Object Name, Version, Path
Get-Module -ListAvailable AzureAD | Select-Object Name, Version, Path
Get-Module -ListAvailable MicrosoftPowerBIMgmt | Select-Object Name, Version, Path
Write-Host "-----------------------------------------------------"

Write-Host "INFO: PAC CLI installation will be addressed separately."
Write-Host "INFO: Microsoft.Xrm.Tooling.CrmConnector.PowerShell installation will be addressed if necessary."

Write-Host "`nScript execution finished."
