$sharedHelpersPath = Join-Path $PSScriptRoot 'SharedAppHelpers.psm1'
Import-Module $sharedHelpersPath -Force -Verbose

function CreateOrUpdateResourceAppRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] 
        [string] $ApplicationName,
        [bool] $ExposeApi = $true,
        [string[]] $AppRoles = @(),
        [string[]] $Owners = @(),
        [string] $KeyVaultName = $null,
        [ValidateSet("UniqueName", "AppId")]
        [string] $IdentifierUriType = "UniqueName",
        [bool] $OrganizationalAccess = $false,
        [string] $ScopeName = $null
    )

    if($OrganizationalAccess -eq $true -and [string]::IsNullOrEmpty($ScopeName)){
        throw [System.ArgumentException]::new("ScopeName parameter is required when OrganizationalAccess is set to true. Example: System.Access")
    }

    # Get the app registration if it exists.
    $app = Get-MgApplicationByUniqueName -UniqueName $($ApplicationName) -ErrorAction SilentlyContinue
    if ($null -eq $app) {
        Write-Host "Creating new app registration: '$ApplicationName'" -ForegroundColor Green
        $newAppRoleDefinitions = CreateAppRolesPayload -ApplicationName $ApplicationName -AppRoles $AppRoles
        
        $appParams = @{
            DisplayName = $ApplicationName
            UniqueName = $ApplicationName
            AppRoles = $newAppRoleDefinitions
        }

        $app = New-MgApplication @appParams -ErrorAction Stop
        New-MgServicePrincipal -AppId $app.AppId -ErrorAction Stop | Out-Null
    } 
    else {
        $updatedAppRoleDefinitions = if ($app.AppRoles.Length -gt 0) {
            CreateAppRolesPayload -ApplicationName $ApplicationName -AppRoles $AppRoles -ExistingRoles $app.AppRoles
        }
        else {
            CreateAppRolesPayload -ApplicationName $ApplicationName -AppRoles $AppRoles
        }
        
        Write-Host "Updating existing app registration: '$ApplicationName'" -ForegroundColor Green
        
        $updateParams = @{
            ApplicationId = $app.Id
            AppRoles = $updatedAppRoleDefinitions
        }

        Update-MgApplication @updateParams -ErrorAction Stop | Out-Null
    }
 
    if ($ExposeApi) {
        Set-ApiExposureConfiguration `
            -Application $app `
            -ApplicationName $ApplicationName `
            -IdentifierUriType $IdentifierUriType `
            -OrganizationalAccess $OrganizationalAccess `
            -ScopeName $ScopeName `
            -KeyVaultName $KeyVaultName
    }
 
    AssignOwners -ApplicationPrincipal $app -Owners $Owners

    Write-Host "Resource app registration '$ApplicationName' was successfully created/updated" -ForegroundColor Green
}

function CreateAppRolesPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $ApplicationName,
        [Parameter(Mandatory = $true)]
        [string[]] $AppRoles,
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphAppRole[]] $ExistingRoles = [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphAppRole[]]@()
    )

    $parsedRoles = @()
    foreach ($roleString in $AppRoles) {
        if ($roleString -match '^([^:]+):(.+)$') {
            $name = $matches[1].Trim()
            $types = $matches[2] -split ',' | ForEach-Object { $_.Trim() }
            
            $parsedRoles += @{
                name = $name
                allowedTypes = $types
            }
        }
        else{
            Write-Warning "The AppRole $roleString was formatted incorrectly. Valid format: RoleName:Application,User or RoleName:Application"
        }
    }

    Write-Information "Getting Roles for $($parsedRoles | ConvertTo-Json -Compress)"

    $result = @()
    foreach ($role in $parsedRoles) {
        $existingRole = $ExistingRoles | Where-Object { $_.Value -eq $role.name }
        if ($null -eq $existingRole) {
            Write-Host "Creating App Role '$($role.name)'" -ForegroundColor Green 
            
            $newRole = @{
                'AllowedMemberTypes' = $role.allowedTypes
                'Description'        = "Gives '$($role.name)' access to application '$ApplicationName'."
                'DisplayName'        = $role.name
                'Id'                 = [guid]::NewGuid()
                'IsEnabled'          = $true
                'Value'              = $role.name
            }
            $result += $newRole
        } 
        else {
            Write-Information "Using Existing App Role for $($role.name)"
            $result += $existingRole
        }
    }

    Write-Information "New Roles: $($result | ConvertTo-Json -Compress)"
    Write-Host $result
    return $result
}

function Set-ApiExposureConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Application,
        
        [Parameter(Mandatory = $true)]
        [string]$ApplicationName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("UniqueName", "AppId")]
        [string]$IdentifierUriType,
        
        [Parameter()]
        [bool]$OrganizationalAccess = $false,
        
        [Parameter()]
        [string]$ScopeName = "Access",
        
        [Parameter()]
        [string]$KeyVaultName = $null
    )

    # Build identifier URI based on type
    $identifierUris = switch ($IdentifierUriType) {
        "UniqueName" { "api://$($Application.UniqueName)" }
        "AppId" { "api://$($Application.AppId)" }
    }

    Write-Host "Exposing API with the following Identifier Uris: '$identifierUris'" -ForegroundColor Green
    
    $apiParams = @{
        ApplicationId = $Application.Id
        IdentifierUris = $identifierUris
    }

    # Add OAuth2 permission scope if OrganizationalAccess is true
    if ($OrganizationalAccess) {
        $oauth2PermissionScope = CreateOAuth2PermissionScope -ScopeName $ScopeName
        $apiParams.Api = @{
            Oauth2PermissionScopes = @($oauth2PermissionScope)
        }
        Write-Host "Adding OAuth2 permission scope: '$ScopeName'" -ForegroundColor Green
    }

    Update-MgApplication @apiParams -ErrorAction Stop | Out-Null

    # Store scope in Key Vault if specified
    if ($KeyVaultName) {
        Write-Host "Creating/Updating secret '$ApplicationName-scope' in key vault '$KeyVaultName'" -ForegroundColor Green
        $scope = ConvertTo-SecureString -String $identifierUris -AsPlainText -Force
        Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "$ApplicationName-scope" -SecretValue $scope | Out-Null
    }
}

function CreateOAuth2PermissionScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScopeName
    )

    return @{
        Id = [System.Guid]::NewGuid().ToString()
        AdminConsentDescription = "Allow the application to access $ScopeName on behalf of the signed-in user."
        AdminConsentDisplayName = "Access $ScopeName"
        IsEnabled = $true
        Type = "User"
        UserConsentDescription = "Allow the application to access $ScopeName on your behalf."
        UserConsentDisplayName = "Access $ScopeName"
        Value = $ScopeName
    }
}

Export-ModuleMember -Function @(
    'CreateOrUpdateResourceAppRegistration'
)