# ================================
# Interactive Service Principal Creator (Azure-generated secret)
# ================================
# if you want to only update roles on an existing SP, run with -UpdateOnly
param(
    [switch]$UpdateOnly
)

# Variables for Azure connection
$subscriptionId = "bb8f3354-1ce0-4efc-b2a7-8506304c5362"
$tenantId       = "a5dea08c-0cc9-40d8-acaa-cacf723e7b9b"

# Environment config
$envConfig = @{
    dev = @{
        VaultName = "kv-wake-dev"
        VaultResourceGroup = "rg-dev-kv-wake-dev"
        AcrName = "acrwakedev01"
    }
    prod = @{
        VaultName = "kv-wake-prod"
        VaultResourceGroup = "rg-prod-kv-wake-prod"
        AcrName = "acrwakeprod01"
    }
}

# Prompt for environment
$Environment = Read-Host "Enter environment (dev/prod)"
if (-not $envConfig.ContainsKey($Environment)) {
    Write-Error "Invalid environment. Must be 'dev' or 'prod'."
    exit
}
$config = $envConfig[$Environment]

# Prompt for SP name prefix
$SpNameprefix = Read-Host "Enter Service Principal name prefix (e.g. sp-aci)"
$SpName = "$SpNameprefix-$Environment"

param(
    [switch]$UpdateOnly
)

# Connect
Connect-AzAccount -Subscription $subscriptionId -Tenant $tenantId

# Try to get existing SP
$existingSp = Get-AzADServicePrincipal -DisplayName $SpName -ErrorAction SilentlyContinue

if ($null -eq $existingSp) {
    if ($UpdateOnly) {
        Write-Error "UpdateOnly specified, but Service Principal $SpName does not exist."
        exit
    }

    Write-Host "Service Principal $SpName does not exist. Creating..."
    $sp = New-AzADServicePrincipal -DisplayName $SpName
    $secretValue = $sp.PasswordCredentials.SecretText

    # Store credentials in Key Vault
    $clientIdSecret = Set-AzKeyVaultSecret -VaultName $config.VaultName -Name "$($SpName)-client-id" -SecretValue (ConvertTo-SecureString $sp.AppId -AsPlainText -Force)
    $tenantIdSecret = Set-AzKeyVaultSecret -VaultName $config.VaultName -Name "$($SpName)-tenant-id" -SecretValue (ConvertTo-SecureString $tenantId -AsPlainText -Force)
    $clientSecret   = Set-AzKeyVaultSecret -VaultName $config.VaultName -Name "$($SpName)-client-secret" -SecretValue (ConvertTo-SecureString $secretValue -AsPlainText -Force)

    Write-Host "Stored credentials in Key Vault: $($config.VaultName)"
} else {
    Write-Host "Service Principal $SpName already exists."
    $sp = $existingSp
}

# Show existing role assignments
Write-Host "`n===== EXISTING ROLE ASSIGNMENTS ====="
$roles = Get-AzRoleAssignment -ObjectId $sp.Id -Scope "/subscriptions/$subscriptionId"
if ($roles) {
    $roles | Select-Object RoleDefinitionName, Scope | Format-Table
} else {
    Write-Host "No roles currently assigned."
}
Write-Host "======================================"

# Role assignment loop
# Track changes
$addedRoles = @()
$removedRoles = @()
$actionLog = @()

do {
    $action = Read-Host "Enter a role to assign, or type 'remove <RoleName>' to remove (leave blank to finish)"

    if (![string]::IsNullOrWhiteSpace($action)) {
        # Handle removal
        if ($action -like "remove *") {
            $roleToRemove = $action.Substring(7).Trim()
            # Confirm removal
            $confirm = Read-Host "Are you sure you want to remove role '$roleToRemove' from $SpName? (y/n)"
            if ($confirm -eq "y") {
                try {
                    $assignment = Get-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName $roleToRemove -Scope "/subscriptions/$subscriptionId"
                    if ($assignment) {
                        Remove-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName $roleToRemove -Scope "/subscriptions/$subscriptionId"
                        Write-Host "Removed role $roleToRemove from $SpName"
                        $removedRoles += $roleToRemove
                        $actionLog += "$(Get-Date -Format 'u') - Removed role $roleToRemove"
                    } else {
                        Write-Host "Role $roleToRemove not currently assigned to $SpName"
                        $actionLog += "$(Get-Date -Format 'u') - Attempted removal of $roleToRemove (not assigned)"
                    }
                } catch {
                    Write-Warning "Failed to remove role $roleToRemove. Check spelling or availability."
                    $actionLog += "$(Get-Date -Format 'u') - Failed removal of $roleToRemove"
                }
            } else {
                Write-Host "Skipped removal of $roleToRemove"
                $actionLog += "$(Get-Date -Format 'u') - Skipped removal of $roleToRemove"
            }
        }
        else {
            $role = $action
            try {
                # Assign role
                if (-not (Get-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName $role -Scope "/subscriptions/$subscriptionId")) {
                    New-AzRoleAssignment -ApplicationId $sp.AppId -RoleDefinitionName $role -Scope "/subscriptions/$subscriptionId"
                    Write-Host "Assigned role $role to $SpName"
                    $addedRoles += $role
                    $actionLog += "$(Get-Date -Format 'u') - Assigned role $role"
                } else {
                    # Already assigned
                    Write-Host "Role $role already assigned to $SpName"
                    $actionLog += "$(Get-Date -Format 'u') - Attempted assignment of $role (already assigned)"
                }
            } catch {
                Write-Warning "Failed to assign role $role. Check spelling or availability."
                $actionLog += "$(Get-Date -Format 'u') - Failed assignment of $role"
            }
        }

        # Show current roles after every change
        Write-Host "`n===== CURRENT ROLE ASSIGNMENTS ====="
        $roles = Get-AzRoleAssignment -ObjectId $sp.Id -Scope "/subscriptions/$subscriptionId"
        if ($roles) {
            $roles | Select-Object RoleDefinitionName, Scope | Format-Table
        } else {
            Write-Host "No roles currently assigned."
        }
        Write-Host "====================================`n"
    }
} while (![string]::IsNullOrWhiteSpace($action))

# ================================
# Summary Report
# ================================

$summaryLines = @()
$summaryLines += "===== SUMMARY ====="
$summaryLines += "Service Principal: $SpName"
$summaryLines += "AppId: $($sp.AppId)"
$summaryLines += "TenantId: $tenantId"
$summaryLines += "Key Vault: $($config.VaultName)"
$summaryLines += "Existing Roles (final state): $($roles.RoleDefinitionName -join ', ')"
$summaryLines += "New Roles Assigned: $($addedRoles -join ', ')"
$summaryLines += "Roles Removed: $($removedRoles -join ', ')"

if (-not $UpdateOnly) {
    $summaryLines += "Secrets stored at:"
    $summaryLines += " - ClientId: $($clientIdSecret.Id)"
    $summaryLines += " - TenantId: $($tenantIdSecret.Id)"
    $summaryLines += " - ClientSecret: $($clientSecret.Id)"
}

$summaryLines += "Action Log:"
$summaryLines += $actionLog
$summaryLines += "===================="

# Write to console
$summaryLines | ForEach-Object { Write-Host $_ }

# Export to file
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$summaryFile = ".\${SpName}-summary-$timestamp.txt"
$summaryLines | Out-File -FilePath $summaryFile -Encoding UTF8

Write-Host "Summary exported to $summaryFile"