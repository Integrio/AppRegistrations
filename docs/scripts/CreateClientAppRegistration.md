# Create Client App Registration

```pwsh
#Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
#Install-Module Microsoft.Graph -Scope CurrentUser -Repository PSGallery -Force

#Powershell must be running as Administrator
#Install-Module Microsoft.Graph -Scope AllUsers -Repository PSGallery -Force

function Main {
    Connect-MgGraph -Scopes Application.ReadWrite.All -NoWelcome 
    CreateOrUpdateClientAppRegistration `
        -ClientApplicationName "U4-68ClientTest" `
        -ResourceApplicationName "Unit4 Proxy API:s Test" `
        -AppRolesToAssign @("Default") `
        -SecretName "Default" `
        -KeyVaultName "protestshared01kv" `
        -Owners @("ext.mattias.hammarsten@protan.no", "ext.timothy.lindberg@protan.no")
}

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
            Write-Host "Created secret valid unltil $($secret.EndDateTime)" -ForegroundColor Cyan
            $clientSecret = ConvertTo-SecureString -String $secret.SecretText -AsPlainText -Force
            $clientId = ConvertTo-SecureString -String $clientApp.AppId -AsPlainText -Force
            
            if ($KeyVaultName) {
                Write-Host "Updating secret "$ClientApplicationName-$SecretName-client-secret" in key vault '$KeyVaultName'" -ForegroundColor Cyan
                $kvClientSecret = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "$ClientApplicationName-$SecretName-client-secret" -SecretValue $clientSecret
                $kvClientId = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "$ClientApplicationName-client-id" -SecretValue $clientId
            }
        }
        else {
            Write-Host "Secret with name '$SecretName' already exists for application '$ClientApplicationName'. Skipping!" -ForegroundColor Green
        }
    }

    foreach ($owner in $Owners) {
        $user = Get-MgUser -UserId $Owner -ErrorAction SilentlyContinue
        if ($null -eq $role) {
            $objectId = $user.ID
            $ownerPayload = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/{$objectId}"
            }
            Write-Host "Adding the following user as app registration owner: '$owner'" -ForegroundColor Green
            New-MgApplicationOwnerByRef -ApplicationId $clientApp.Id -BodyParameter $ownerPayload -ErrorAction SilentlyContinue
        }
    }
    Write-Host "Client app registration '$ClientApplicationName' was sucessfully created/updated" -ForegroundColor Green
}

Main        
```