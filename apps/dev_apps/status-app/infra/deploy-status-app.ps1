[CmdletBinding()]
param(
    [ValidateSet("dev","prod")]
    [string]$Environment = $null # Optional: pass "dev" or "prod", otherwise auto-detect
)
# ================================
# 1. DETERMINE ENVIRONMENT — CI + Local friendly, ZERO prompts
# ================================
if (-not $Environment) {
    if ($env:GITHUB_WORKSPACE) {
        # CI: infer from the folder structure
        $relative = (Get-Location).Path.Replace($env:GITHUB_WORKSPACE, "").TrimStart('/\')
        if ($relative -like "apps/dev_apps/*")     { $Environment = "dev" }
        elseif ($relative -like "apps/prod_apps/*") { $Environment = "prod" }
        else {
            Write-Error "Cannot auto-detect environment from path: $relative"
            exit 1
        }
    }
    else {
        # Local developer running the script → default to dev
        $Environment = "dev"
    }
}

# Optional: allow override from command line (great for local prod testing)
# Example: pwsh deploy-status-app.ps1 -Environment prod
Write-Host "Deploying to environment: $Environment" -ForegroundColor Green
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
# ================================
# 12. GRANT APP SERVICE IDENTITY ACCESS TO KEY VAULT (cross-region safe)
# ================================
Write-Host "Granting App Service identity access to Key Vault..." -ForegroundColor Yellow
$appIdentity = $deployment.Outputs.appServiceName.Value
$principalId = (Get-AzWebApp -ResourceGroupName $resourceGroupName -Name $appIdentity).Identity.PrincipalId
if (-not $principalId) {
    Write-Warning "Could not get managed identity PrincipalId — skipping KV access"
} else {
    # This works even if KV is in eastus and app is in centralus
    Set-AzKeyVaultAccessPolicy `
        -VaultName $config.VaultName `
        -ObjectId $principalId `
        -PermissionsToSecrets get `
        -BypassObjectIdValidation # ← this is the magic for cross-region
        -ErrorAction Continue
    Write-Host "Granted 'get' secrets permission to $appIdentity on vault $($config.VaultName)" -ForegroundColor Green
}
# ================================
# 13. FINAL SUCCESS
# ================================
Write-Host "DEPLOYMENT COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "App URL: https://$appServiceName.azurewebsites.net" -ForegroundColor Cyan
# Make these available to GitHub Actions (modern syntax)
$appServiceOutput = $deployment.Outputs.appServiceName.Value
echo "APP_SERVICE_NAME=$appServiceOutput" >> $env:GITHUB_OUTPUT
echo "resourceGroupName=$resourceGroupName" >> $env:GITHUB_OUTPUT
