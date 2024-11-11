# CreateResourceAppRegistration

```pwsh
# Prompt the user for input
$environment = Read-Host "Enter the Environment (e.g., 'Acc', 'Prod')"
$ApplicationName = Read-Host "Enter the Application Name (e.g., 'MyAPIResource')"
$ExposeApi = [bool](Read-Host "Expose API? Enter 'true' or 'false'")
$KeyVaultName = Read-Host "Enter the Key Vault Name"
$AppRoles = (Read-Host "Enter App Roles (comma-separated)").Split(',') -replace '^\s+|\s+$', '' # Trims spaces
$Owners = (Read-Host "Enter Owners' email addresses (comma-separated)").Split(',') -replace '^\s+|\s+$', ''

function CreateOrUpdateEntraAppRegistration {
    param(
        [Parameter(Mandatory = $true)] [string] $ApplicationName,
        [Parameter(Mandatory = $true)] [bool] $ExposeApi,
        [string] $KeyVaultName="",
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
            $scope = ConvertTo-SecureString -String $identifierUris -AsPlainText -Force
            $kvScope = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "$ApplicationName-scope" -SecretValue $scope
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
            New-MgApplicationOwnerByRef -ApplicationId $app.Id -BodyParameter $ownerPayload -ErrorAction SilentlyContinue
        }
    }
    Write-Host "Resource app registration '$ApplicationName' was successfully created/updated" -ForegroundColor Green
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

function Main {
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

    Connect-MgGraph -Scopes Application.ReadWrite.All -NoWelcome 
    CreateOrUpdateEntraAppRegistration `
        -ApplicationName $ApplicationName `
        -ExposeApi $ExposeApi `
        -KeyVaultName $KeyVaultName `
        -AppRoles $AppRoles `
        -Owners $Owners
}

# Call Main function with the user-provided parameters
Main -Environment $environment -ApplicationName $ApplicationName -ExposeApi $ExposeApi -KeyVaultName $KeyVaultName -AppRoles $AppRoles -Owners $Owners
```
