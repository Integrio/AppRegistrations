# Assign Roles To Managed Identity

#### Internal Client With Managed Identity
For internal clients with a managed identity we can assign App Roles to the existing identity. Thus removing the need for a new App Registration.  
Enter the parameter values needed and execute the script `AssignAppRolesToManagedIdentity.ps1`. 
It will find your Managed Identity and Resource App Registration by DisplayNames and assign the App Role provided. If the provided App Role exists on the resource app, it will assign that role to your Managed Identity.

**NOTE**  
The tokens your application receives are cached by the underlying Azure infrastructure. This means that any changes to the managed identity's roles can take significant time to process.

Docs:  
https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/how-to-assign-app-role-managed-identity?pivots=identity-mi-app-role-powershell  
https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/managed-identity-best-practice-recommendations#limitation-of-using-managed-identities-for-authorization

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