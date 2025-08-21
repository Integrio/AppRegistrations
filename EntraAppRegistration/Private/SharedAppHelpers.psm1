function AssignOwners {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphServicePrincipal] $ApplicationPrincipal,
        [string[]] $Owners = @()
    )

    foreach ($owner in $Owners) {
        $user = Get-MgUser -UserId $owner -ErrorAction SilentlyContinue
        if ($null -eq $role) {
            $objectId = $user.ID
            $ownerPayload = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/{$objectId}"
            }
            New-MgApplicationOwnerByRef -ApplicationId $ApplicationPrincipal.Id -BodyParameter $ownerPayload -ErrorAction SilentlyContinue | Out-Null
            Write-Host "Added the following user as app registration owner: '$owner'" -ForegroundColor Green
        }
    }
}

Export-ModuleMember -Function @(
    'AssignOwners'
)