# AppRegistrationManagement

## Getting started

These scripts can be used when establishing a `Oauth2 Client Credentials Flow` with a resource API and one or many clients.  
To run the scripts you will need the following permissions:  

| Permission Type                    | Permission Scope                        | Purpose                                         |
|------------------------------------|-----------------------------------------|-------------------------------------------------|
| **Microsoft Graph API Permission** | `Application.ReadWrite.OwnedBy`         | Create and manage owned app registrations       |
| **Microsoft Graph API Permission** | `User.Read.All`                         | Read user profiles for owner assignment         |
| **Azure Key Vault Role**           | `Key Vault Secrets User` (or equivalent)| Create/update secrets in Key Vault              |

You will also need the Microsoft Graph PowerShell SDK and the Azure PowerShell Module. These modules provide the necessary cmdlets to interact with Microsoft Graph API and Azure services.

```pwsh
Install-Module Microsoft.Graph -Scope CurrentUser
Install-Module Az -Scope CurrentUser
```

Ensure these modules are installed and authenticated with the appropriate permissions before running the script.

### API Resource App configuration

You will need to create an app registration for your resource. Execute the script [CreateResourceAppRegistration.ps1](https://intropy.io/docs/intropy/Component/AppConfiguration/scripts/CreateResourceAppRegistration.md) and enter the parameter values when prompted to do so.  
The script performs the following actions:

1. Connects to Microsoft Graph and Azure services.
2. Creates a new app registration or updates an existing one with specified app roles.
3. Exposes the API if requested, generating and storing the identifier URI in Azure Key Vault.
4. Assigns specified users as owners of the application.

When the script has executed you will have a new App Registration configured according to our best practices.
This should be used when setting up a new API to validate jwt tokens. Here is a policy snippet you can use in the inbound policy segment:  

```xml
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

### Client App Configuration

#### External Client or client without a Managed Identity

If the client consuming the API does not have a Managed Identity, you will need to create a new App Registration for the client.
Execute the script [CreateClientAppRegistration.ps1](https://intropy.io/docs/intropy/Component/AppConfiguration/scripts/CreateClientAppRegistration.md) and enter the parameter values when prompted to do so.  
The script performs the following tasks:

1. Connects to Microsoft Graph API.
2. Checks if the resource and client applications already exist. If the client application doesn’t exist, it creates a new app registration and service principal.
3. Assigns specified app roles from the resource application to the client application.
4. Optionally generates a long-term secret for the client application, stores it in Azure Key Vault if specified, and sets the client ID as a secret in the Key Vault. KeyVault Secret name will be: `{ClientApplicationName}-{SecretName}-client-secret/id`
5. Assigns specified users as owners of the client application.

Your external client will need:

- ClientId for the Client App Registration
- ClientSecret for the Client App Registration
- Scope for the Resource App Registration (`api://{ResourceApplicationName}`)
- ocp-apim-subscription-key for the API
- Token endpoint
- API endpoint

Enter this information in a new 1Password API Credential and share it with the client using 1Password share item functionality. Restrict the access to a email address or to a single view.

#### Client with Managed Identity

If the client counsuming the API does have a Managed Identity, we can assign App Roles to the existing identity. Thus removing the need for a new App Registration. Enter the parameter values needed and execute the script [AssignAppRolesToManagedIdentity.ps1](https://intropy.io/docs/intropy/Component/AppConfiguration/scripts/AssignRolesToManagedIdentity.md).  
The script performs the following actions:

1. Connects to Microsoft Graph.
2. Verifies the existence of the specified managed identity and resource application.
3. For each app role in the list, it checks if the role exists in the resource application and assigns it to the managed identity.
4. Outputs a confirmation for each successful role assignment or a warning if a role is not found.

**NOTE**  
The token your application receives are cached by the underlying Azure infrastructure. This means that any changes to the managed identity's roles can take significant time to process (up to 24h).

Docs:  
https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/how-to-assign-app-role-managed-identity?pivots=identity-mi-app-role-powershell  
https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/managed-identity-best-practice-recommendations#limitation-of-using-managed-identities-for-authorization