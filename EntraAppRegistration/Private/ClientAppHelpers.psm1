$sharedHelpersPath = Join-Path $PSScriptRoot 'SharedAppHelpers.psm1'
Import-Module $sharedHelpersPath -Force -Verbose

function CreateOrUpdateClientAppRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] 
        [string] $ClientApplicationName,
        [string] $ResourceApplicationName = $null,
        [string[]] $AppRolesToAssign = @(),
        [string[]] $DelegatedPermissionsToAssign = @(),
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
        AssignAppRoles `
            -ResourceApplicationPrincipal $resourceAppSp `
            -ClientApplicationPrincipal $clientAppSp `
            -AppRolesToAssign $AppRolesToAssign
    }

    if($DelegatedPermissionsToAssign.Count -gt 0){
        $resourceApp = Get-MgApplicationByUniqueName -UniqueName $($ResourceApplicationName) -ErrorAction SilentlyContinue
        if($null -eq $resourceApp){
            Write-Host "Resource app '$ResourceApplicationName' does not exist. Create it and assign apropriate app roles before running this!" -ForegroundColor Red
            exit 1
        }

        AssignDelegatedPermissions `
            -ResourceApplication $resourceApp `
            -ClientApp $clientApp `
            -DelegatedPermissionsToAssign $DelegatedPermissionsToAssign
    }
    
    if ($SecretName) {
        $passwordCred = @{
            displayName = $SecretName
            endDateTime = (Get-Date).AddYears(50).ToUniversalTime()
        }

        $hasCredential = $clientApp.PasswordCredentials | Where-Object { $_.DisplayName -eq $SecretName }
        if (-not $hasCredential) {
            $secret = Add-MgApplicationPassword -ApplicationId $clientApp.Id -PasswordCredential $passwordCred
            Write-Host "Created secret valid until $($secret.EndDateTime)" -ForegroundColor Green
            $clientSecret = ConvertTo-SecureString -String $secret.SecretText -AsPlainText -Force
            $clientId = ConvertTo-SecureString -String $clientApp.AppId -AsPlainText -Force

            if ($KeyVaultName) {
                Write-Host "Updating secret '$ClientApplicationName-$SecretName-client-secret' in key vault '$KeyVaultName'" -ForegroundColor Green
                Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "$ClientApplicationName-$SecretName-client-secret" -SecretValue $clientSecret -Expires $passwordCred.endDateTime | Out-Null
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

function AssignDelegatedPermissions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphApplication] $ResourceApplication,
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphApplication] $ClientApplication,
        [string[]] $DelegatedPermissionsToAssign = @()
    )

    $requiredResourceAccess = $ClientApplication.RequiredResourceAccess

    foreach ($delegatedPermission in $DelegatedPermissionsToAssign) {
        $permissionToAssign = $ResourceApplication.Api.Oauth2PermissionScopes | Where-Object { $_.Value -eq $delegatedPermission }
        if ($permissionToAssign) {
            $roleAlreadyAssigned = $ClientApplication.RequiredResourceAccess | Where-Object { $_.ResourceAccess.Id -eq $permissionToAssign.Id } 
            if ($roleAlreadyAssigned) {
                Write-Host "Permission '$delegatedPermission' already assigned to client application '$($ClientApplication.DisplayName)'. Skipping!" -ForegroundColor Yellow
                continue
            }

            $newRequiredResourceAccess = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
            $newRequiredResourceAccess.ResourceAppId = $ResourceApplication.AppId
            $newRequiredResourceAccess.ResourceAccess += @{ Id = $permissionToAssign.Id; Type = "Scope" }
            $requiredResourceAccess += $newRequiredResourceAccess
        }
        else {
            Write-Host "Scope '$delegatedPermission' does not exist in resource application '$($ResourceApplicationPrincipal.DisplayName)'. Skipping!" -ForegroundColor Yellow
        }
    }

    Update-MgApplicationByAppId -AppId $ClientApplication.AppId -RequiredResourceAccess $requiredResourceAccess | Out-Null
}

Export-ModuleMember -Function @(
    'CreateOrUpdateClientAppRegistration'
)