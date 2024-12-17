@{
    RootModule = 'EntraAppRegistration.psm1'
    ModuleVersion = '2.0.1'
    GUID = '96413111-f284-4107-8b2f-8999310cfef8'
    Author = 'Mattias Hammarsten, Timothy Lindberg'
    Description = 'Module for managing Entra App Registrations, Client Apps, and Managed Identity Role assignments'
    FunctionsToExport = @(
        'Set-EntraResourceAppRegistration',
        'Set-EntraClientAppRegistration',
        'Add-EntraManagedIdentityRoles',
        'Add-RoleAssignment'
    )
    VariablesToExport = @('AzureBuiltInRoles')
    PrivateData = @{
        PSData = @{
            Tags = @('Entra', 'AppRegistration', 'Azure', 'ManagedIdentity')
            ExternalModuleDependencies = @(
                'Microsoft.Graph.Authentication',
                'Microsoft.Graph.Applications',
                'Microsoft.Graph.Users',
                'Az.KeyVault'
            )
        }
    }
}