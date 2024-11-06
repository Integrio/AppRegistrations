# AppRegistrationManagement

## Getting started
These scripts can be used when establishing a `Oauth2 Client Credentials Flow` with a resource API and one or many clients.  
To use the scripts you will need:  
- access a
- access b
- access c



#### Resource App Registration
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

**NOTE**  
The tokens your application receives are cached by the underlying Azure infrastructure. This means that any changes to the managed identity's roles can take significant time to process.

Docs:  
https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/how-to-assign-app-role-managed-identity?pivots=identity-mi-app-role-powershell  
https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/managed-identity-best-practice-recommendations#limitation-of-using-managed-identities-for-authorization