# Import private functions
$Private = @( Get-ChildItem -Path $PSScriptRoot\Private\*.psm1 -ErrorAction SilentlyContinue )

foreach($import in $Private)
{
    try
    {
        . $import.fullname
    }
    catch
    {
        Write-Error -Message "Failed to import function $($import.fullname): $_"
    }
}

function Assert-MgGraphConnection {
    [CmdletBinding()]
    param()
    
    try {
        $context = Get-MgContext
        if (-not $context) {
            throw "Not connected to Microsoft Graph. Please run Connect-MgGraph first."
        }
    }
    catch {
        throw "Not connected to Microsoft Graph. Please run Connect-MgGraph first."
    }
}

function New-EntraResourceAppRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$ApplicationName,

        [Parameter(Mandatory = $true)]
        [bool]$ExposeApi,

        [Parameter(Mandatory = $true)]
        [string]$KeyVaultName,

        [Parameter(Mandatory = $true)]
        [string[]]$AppRoles,

        [Parameter(Mandatory = $true)]
        [string[]]$Owners
    )

    try {
        Assert-MgGraphConnection
        CreateOrUpdateEntraAppRegistration `
            -ApplicationName $ApplicationName `
            -ExposeApi $ExposeApi `
            -KeyVaultName $KeyVaultName `
            -AppRoles $AppRoles `
            -Owners $Owners
    }
    catch {
        Write-Error "Failed to create/update resource app registration: $_"
    }
}

function New-EntraClientAppRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$ClientApplicationName,

        [Parameter(Mandatory = $true)]
        [string]$ResourceApplicationName,

        [Parameter(Mandatory = $true)]
        [string[]]$AppRolesToAssign,

        [Parameter()]
        [string]$SecretName,

        [Parameter()]
        [string]$KeyVaultName = "",

        [Parameter(Mandatory = $true)]
        [string[]]$Owners
    )

    try {
        Assert-MgGraphConnection
        CreateOrUpdateClientAppRegistration `
            -ClientApplicationName $ClientApplicationName `
            -ResourceApplicationName $ResourceApplicationName `
            -AppRolesToAssign $AppRolesToAssign `
            -SecretName $SecretName `
            -KeyVaultName $KeyVaultName `
            -Owners $Owners
    }
    catch {
        Write-Error "Failed to create/update client app registration: $_"
    }
}

function Add-EntraManagedIdentityRoles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManagedIdentityName,

        [Parameter(Mandatory = $true)]
        [string]$ResourceApplicationName,

        [Parameter(Mandatory = $true)]
        [string[]]$AppRoleNames
    )

    try {
        Assert-MgGraphConnection

        $managedIdentity = Get-MgServicePrincipal -Filter "DisplayName eq '$ManagedIdentityName'"
        if ($null -eq $managedIdentity) {
            throw "Managed Identity with DisplayName '$ManagedIdentityName' does not exist."
        }

        $resourceServicePrincipal = Get-MgServicePrincipal -Filter "DisplayName eq '$ResourceApplicationName'"
        if ($null -eq $resourceServicePrincipal) {
            throw "Resource app '$ResourceApplicationName' does not exist."
        }

        foreach ($appRoleName in $AppRoleNames) {
            $appRoleId = ($resourceServicePrincipal.AppRoles | Where-Object { $_.Value -eq $appRoleName }).Id
            if ($null -eq $appRoleId) {
                Write-Warning "Resource app '$ResourceApplicationName' does not have the App Role '$appRoleName'. Skipping!"
                continue
            }

            New-MgServicePrincipalAppRoleAssignment `
                -ServicePrincipalId $resourceServicePrincipal.Id `
                -PrincipalId $managedIdentity.Id `
                -ResourceId $resourceServicePrincipal.Id `
                -AppRoleId $appRoleId

            Write-Host "App role '$appRoleName' successfully assigned to the managed identity '$ManagedIdentityName'." -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to assign managed identity roles: $_"
    }
}

Export-ModuleMember -Function @(
    'New-EntraResourceAppRegistration',
    'New-EntraClientAppRegistration',
    'Add-EntraManagedIdentityRoles'
)