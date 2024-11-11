# CreateClientAppRegistration

```pwsh
# Prompt the user for input
$environment = Read-Host "Enter the Environment (e.g., 'Test', 'Prod')"
$ClientApplicationName = Read-Host "Enter the Client Application Name (e.g., 'ClientAppName$environment')"
$ResourceApplicationName = Read-Host "Enter the Resource Application Name (e.g., 'ResourceAppName$environment')"
$AppRolesToAssign = (Read-Host "Enter App Roles to Assign (comma-separated)").Split(',') -replace '^\s+|\s+$', '' # Trims spaces
$SecretName = Read-Host "Enter the Secret Name (or leave blank if none)"
$KeyVaultName = Read-Host "Enter the Key Vault Name (or leave blank if none)"
$Owners = (Read-Host "Enter Owners' email addresses (comma-separated)").Split(',') -replace '^\s+|\s+$', ''

function Main {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$ClientApplicationName,

        [Parameter(Mandatory = $true)]
        [string]$ResourceApplicationName,

        [Parameter(Mandatory = $true)]
        [string[]]$AppRolesToAssign,

        [string]$SecretName = $null,

        [string]$KeyVaultName = "",

        [Parameter(Mandatory = $true)]
        [string[]]$Owners
    )

    Connect-MgGraph -Scopes Application.ReadWrite.All -NoWelcome 
    CreateOrUpdateClientAppRegistration `
        -ClientApplicationName $ClientApplicationName `
        -ResourceApplicationName $ResourceApplicationName `
        -AppRolesToAssign $AppRolesToAssign `
        -SecretName $SecretName `
        -KeyVaultName $KeyVaultName `
        -Owners $Owners
}

# Call Main function with the user-provided parameters
Main -Environment $environment -ClientApplicationName $ClientApplicationName -ResourceApplicationName $ResourceApplicationName -AppRolesToAssign $AppRolesToAssign -SecretName $SecretName -KeyVaultName $KeyVaultName -Owners $Owners

function AssignAppRoles {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphServicePrincipal] $ResourceApplicationPrincipal,

        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphServicePrincipal] $ClientApplicationPrincipal,

        [Parameter()]
        [string[]] $AppRolesToAssign = @()
    )

    [array]$alreadyAssignedRoles = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ClientApplicationPrincipal.Id -All

    foreach ($appRoleToAssign in $AppRolesToAssign) {
        $roleToAssign = $ResourceApplicationPrincipal.AppRoles | Where-Object { $_.Value -eq $appRoleToAssign }
        if ($roleToAssign) {
            $roleAlreadyAssigned = $alreadyAssignedRoles | Where-Object { $_.AppRoleId -eq $roleToAssign.Id } 
            if ($roleAlreadyAssigned) {
                Write-Host "Role '$appRoleToAssign' already assigned to client application '$($ClientApplicationPrincipal.DisplayName)'. Skipping!" -ForegroundColor Green
                continue
            }                

            #Update the application to require the role
            $requiredResourceAccess = New-Object -TypeName Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess
            $requiredResourceAccess.ResourceAppId = $ResourceApplicationPrincipal.AppId
            $requiredResourceAccess.ResourceAccess+=@{ Id = $roleToAssign.Id; Type = "Role" }
            Update-MgApplicationByAppId -AppId $ClientApplicationPrincipal.AppId -RequiredResourceAccess $requiredResourceAccess

            Write-Host "Assigning role '$appRoleToAssign' to client application '$($ClientApplicationPrincipal.DisplayName)'" -ForegroundColor Green
            New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ClientApplicationPrincipal.Id -PrincipalId $ClientApplicationPrincipal.Id -AppRoleId $roleToAssign.Id -ResourceId $ResourceApplicationPrincipal.Id
        }
        else {
            Write-Host "Role '$appRoleToAssign' does not exist in resource application '$($ResourceApplicationPrincipal.DisplayName)'. Skipping!" -ForegroundColor Yellow
        }
    }
}

function CreateOrUpdateClientAppRegistration {
    param(
        [Parameter(Mandatory = $true)] [string] $ClientApplicationName,
        [Parameter(Mandatory = $true)] [string] $ResourceApplicationName,
        [string] $SecretName = $null,
        [string] $KeyVaultName="",
        [string[]] $AppRolesToAssign = @(),
        [string[]] $Owners = @()
    )

    $resourceApp = Get-MgApplicationByUniqueName -UniqueName $($ResourceApplicationName) -ErrorAction SilentlyContinue
    if ($null -eq $resourceApp) {
        Write-Host "Resource app '$ResourceApplicationName' does not exist. Create it before running this!" -ForegroundColor Red
        exit 1
    } 
    $resourceAppSp = Get-MgServicePrincipal -Filter "appId eq '$($resourceApp.AppId)'" 

    Write-Host "Resource app registration '$ResourceApplicationName' found" -ForegroundColor Green

    $clientApp = Get-MgApplicationByUniqueName -UniqueName $($ClientApplicationName) -ErrorAction SilentlyContinue
    if ($null -eq $clientApp) {
        Write-Host "Creating client app registration: '$ClientApplicationName'" -ForegroundColor Green
        $clientApp = New-MgApplication -DisplayName $ClientApplicationName -UniqueName $ClientApplicationName
        New-MgServicePrincipal -AppId $clientApp.AppId -ErrorAction Stop
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

    AssignAppRoles -ResourceApplicationPrincipal $resourceAppSp -ClientApplicationPrincipal $clientAppSp -AppRolesToAssign $AppRolesToAssign

    if ($SecretName) {
        $passwordCred = @{
            displayName = $SecretName
            endDateTime = (Get-Date).AddYears(50)
        }

        $hasDefaultCredential = $clientApp.PasswordCredentials | Where-Object { $_.DisplayName -eq $SecretName }
        if (-not $hasDefaultCredential) {
            $secret = Add-MgApplicationPassword -ApplicationId $clientApp.Id -PasswordCredential $passwordCred
            Write-Host "Created secret valid until $($secret.EndDateTime)" -ForegroundColor Cyan
            $clientSecret = ConvertTo-SecureString -String $secret.SecretText -AsPlainText -Force
            $clientId = ConvertTo-SecureString -String $clientApp.AppId -AsPlainText -Force
            
            if ($KeyVaultName) {
                Write-Host "Updating secret '$ClientApplicationName-$SecretName-client-secret' in key vault '$KeyVaultName'" -ForegroundColor Cyan
                $kvClientSecret = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "$ClientApplicationName-$SecretName-client-secret" -SecretValue $clientSecret
                $kvClientId = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "$ClientApplicationName-client-id" -SecretValue $clientId
            }
        }
        else {
            Write-Host "Secret with name '$SecretName' already exists for application '$ClientApplicationName'. Skipping!" -ForegroundColor Green
        }
    }

    foreach ($owner in $Owners) {
        $user = Get-MgUser -UserId $owner -ErrorAction SilentlyContinue
        if ($null -eq $role) {
            $objectId = $user.ID
            $ownerPayload = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/{$objectId}"
            }
            Write-Host "Adding the following user as app registration owner: '$owner'" -ForegroundColor Green
            New-MgApplicationOwnerByRef -ApplicationId $clientApp.Id -BodyParameter $ownerPayload -ErrorAction SilentlyContinue
        }
    }
    Write-Host "Client app registration '$ClientApplicationName' was successfully created/updated" -ForegroundColor Green
}
```
