# Create Resource App Registration

To create an app registration for your resource, enter the parameter values needed and execute the script `CreateResourceAppRegistration.ps1`.  
First it will check if an App Registration with the provided UniqueName already exists.  
If it does exist:
- Make sure all App Roles provided are created

If it does not exist:
- Create a new App Registration
- Add all roles provided
- Add a UniqueName equal to the ApplicationName

Always:
- Expose an API with the URI `api://{ApplicationName}`
- Add all Application Owners provided

When the script is done you will have a new App Registration configured according to our best practices.
This should be used when setting up a new API to validate jwt tokens. Here is a policy snippet you can use in the inbound policy segment:  
``` xml
<validate-azure-ad-token tenant-id="{{TenantId}}">
    <audiences>
        <audience>api://{{ApplicationName}}</audience>
    </audiences>			
    <required-claims>
        <claim name="roles" match="any">
            <value>Default</value>
        </claim>
    </required-claims>
</validate-azure-ad-token>
```
This will ensure that the client token has the correct audience and claims to access the API.

```pwsh
#Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
#Install-Module Microsoft.Graph -Scope CurrentUser -Repository PSGallery -Force

#Powershell must be running as Administrator
#Install-Module Microsoft.Graph -Scope AllUsers -Repository PSGallery -Force

$environment = "Test"

function Main {
    Connect-MgGraph -Scopes Application.ReadWrite.All -NoWelcome 
    CreateOrUpdateEntraAppRegistration `
        -ApplicationName "ResourceApplicationName$environment" `
        -ExposeApi $true `
        -KeyVaultName "KeyVaultName" `
        -AppRoles @("Default") `
        -Owners @("john.doe@contoso.com", "jane.doe@contoso.com") # Enter email addresses of the owners of your applicaiton
}

function CreateAppRolesPayload {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $ApplicationName,

        [Parameter(Mandatory = $true)]
        [string[]] $RoleNames,

        [Parameter(Mandatory = $false)]
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphAppRole[]] $ExistingRoles = [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphAppRole[]]@()
    )

    Write-Information "Getting App Roles for $($RoleNames | ConvertTo-Json -Compress)"
    $result = @()
    foreach ($roleName in $RoleNames) {
        $role = $ExistingRoles | Where-Object { $_.Value -eq $roleName }
        if ($null -eq $role) {
            Write-Verbose "Creating App Role for $roleName"
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

function CreateOrUpdateEntraAppRegistration {
    param(
        [Parameter(Mandatory = $true)] [string] $ApplicationName,
        [Parameter(Mandatory = $true)] [bool] $ExposeApi,
        [string[]] $AppRoles = @(),
        [string[]] $Owners = @()
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
        Update-MgApplication -ApplicationId $app.Id -AppRoles $updatedAppRoleDefinitions -ErrorAction Stop
    }

    if ($ExposeApi) {
        $identifierUris = "api://$($app.UniqueName)"
        Write-Host "Exposing API with the following Identifier Uris: '$identifierUris'" -ForegroundColor Green
        Update-MgApplication -ApplicationId $app.Id -IdentifierUris $identifierUris -ErrorAction Stop

        if ($KeyVaultName) {
            Write-Host "Creating/Updating secret "$ApplicationName-scope" in key vault '$KeyVaultName'" -ForegroundColor Cyan
            $kvScope = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "$ApplicationName-scope-scope" -SecretValue $identifierUris
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
            New-MgApplicationOwnerByRef -ApplicationId $app.Id -BodyParameter $ownerPayload -ErrorAction SilentlyContinue
        }
    }
    Write-Host "Resource app registration '$ApplicationName' was sucessfully created/updated" -ForegroundColor Green
}

Main        
```