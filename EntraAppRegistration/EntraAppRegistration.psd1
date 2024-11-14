@{
    RootModule = 'EntraAppRegistration.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'CC984B2A-A2A0-11EF-BBE7-CECC87E1CF5E'
    Author = 'Mattias Hammarsten, Timothy Lindberg'
    Description = 'Module for managing Entra App Registrations, Client Apps, and Managed Identity Role assignments'
    PowerShellVersion = '5.1'
    RequiredModules = @(
        @{
            ModuleName = 'Microsoft.Graph'
            ModuleVersion = '2.0.0'  # Adjust version as needed
        }
    )
    FunctionsToExport = @(
        'New-EntraResourceAppRegistration',
        'New-EntraClientAppRegistration',
        'Add-EntraManagedIdentityRoles'
    )
    PrivateData = @{
        PSData = @{
            Tags = @('Entra', 'AppRegistration', 'Azure', 'ManagedIdentity')
            ProjectUri = 'YOUR-PROJECT-URI'  # Optional
        }
    }
}