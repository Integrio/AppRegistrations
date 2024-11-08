# Create Client App Registration

#### External Client App Registration
To create an app registration for an external client, enter the parameter values needed and execute the script `CreateClientAppRegistration.ps1`.  
First it will verify that a Resource App Registration with the provided UniqueName exists. If not, the script will fail. Then it will check if a Client App Registration with the provided UniqueName already exists.  
If it does exist:
- Make sure a Service Principal exist or is created for the App Registration

If it does not exist:
- Create a new App Registration
- Add a UniqueName equal to the ApplicationName
- Create a new Service Principal for the App Registration

Always:
- Assign the provided App Roles to the Client Application Service Principal
- Add all Application Owners provided
- Create a new secret (if it does not already exist) that will be valid for 50 years. The secret value will be added to a Key Vault Secret named `{ClientApplicationName}-{SecretName}-client-secret`
- Create a Key Vault secret for the ClientId named `{ClientApplicationName}-client-id`

Your external client will need:
- ClientId for the Client App Registration
- ClientSecret for the Client App Registration
- Scope for the Resource App Registration (`api://{ResourceApplicationName}`)
- ocp-apim-subscription-key for the API
- Token endpoint
- API endpoint

Enter this information in a new 1Password API Credential and share it with the client using 1Password share item functionality. Restrict the access to a email address or to a single view.

#### Internal Client With Managed Identity
For internal clients with a managed identity we can assign App Roles to the existing identity. Thus removing the need for a new App Registration.  
Enter the parameter values needed and execute the script `AssignAppRolesToManagedIdentity.ps1`. 
It will find your Managed Identity and Resource App Registration by DisplayNames and assign the App Role provided. If the provided App Role exists on the resource app, it will assign that role to your Managed Identity.

```pwsh
#Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
#Install-Module Microsoft.Graph -Scope CurrentUser -Repository PSGallery -Force

#Powershell must be running as Administrator
#Install-Module Microsoft.Graph -Scope AllUsers -Repository PSGallery -Force

$environment = "Test"

function Main {
    Connect-MgGraph -Scopes Application.ReadWrite.All -NoWelcome 
    CreateOrUpdateClientAppRegistration `
        -ClientApplicationName "ClientApplicationName$environment" `
        -ResourceApplicationName "ResourceApplicationName$environment" `
        -AppRolesToAssign @("Default") `
        -SecretName "Default" `
        -KeyVaultName "KeyVaultName" `
        -Owners @("john.doe@contoso.com", "jane.doe@contoso.com")
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