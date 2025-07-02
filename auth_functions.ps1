<#
.SYNOPSIS
PowerShell functions for authenticating to Power Platform, SharePoint Online, Azure AD, and Power BI.

.DESCRIPTION
This script provides a set of functions to handle authentication.
It assumes PAC CLI is installed and in the PATH, and that the necessary PowerShell modules
(SharePointPnPPowerShellOnline, AzureAD, MicrosoftPowerBIMgmt) are installed.
#>

#Requires -Version 5.1

Function Connect-PowerPlatform {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$EnvironmentUrl,

        [Parameter(Mandatory=$false)]
        [string]$ApplicationId,

        [Parameter(Mandatory=$false)]
        [string]$ClientSecret,

        [Parameter(Mandatory=$false)]
        [string]$TenantId
    )

    Write-Host "Attempting to authenticate to Power Platform environment: $EnvironmentUrl"
    Write-Host "Ensure you have PAC CLI installed and configured in your PATH."

    try {
        # Check if already authenticated to this environment
        $authList = pac auth list | ConvertFrom-Json
        $existingAuth = $authList | Where-Object { $_.url -eq $EnvironmentUrl }

        if ($existingAuth) {
            Write-Host "INFO: Already authenticated to $EnvironmentUrl. Setting as active."
            pac auth select --url $EnvironmentUrl | Out-Null
        } else {
            Write-Host "INFO: Not authenticated to $EnvironmentUrl or authentication expired. Initiating new authentication."
            # Attempt interactive login first
            # For unattended, Service Principal would be needed:
            # pac auth create --url $EnvironmentUrl --applicationId $ApplicationId --clientSecret $ClientSecret --tenant $TenantId
            # However, for user-run script, interactive is more common.
            # The command below will open a browser for login.
            pac auth create --url $EnvironmentUrl
        }

        # Verify authentication
        $currentAuth = pac auth list | ConvertFrom-Json | Where-Object { $_.isActive -eq $true -and $_.url -eq $EnvironmentUrl }
        if ($currentAuth) {
            Write-Host "SUCCESS: Successfully authenticated to Power Platform environment: $EnvironmentUrl"
            Write-Host "Authenticated user: $($currentAuth.user)"
            return $true
        } else {
            Write-Warning "WARN: Authentication to Power Platform environment $EnvironmentUrl might have failed or is not active."
            # Attempt to list environments as a basic check
            Write-Host "Attempting to list environments as a check..."
            pac admin list
            return $false
        }
    }
    catch {
        Write-Error "ERROR: Failed to authenticate to Power Platform. Error: $($_.Exception.Message)"
        Write-Error "Ensure PAC CLI is installed and you have permissions to the environment."
        return $false
    }
}

Function Connect-SPOnline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SharePointAdminUrl
    )

    Write-Host "Attempting to authenticate to SharePoint Online: $SharePointAdminUrl"
    try {
        Import-Module SharePointPnPPowerShellOnline -ErrorAction SilentlyContinue
        Connect-PnPOnline -Url $SharePointAdminUrl -Interactive
        $context = Get-PnPContext
        if ($context) {
            Write-Host "SUCCESS: Successfully authenticated to SharePoint Online: $($context.Url)"
            Write-Host "Authenticated user: $($context.Web.CurrentUser.LoginName)"
            return $true
        } else {
            Write-Warning "WARN: Authentication to SharePoint Online might have failed."
            return $false
        }
    }
    catch {
        Write-Error "ERROR: Failed to authenticate to SharePoint Online. Error: $($_.Exception.Message)"
        Write-Error "Ensure SharePointPnPPowerShellOnline module is installed."
        return $false
    }
}

Function Connect-GraphAPI {
    [CmdletBinding()]
    param()

    Write-Host "Attempting to authenticate to Azure Active Directory / Microsoft Graph."
    try {
        Import-Module AzureAD -ErrorAction SilentlyContinue
        # Check if already connected
        $currentSession = Get-AzureADSession
        if ($currentSession.TenantId) {
             Write-Host "INFO: Already connected to Azure AD tenant: $($currentSession.TenantId)"
             return $true
        }

        Connect-AzureAD
        $currentSession = Get-AzureADSession
        if ($currentSession.TenantId) {
            Write-Host "SUCCESS: Successfully authenticated to Azure AD."
            Write-Host "Tenant ID: $($currentSession.TenantId), Account: $($currentSession.Account.Id)"
            return $true
        } else {
            Write-Warning "WARN: Authentication to Azure AD might have failed."
            return $false
        }
    }
    catch {
        Write-Error "ERROR: Failed to authenticate to Azure AD. Error: $($_.Exception.Message)"
        Write-Error "Ensure AzureAD module is installed."
        return $false
    }
}

Function Connect-PBI {
    [CmdletBinding()]
    param()

    Write-Host "Attempting to authenticate to Power BI Service."
    try {
        Import-Module MicrosoftPowerBIMgmt -ErrorAction SilentlyContinue
        # Check if already connected
        $currentPbiAccount = Get-PowerBIAccessToken -ErrorAction SilentlyContinue
        if ($currentPbiAccount) {
            Write-Host "INFO: Already connected to Power BI."
            # You might want to add more details here if available from Get-PowerBIAccessToken
            return $true
        }

        Connect-PowerBIServiceAccount
        # Verify connection
        $currentPbiAccount = Get-PowerBIAccessToken
         if ($currentPbiAccount) {
            Write-Host "SUCCESS: Successfully authenticated to Power BI Service."
            # Extract user info if possible, depends on what Get-PowerBIAccessToken returns or if other cmdlets are needed
            # $profile = Get-PowerBIProfile -Scope Individual -ErrorAction SilentlyContinue
            # if ($profile) { Write-Host "User: $($profile.UserPrincipalName)" }
            return $true
        } else {
            Write-Warning "WARN: Authentication to Power BI Service might have failed."
            return $false
        }
    }
    catch {
        Write-Error "ERROR: Failed to authenticate to Power BI Service. Error: $($_.Exception.Message)"
        Write-Error "Ensure MicrosoftPowerBIMgmt module is installed."
        return $false
    }
}

# Example Usage (user would uncomment and run these in their main script):
<#
# --- Configuration ---
# Source Environment Details
# Important: For Power Platform, this is the URL of your Dataverse/Dynamics 365 environment
# e.g., https://yourorg.crm.dynamics.com
$SourceEnvironmentUrl = "https://<your-org-name>.crm.dynamics.com"

# SharePoint Admin Center URL for PnP Connection
# e.g., https://yourtenant-admin.sharepoint.com
$SourceSharePointAdminUrl = "https://<your-tenant>-admin.sharepoint.com"

# --- Authentications ---
# Authenticate to Power Platform
# Connect-PowerPlatform -EnvironmentUrl $SourceEnvironmentUrl

# Authenticate to SharePoint Online
# Connect-SPOnline -SharePointAdminUrl $SourceSharePointAdminUrl

# Authenticate to Azure AD / Graph
# Connect-GraphAPI

# Authenticate to Power BI
# Connect-PBI
#>

Write-Host "Authentication functions loaded. Call them as needed in your main script."
Write-Host "Example: Connect-PowerPlatform -EnvironmentUrl 'https://yourorg.crm.dynamics.com'"
Write-Host "Example: Connect-SPOnline -SharePointAdminUrl 'https://yourtenant-admin.sharepoint.com'"
Write-Host "Example: Connect-GraphAPI"
Write-Host "Example: Connect-PBI"
