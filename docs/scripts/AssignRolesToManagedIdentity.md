# AssignRolesToManagedIdentity

```pwsh
# Prompt the user for input
$managedIdentityName = Read-Host "Enter the name of your app with the managed identity"
$resourceApplicationName = Read-Host "Enter the name of the resource app that exposes the app roles"
$appRoleNames = (Read-Host "Enter the app roles to assign to the managed identity (comma-separated, e.g., 'MyApi.Read.All,MyApi.Write.All')").Split(',') -replace '^\s+|\s+$', '' # Trims spaces

# Connect to Microsoft Graph
Connect-MgGraph -Scopes Application.ReadWrite.All -NoWelcome 

# Look up the web app's managed identity.
$managedIdentity = Get-MgServicePrincipal -Filter "DisplayName eq '$managedIdentityName'"
if ($null -eq $managedIdentity) {
    Write-Host "Managed Identity with DisplayName '$managedIdentityName' does not exist." -ForegroundColor Red
    exit 1
}

# Look up the resource app's service principal
$resourceServicePrincipal = Get-MgServicePrincipal -Filter "DisplayName eq '$resourceApplicationName'"
if ($null -eq $resourceServicePrincipal) {
    Write-Host "Resource app '$resourceApplicationName' does not exist. Create it before running this!" -ForegroundColor Red
    exit 1
}

# Assign each app role in the list to the managed identity
foreach ($appRoleName in $appRoleNames) {
    # Look up the app role ID for each role
    $appRoleId = ($resourceServicePrincipal.AppRoles | Where-Object { $_.Value -eq $appRoleName }).Id
    if ($null -eq $appRoleId) {
        Write-Host "Resource app '$resourceApplicationName' does not have the App Role '$appRoleName'. Skipping!" -ForegroundColor Yellow
        continue
    }

    # Assign the managed identity access to the app role
    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $resourceServicePrincipal.Id `
        -PrincipalId $managedIdentity.Id `
        -ResourceId $resourceServicePrincipal.Id `
        -AppRoleId $appRoleId

    Write-Host "App role '$appRoleName' successfully assigned to the managed identity '$managedIdentityName' for the resource app '$resourceApplicationName'." -ForegroundColor Green
}
```
