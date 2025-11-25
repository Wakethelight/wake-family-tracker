[CmdletBinding()]
param(
    [ValidateSet("dev","prod")]
    [string]$Environment = $null # Optional: pass "dev" or "prod", otherwise auto-detect
)
# ================================
# 1. DETERMINE ENVIRONMENT — FINAL VERSION (works everywhere)
# ================================
if (-not $Environment) {
    if ($env:GITHUB_WORKSPACE) {
        # CI: Look for the script's own location in the repo
        $scriptDir = $PSScriptRoot
        $relative = $scriptDir.Replace($env:GITHUB_WORKSPACE, "").TrimStart('/\')
        if ($relative -like "apps/dev_apps/*")     { $Environment = "dev" }
        elseif ($relative -like "apps/prod_apps/*") { $Environment = "prod" }
        else {
            Write-Error "Cannot auto-detect environment. Script path: $relative"
            exit 1
        }
    }
    else {
        # Local run → default to dev
        $Environment = "dev"
    }
}
Write-Host "Deploying to environment: $Environment" -ForegroundColor Green
# Optional: allow override from command line (great for local prod testing)
# Example: pwsh deploy-status-app.ps1 -Environment prod

# ================================
# 2. ENVIRONMENT CONFIG (no files!)
# ================================
$envConfig = @{
    dev = @{
        ResourceGroupPrefix = "rg-dev"
        Location = "eastus"
        Tags = @{ Environment="Development"; Owner="Chris"; CostCenter="DEV-001" }
        AppServiceSuffix = "-dev"
        VaultName = "kv-wake-dev"
        AcrName = "acrwakedev01"
    }
    prod = @{
        ResourceGroupPrefix = "rg-prod"
        Location = "eastus"
        Tags = @{ Environment="Production"; Owner="Chris"; CostCenter="PROD-001" }
        AppServiceSuffix = ""
        VaultName = "kv-wake-prod" # change when you have it
        AcrName = "acrwakeprod01" # change when you have it
    }
}
$config = $envConfig[$Environment]
# ================================
# 3. REQUIRED SECRETS / VARIABLES
# ================================
$TenantId = $env:AZURE_TENANT_ID
$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID
$PostgresPassword = $env:POSTGRES_PASSWORD
if (-not $TenantId -or -not $SubscriptionId) {
    Write-Error "AZURE_TENANT_ID and AZURE_SUBSCRIPTION_ID must be set in GitHub Secrets/Variables"
    exit 1
}
# ================================
# 4. AZURE LOGIN & CONTEXT (Actions handles this!)
# ================================
if ($env:GITHUB_ACTIONS) {
    Write-Host "Running in GitHub Actions — using OIDC (Az context auto-set)"
    # No Connect-AzAccount or Set-AzContext needed — OIDC session is active
} else {
    Connect-AzAccount -Tenant $TenantId -Subscription $SubscriptionId -UseDeviceAuthentication
    Set-AzContext -Tenant $TenantId -Subscription $SubscriptionId | Out-Null
}
# ================================
# 5. RESOURCE NAMES
# ================================
$appName = "statusapp"
$resourceGroupName = "$($config.ResourceGroupPrefix)-$appName"
$appServiceName = "$appName$($config.AppServiceSuffix)" # statusapp-dev or statusapp
Write-Host "Resource Group : $resourceGroupName"
Write-Host "App Service : $appServiceName"
Write-Host "Key Vault : $($config.VaultName)"
# ================================
# 6. CREATE RG IF MISSING
# ================================
if (-not (Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $resourceGroupName -Location $config.Location -Tag $config.Tags | Out-Null
    Write-Host "Created resource group $resourceGroupName"
}
# ================================
# 7. POSTGRES PASSWORD (secure handling)
# ================================
if ($env:GITHUB_ACTIONS) {
    if (-not $PostgresPassword) {
        Write-Error "POSTGRES_PASSWORD secret is missing!"
        exit 1
    }
    $postgresPasswordPlain = $PostgresPassword
} else {
    $sec = Read-Host "Enter Postgres admin password" -AsSecureString
    $postgresPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}
# ================================
# 8. DEPLOY BICEP
# ================================
$bicepFile = Join-Path $PSScriptRoot "bicep/main.bicep"
$parameterFile = Join-Path $PSScriptRoot "bicep/params/$Environment.json"
$deploymentName = "statusapp-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Host "Deploying Bicep with deployment name: $deploymentName"
New-AzResourceGroupDeployment `
    -Name $deploymentName `
    -ResourceGroupName $resourceGroupName `
    -TemplateFile $bicepFile `
    -TemplateParameterFile $parameterFile `
    -postgresPassword (ConvertTo-SecureString $postgresPasswordPlain -AsPlainText -Force) `
    -Verbose
# ================================
# 9. GET DEPLOYMENT OUTPUTS
# ================================
$deployment = Get-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -Name $deploymentName
$dbFqdn = $deployment.Outputs.dbFqdn.Value
$storageName = $deployment.Outputs.storageAccountName.Value
$storageKey = $deployment.Outputs.storageAccountKey.Value
Write-Host "DB FQDN: $dbFqdn"
Write-Host "Storage Account: $storageName"
# ================================
# 10. UPLOAD init.sql
# ================================
$ctx = New-AzStorageContext -StorageAccountName $storageName -StorageAccountKey $storageKey
$initSqlSource = Join-Path $PSScriptRoot "db/init.sql"
Set-AzStorageFileContent `
    -ShareName "init-sql" `
    -Context $ctx `
    -Path "init.sql" `
    -Source $initSqlSource `
    -Force
Write-Host "Uploaded init.sql"
# ================================
# 11. WRITE CONNECTION STRING TO KV
# ================================
$connString = "postgresql://postgres:$postgresPasswordPlain@$dbFqdn:5432/statusdb?sslmode=disable"
Set-AzKeyVaultSecret `
    -VaultName $config.VaultName `
    -Name "db-connection-string" `
    -SecretValue (ConvertTo-SecureString $connString -AsPlainText -Force)
Write-Host "Updated Key Vault secret 'db-connection-string'"

# 11.5 Remove any leftover bad DB_CONNECTION_STRING from App Settings (safe version)
Write-Host "Ensuring no bad DB_CONNECTION_STRING exists in App Settings..." -ForegroundColor Cyan
$currentHash = @{}
foreach ($s in (Get-AzWebApp -ResourceGroupName $resourceGroupName -Name $appServiceName).SiteConfig.AppSettings) {
    $currentHash[$s.Name] = $s.Value
}
if ($currentHash.ContainsKey("DB_CONNECTION_STRING")) {
    Write-Host "Removing bad DB_CONNECTION_STRING from App Settings" -ForegroundColor Yellow
    $currentHash.Remove("DB_CONNECTION_STRING")
    Set-AzWebApp -ResourceGroupName $resourceGroupName -Name $appServiceName -AppSettings $currentHash | Out-Null
    Write-Host "Cleaned!" -ForegroundColor Green
} else {
    Write-Host "Already clean" -ForegroundColor Cyan
}

# ================================
# 12. GRANT APP SERVICE IDENTITY RBAC ACCESS TO KEY VAULT (2025 best practice)
# ================================
Write-Host "Granting App Service RBAC access to Key Vault (Secrets User)..." -ForegroundColor Yellow

$appNameFromDeploy = $deployment.Outputs.appServiceName.Value
$webApp = Get-AzWebApp -ResourceGroupName $resourceGroupName -Name $appNameFromDeploy -ErrorAction Stop
$principalId = $webApp.Identity.PrincipalId

if (-not $principalId) {
    Write-Warning "Managed identity not ready yet — retry in 30s or re-run workflow"
} else {
    $kvScope = "/subscriptions/$SubscriptionId/resourceGroups/rg-dev-kv-wake-dev/providers/Microsoft.KeyVault/vaults/$($config.VaultName)"
    
    # Check if already assigned
    $assignment = Get-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Key Vault Secrets User" -Scope $kvScope -ErrorAction SilentlyContinue
    if ($assignment) {
        Write-Host "RBAC already assigned (idempotent)" -ForegroundColor Cyan
    } else {
        # Retry logic for propagation (up to 3 tries, 30s apart)
        $retryCount = 0
        $maxRetries = 3
        $success = $false
        while ($retryCount -lt $maxRetries -and -not $success) {
            try {
                New-AzRoleAssignment -ObjectId $principalId `
                                     -RoleDefinitionName "Key Vault Secrets User" `
                                     -Scope $kvScope | Out-Null
                Write-Host "Successfully granted 'Key Vault Secrets User' RBAC to $appNameFromDeploy" -ForegroundColor Green
                $success = $true
            } catch {
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    Write-Host "RBAC grant attempt $retryCount failed (likely propagation): $($_.Exception.Message). Retrying in 30s..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 30
                } else {
                    Write-Error "RBAC grant failed after $maxRetries attempts: $($_.Exception.Message). Check OIDC perms on KV RG and re-run."
                }
            }
        }
    }
}

# ================================
# 13. ENSURE APP SERVICE IS RUNNING (renumbered from 13)
# ================================
Write-Host "Ensuring App Service is running..." -ForegroundColor Yellow
$app = Get-AzWebApp -ResourceGroupName $resourceGroupName -Name $appServiceName -ErrorAction Stop
if ($app.State -eq "Stopped") {
    Write-Host "App Service is currently STOPPED → starting it now"
    Start-AzWebApp -ResourceGroupName $resourceGroupName -Name $appServiceName
    Write-Host "App Service STARTED successfully!" -ForegroundColor Green
}
elseif ($app.State -eq "Running") {
    Write-Host "App Service already RUNNING" -ForegroundColor Green
}
else {
    Write-Host "App Service state: $($app.State)" -ForegroundColor Cyan
}

# ================================
# 14. FINAL SUCCESS (renumbered)
# ================================
Write-Host "DEPLOYMENT COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "App URL: https://$appServiceName.azurewebsites.net" -ForegroundColor Cyan
# Outputs unchanged
$appServiceOutput = $deployment.Outputs.appServiceName.Value
echo "APP_SERVICE_NAME=$appServiceOutput" >> $env:GITHUB_OUTPUT
echo "resourceGroupName=$resourceGroupName" >> $env:GITHUB_OUTPUT
