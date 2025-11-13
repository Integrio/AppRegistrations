function Import-PrivateFunctions {
    [CmdletBinding()]
    param()
    
    $privateFunctionsPath = Join-Path $PSScriptRoot 'Private' 'AppRoleHelpers.psm1'
    Write-Verbose "Looking for private functions at: $privateFunctionsPath"
    
    if (-not (Test-Path $privateFunctionsPath)) {
        throw "Cannot find private functions file: $privateFunctionsPath"
    }
    
    try {
        Write-Verbose "Loading private functions from: $privateFunctionsPath"
        Import-Module $privateFunctionsPath -Force -Verbose
        
        # Verify critical functions exist
        $requiredFunctions = @(
            'CreateOrUpdateResourceAppRegistration',
            'CreateOrUpdateClientAppRegistration'
        )
        
        foreach ($functionName in $requiredFunctions) {
            $function = Get-Command $functionName -ErrorAction SilentlyContinue
            if (-not $function) {
                Write-Verbose "Could not find function: $functionName"
                throw "Required function '$functionName' was not loaded from private module"
            }
            Write-Verbose "Found function $functionName in module: $($function.Source)"
        }
        
        Write-Verbose "Successfully loaded all required private functions"
    }
    catch {
        throw "Failed to load private functions: $_"
    }
}

try {
    Import-PrivateFunctions
}
catch {
    throw "Module initialization failed: $_"
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

function Set-EntraResourceAppRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApplicationName,

        [Parameter(Mandatory = $true)]
        [bool]$ExposeApi,

        [Parameter(Mandatory = $true)]
        [string[]]$AppRoles,

        [Parameter(Mandatory = $true)]
        [string[]]$Owners,

        [Parameter()]
        [string]$KeyVaultName = $null,

        [Parameter()]
        [string]$Domain = $null
    )

    try {
        Assert-MgGraphConnection
        CreateOrUpdateResourceAppRegistration `
            -ApplicationName $ApplicationName `
            -ExposeApi $ExposeApi `
            -AppRoles $AppRoles `
            -Owners $Owners `
            -KeyVaultName $KeyVaultName `
            -Domain $Domain
    }
    catch {
        Write-Error "Failed to create/update resource app registration: $_"
    }
}

function Set-EntraClientAppRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClientApplicationName,
        [string]$ResourceApplicationName = $null,
        [string[]]$AppRolesToAssign = @(),
        [string[]]$Owners = @(),
        [string]$SecretName = "Default",
        [string]$KeyVaultName = $null
    )

    try {
        Assert-MgGraphConnection
        CreateOrUpdateClientAppRegistration `
            -ClientApplicationName $ClientApplicationName `
            -ResourceApplicationName $ResourceApplicationName `
            -AppRolesToAssign $AppRolesToAssign `
            -Owners $Owners `
            -SecretName $SecretName `
            -KeyVaultName $KeyVaultName `
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
                Write-Host "Resource app '$ResourceApplicationName' does not have the App Role '$appRoleName'. Skipping!" -ForegroundColor Yellow
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

function Add-RoleAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApplicationName,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionName,

        [Parameter(Mandatory = $true)]
        [string]$TargetResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$TargetResourceName,

        [Parameter(Mandatory = $true)]
        [string]$RoleDefinitionId
    )

    try {
        Assert-MgGraphConnection

        $clientApp = Get-MgApplicationByUniqueName -UniqueName $ApplicationName -ErrorAction SilentlyContinue
        if ($null -eq $clientApp) {
            throw "The application '$ApplicationName' does not exist. Please create one first bu calling 'Set-EntraClientAppRegistration' or 'Set-EntraResourceAppRegistration'"
        }

        $servicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$($clientApp.AppId)'"
        if ($null -eq $servicePrincipal) {
            throw "The application '$ApplicationName' does not have a service pricipal attached. Please create one first."
        }

        Set-AzContext -Subscription $SubscriptionName | Out-Null
        $targetResource = Get-AzResource -ResourceGroupName $TargetResourceGroupName -ResourceName $TargetResourceName
        if ($null -eq $targetResource) {
            throw "The resource '$TargetResourceName' does not exist in resource group '$TargetResourceGroupName'. Please create it first."
        }
        
        $roleAssigment = Get-AzRoleAssignment -ObjectId $servicePrincipal.Id -RoleDefinitionId $RoleDefinitionId -Scope $targetResource.Id -ErrorAction SilentlyContinue 
        if ($null -eq $roleAssigment) {
            New-AzRoleAssignment -ObjectId $servicePrincipal.Id -RoleDefinitionId $RoleDefinitionId -Scope $targetResource.Id | Out-Null
            Write-Host "Role assignment '$roleDefinitionId' successfully assigned to resource '$($targetResource.Id)' for service pricipal $($servicePrincipal.DisplayName)" -ForegroundColor Green
        }
        else {
            Write-Host "Role assignment '$roleDefinitionId' already exists for service pricipal $($servicePrincipal.DisplayName) on resource '$($targetResource.Id)'. Skipping!" -ForegroundColor Yellow
        }

    }
    catch {
        Write-Error "Failed to set role assignments on app: $_"
    }
}

# Define variables
$Global:AzureBuiltInRoles = [PSCustomObject]@{
    AcrPull = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
    AcrPush = '8311e382-0749-4cb8-b61a-304f252e45ec'
    AzureServiceBusDataOwner = '090c5cfd-751d-490a-894a-3ce6f1109419'
    AzureServiceBusDataReceiver = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
    AzureServiceBusDataSender = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
    AppConfigurationDataOwner = '5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b'
    AppConfigurationDataReader = '516239f1-63e1-4d78-a4de-a74fb236a071'
    KeyVaultReader = '21090545-7ca7-4776-b22c-e363652d74d2'
    KeyVaultSecretsUser = '4633458b-17de-408a-b874-0445c86b69e6'
    StorageBlobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    StorageBlobDataOwner = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
    StorageBlobDataReader = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
    StorageTableDataReader = '76199698-9eea-4c19-bc75-cec21354c6b6'
    StorageTableDataContributor = '	0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
}

Export-ModuleMember -Variable AzureBuiltInRoles

Export-ModuleMember -Function @(
    'Set-EntraResourceAppRegistration',
    'Set-EntraClientAppRegistration',
    'Add-EntraManagedIdentityRoles',
    'Add-RoleAssignment'
)