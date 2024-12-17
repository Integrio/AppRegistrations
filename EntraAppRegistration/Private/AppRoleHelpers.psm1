function CreateAppRolesPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $ApplicationName,
        [Parameter(Mandatory = $true)]
        [string[]] $RoleNames,
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphAppRole[]] $ExistingRoles = [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphAppRole[]]@()
    )

    Write-Information "Getting App Roles for $($RoleNames | ConvertTo-Json -Compress)"
    $result = @()
    foreach ($roleName in $RoleNames) {
        $role = $ExistingRoles | Where-Object { $_.Value -eq $roleName }
        if ($null -eq $role) {
            Write-Host "Creating App Role '$roleName'"  -ForegroundColor Green 
            $newRole = @{
                'AllowedMemberTypes' = @( 'Application' )
                'Description'        = "Gives '$roleName' access to application '$ApplicationName'."
                'DisplayName'        = $roleName
                'Id'                 = [guid]::NewGuid()
                'IsEnabled'          = $true
                'Value'              = $roleName
            }
            $result += $newRole
        } 
        else {
            Write-Information "Using Existing App Role for $roleName"
            $result += $role
        }
    }
    Write-Information "New App Roles: $($result | ConvertTo-Json -Compress)"
    return $result
}

function CreateOrUpdateResourceAppRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] 
        [string] $ApplicationName,
        [bool] $ExposeApi = $true,
        [string[]] $AppRoles = @(),
        [string[]] $Owners = @(),
        [string] $KeyVaultName = $null
    )

    # Get the app registration if it exists.
    $app = Get-MgApplicationByUniqueName -UniqueName $($ApplicationName) -ErrorAction SilentlyContinue
    if ($null -eq $app) {
        Write-Host "Creating new app registration: '$ApplicationName'" -ForegroundColor Green
        $newAppRoleDefinitions = CreateAppRolesPayload -ApplicationName $ApplicationName -RoleNames $AppRoles
        $app = New-MgApplication -DisplayName $ApplicationName -UniqueName $ApplicationName -AppRoles $newAppRoleDefinitions -ErrorAction Stop
        New-MgServicePrincipal -AppId $app.AppId -ErrorAction Stop       
    } 
    else {
        $updatedAppRoleDefinitions = if ($app.AppRoles.Length -gt 0) {
            CreateAppRolesPayload -ApplicationName $ApplicationName -RoleNames $AppRoles -ExistingRoles $app.AppRoles
        }
        else {
            CreateAppRolesPayload -ApplicationName $ApplicationName -RoleNames $AppRoles
        }
        Write-Host "Updating existing app registration: '$ApplicationName'" -ForegroundColor Green
        Update-MgApplication -ApplicationId $app.Id -AppRoles $updatedAppRoleDefinitions -ErrorAction Stop | Out-Null
    }
 
    if ($ExposeApi) {
        $identifierUris = "api://$($app.UniqueName)"
        Write-Host "Exposing API with the following Identifier Uris: '$identifierUris'" -ForegroundColor Green
        Update-MgApplication -ApplicationId $app.Id -IdentifierUris $identifierUris -ErrorAction Stop | Out-Null
 
        if ($KeyVaultName) {
            Write-Host "Creating/Updating secret "$ApplicationName-scope" in key vault '$KeyVaultName'" -ForegroundColor Green
            $scope = ConvertTo-SecureString -String $identifierUris -AsPlainText -Force
            Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "$ApplicationName-scope" -SecretValue $scope | Out-Null
        }
    }
 
    AssignOwners -ApplicationPrincipal $app -Owners $Owners

    Write-Host "Resource app registration '$ApplicationName' was successfully created/updated" -ForegroundColor Green
}

function CreateOrUpdateClientAppRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] 
        [string] $ClientApplicationName,
        [string] $ResourceApplicationName = $null,
        [string[]] $AppRolesToAssign = @(),
        [string[]] $Owners = @(),
        [string] $SecretName = $null,
        [string] $KeyVaultName = $null
    )

    $clientApp = Get-MgApplicationByUniqueName -UniqueName $($ClientApplicationName) -ErrorAction SilentlyContinue
    if ($null -eq $clientApp) {
        Write-Host "Creating client app registration: '$ClientApplicationName'" -ForegroundColor Green
        $clientApp = New-MgApplication -DisplayName $ClientApplicationName -UniqueName $ClientApplicationName
        $clientAppSp = New-MgServicePrincipal -AppId $clientApp.AppId -ErrorAction Stop
    } 
    else {
        Write-Host "Client app registration '$ClientApplicationName' found" -ForegroundColor Green
        $clientAppSp = Get-MgServicePrincipal -Filter "appId eq '$($clientApp.AppId)'"
        if ($null -eq $clientAppSp) {
            Write-Host "No service principal found for existing app registration" -ForegroundColor Green
            Write-Host "Creating new service principal for client app: '$($ClientApplicationName)'" -ForegroundColor Green
            $clientAppSp = New-MgServicePrincipal -AppId $clientApp.AppId -ErrorAction Stop
        }
    }

    if ($AppRolesToAssign.Count -gt 0) {

        $resourceApp = Get-MgApplicationByUniqueName -UniqueName $($ResourceApplicationName) -ErrorAction SilentlyContinue
        if ($null -eq $resourceApp) {
            Write-Host "Resource app '$ResourceApplicationName' does not exist. Create it and assign apropriate app roles before running this!" -ForegroundColor Red
            exit 1
        } 
        $resourceAppSp = Get-MgServicePrincipal -Filter "appId eq '$($resourceApp.AppId)'" 
        AssignAppRoles -ResourceApplicationPrincipal $resourceAppSp -ClientApplicationPrincipal $clientAppSp -AppRolesToAssign $AppRolesToAssign
    }
    
    if ($SecretName) {
        $passwordCred = @{
            displayName = $SecretName
            endDateTime = (Get-Date).AddYears(50)
        }

        $hasCredential = $clientApp.PasswordCredentials | Where-Object { $_.DisplayName -eq $SecretName }
        if (-not $hasCredential) {
            $secret = Add-MgApplicationPassword -ApplicationId $clientApp.Id -PasswordCredential $passwordCred
            Write-Host "Created secret valid until $($secret.EndDateTime)" -ForegroundColor Green
            $clientSecret = ConvertTo-SecureString -String $secret.SecretText -AsPlainText -Force
            $clientId = ConvertTo-SecureString -String $clientApp.AppId -AsPlainText -Force
                        
            if ($KeyVaultName) {
                Write-Host "Updating secret '$ClientApplicationName-$SecretName-client-secret' in key vault '$KeyVaultName'" -ForegroundColor Green
                Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "$ClientApplicationName-$SecretName-client-secret" -SecretValue $clientSecret | Out-Null
                Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "$ClientApplicationName-client-id" -SecretValue $clientId | Out-Null
            }
            else {
                Write-Host "No KeyVault configured. Printing Secrets. Store them someplace safe! ClientId: '$($clientApp.AppId)'. ClientSectret: '$($secret.SecretText)'" -ForegroundColor Cyan
            }
        }
        else {
            Write-Host "Secret with name '$SecretName' already exists for application '$ClientApplicationName'. Skipping!" -ForegroundColor Yellow
        }
    }

    AssignOwners -ApplicationPrincipal $clientApp -Owners $Owners

    Write-Host "Client app registration '$ClientApplicationName' was successfully created/updated" -ForegroundColor Green
}

function AssignAppRoles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphServicePrincipal] $ResourceApplicationPrincipal,
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphServicePrincipal] $ClientApplicationPrincipal,
        [string[]] $AppRolesToAssign = @()
    )

    [array]$alreadyAssignedRoles = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ClientApplicationPrincipal.Id -All

    foreach ($appRoleToAssign in $AppRolesToAssign) {
        $roleToAssign = $ResourceApplicationPrincipal.AppRoles | Where-Object { $_.Value -eq $appRoleToAssign }
        if ($roleToAssign) {
            $roleAlreadyAssigned = $alreadyAssignedRoles | Where-Object { $_.AppRoleId -eq $roleToAssign.Id } 
            if ($roleAlreadyAssigned) {
                Write-Host "Role '$appRoleToAssign' already assigned to client application '$($ClientApplicationPrincipal.DisplayName)'. Skipping!" -ForegroundColor Yellow
                continue
            }                

            #Update the application to require the role
            $requiredResourceAccess = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
            $requiredResourceAccess.ResourceAppId = $ResourceApplicationPrincipal.AppId
            $requiredResourceAccess.ResourceAccess += @{ Id = $roleToAssign.Id; Type = "Role" }
            Update-MgApplicationByAppId -AppId $ClientApplicationPrincipal.AppId -RequiredResourceAccess $requiredResourceAccess | Out-Null

            Write-Host "Assigning role '$appRoleToAssign' to client application '$($ClientApplicationPrincipal.DisplayName)'" -ForegroundColor Green
            New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ClientApplicationPrincipal.Id -PrincipalId $ClientApplicationPrincipal.Id -AppRoleId $roleToAssign.Id -ResourceId $ResourceApplicationPrincipal.Id | Out-Null
        }
        else {
            Write-Host "Role '$appRoleToAssign' does not exist in resource application '$($ResourceApplicationPrincipal.DisplayName)'. Skipping!" -ForegroundColor Yellow
        }
    }
}

function AssignOwners {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphServicePrincipal] $ApplicationPrincipal,
        [string[]] $Owners = @()
    )

    foreach ($owner in $Owners) {
        $user = Get-MgUser -UserId $owner -ErrorAction SilentlyContinue
        if ($null -eq $role) {
            $objectId = $user.ID
            $ownerPayload = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/{$objectId}"
            }
            New-MgApplicationOwnerByRef -ApplicationId $ApplicationPrincipal.Id -BodyParameter $ownerPayload -ErrorAction SilentlyContinue | Out-Null
            Write-Host "Added the following user as app registration owner: '$owner'" -ForegroundColor Green
        }
    }
}

Export-ModuleMember -Function @(
    'CreateOrUpdateResourceAppRegistration',
    'CreateOrUpdateClientAppRegistration'
)