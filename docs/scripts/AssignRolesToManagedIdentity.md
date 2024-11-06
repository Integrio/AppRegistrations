# Assign Roles To Managed Identity

```pwsh
# Install-Module Microsoft.Graph -Scope CurrentUser
Connect-MgGraph -Scopes Application.ReadWrite.All -NoWelcome 

# The name of your app, which has a managed identity that should be assigned to the resource app's app role.
$managedIdentityName = '<name of your app>'

# The name of the resource app that exposes the app role.
# For example, MyApi
$resourceApplicationName = '<name of your resource app registration>'

# The name of the app role that the managed identity should be assigned to.
# For example, MyApi.Read.All
$appRoleName = 'Default' 

# Look up the web app's managed identity.
$managedIdentity = (Get-MgServicePrincipal -Filter "DisplayName eq '$managedIdentityName'") 
if ($null -eq $managedIdentity) {
    Write-Host "Managed Identity with DisplayName '$managedIdentityName' does not exist." -ForegroundColor Red
    exit 1
}
# Look up the resource app's service principal
$resourceServicePrincipal = (Get-MgServicePrincipal -Filter "DisplayName eq '$resourceApplicationName'")
if ($null -eq $resourceServicePrincipal) {
    Write-Host "Resource app '$ResourceApplicationName' does not exist. Create it before running this!" -ForegroundColor Red
    exit 1
}

# Look up the resource service principals app roles
$appRoleId = ($resourceServicePrincipal.AppRoles | Where-Object {$_.Value -eq $appRoleName }).Id
if ($null -eq $resourceServicePrincipal) {
    Write-Host "Resource app '$ResourceApplicationName' does not have the App Role '$appRoleName'." -ForegroundColor Red
    exit 1
}

# Assign the managed identity access to the app role.
New-MgServicePrincipalAppRoleAssignment `
    -ServicePrincipalId $resourceServicePrincipal.Id `
    -PrincipalId $managedIdentity.Id `
    -ResourceId $resourceServicePrincipal.Id `
    -AppRoleId $appRoleId
```