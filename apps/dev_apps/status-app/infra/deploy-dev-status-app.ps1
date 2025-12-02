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
        VaultResourceGroup = "rg-dev-kv-wake-dev"   # NEW
        AcrName = "acrwakedev01"
    }
    prod = @{
        ResourceGroupPrefix = "rg-prod"
        Location = "eastus"
        Tags = @{ Environment="Production"; Owner="Chris"; CostCenter="PROD-001" }
        AppServiceSuffix = ""
        VaultName = "kv-wake-prod"
        VaultResourceGroup = "rg-prod-kv-wake-prod" # NEW
        AcrName = "acrwakeprod01"
    }
}
$config = $envConfig[$Environment]

# ================================
# 3. REQUIRED SECRETS / VARIABLES
# ================================
$TenantId = $env:AZURE_TENANT_ID
$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID
$PostgresPassword = $env:POSTGRES_PASSWORD
$acrPassword = $env:ACR_PASSWORD

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
# 8. DEPLOY BICEP (single phase with admin creds)
# ================================
$bicepFile = Join-Path $PSScriptRoot "bicep/main.bicep"
$parameterFile = Join-Path $PSScriptRoot "bicep/params/$Environment.json"
$deploymentName = "statusapp-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Host "Deploying Bicep with deployment name: $deploymentName"

try {
    # Capture the deployment result directly
    $deployment = New-AzResourceGroupDeployment `
        -Name $deploymentName `
        -ResourceGroupName $resourceGroupName `
        -TemplateFile $bicepFile `
        -TemplateParameterFile $parameterFile `
        -postgresPassword (ConvertTo-SecureString $postgresPasswordPlain -AsPlainText -Force) `
        -acrAdminPassword (ConvertTo-SecureString $acrPassword -AsPlainText -Force) `
        -Verbose -ErrorAction Stop
} catch {
    if ($_.Exception.Message -like "*RoleAssignmentExists*") {
        Write-Warning "Role assignment already exists, continuing..."
    } else {
        throw
    }
}

# Helper function to safely extract outputs
function Get-DeploymentOutputValue {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Deployment,
        [Parameter(Mandatory=$true)]
        [string]$Key
    )
    if ($Deployment.Outputs -and $Deployment.Outputs.ContainsKey($Key) -and $Deployment.Outputs[$Key]) {
        return [string]$Deployment.Outputs[$Key].Value
    } else {
        Write-Warning "Deployment output '$Key' not found or empty"
        return ""
    }
}

# ================================
# 9. GET DEPLOYMENT OUTPUTS
# ================================
$dbFqdn         = Get-DeploymentOutputValue -Deployment $deployment -Key "dbFqdn"
$storageName    = Get-DeploymentOutputValue -Deployment $deployment -Key "storageAccountName"
$storageKey     = Get-DeploymentOutputValue -Deployment $deployment -Key "storageAccountKey"
$appServiceName = Get-DeploymentOutputValue -Deployment $deployment -Key "appServiceName"
$appServiceOutput = $appServiceName

Write-Host "DB FQDN: $dbFqdn"
Write-Host "Storage Account: $storageName"
Write-Host "App Service: $appServiceName"

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
# 11. ENSURE APP SERVICE IS RUNNING
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
# 12. FINAL SUCCESS
# ================================
Write-Host "DEPLOYMENT COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "App URL: https://$appServiceName.azurewebsites.net" -ForegroundColor Cyan
Write-Host "Emitting GitHub outputs..."
"APP_SERVICE_NAME=$appServiceOutput" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
"resourceGroupName=$resourceGroupName" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
"VAULT_NAME=$($config.VaultName)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append



<#
old deployment code for three-phase ACI with RBAC (now removed)
# Phase 1: Deploy ACI (identity created, container may fail to start)
try {
    New-AzResourceGroupDeployment `
        -Name "$deploymentName-aci" `
        -ResourceGroupName $resourceGroupName `
        -TemplateFile $bicepFile `
        -TemplateParameterFile $parameterFile `
        -postgresPassword (ConvertTo-SecureString $postgresPasswordPlain -AsPlainText -Force) `
        -deployPhase "aciOnly" `
        -acrAdminPassword (ConvertTo-SecureString $acrPassword -AsPlainText -Force)
        -Verbose -ErrorAction Stop
} catch {
    Write-Warning "ACI phase failed to start container (expected). Identity still created. Continuing to RBAC phase..."
}

# Phase 2: Deploy RBAC (assign AcrPull to ACI identity)
try {
    New-AzResourceGroupDeployment `
        -Name "$deploymentName-rbac" `
        -ResourceGroupName $resourceGroupName `
        -TemplateFile $bicepFile `
        -TemplateParameterFile $parameterFile `
        -postgresPassword (ConvertTo-SecureString $postgresPasswordPlain -AsPlainText -Force) `
        -deployPhase "rbacOnly" `
        -Verbose -ErrorAction Stop

    $rbacDeployment = Get-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -Name "$deploymentName-rbac"
    $acrResourceIdForAci    = [string]$rbacDeployment.Outputs['acrResourceIdForAci'].Value
    $acrAssignedPrincipalAci= [string]$rbacDeployment.Outputs['acrAssignedPrincipalAci'].Value
    Write-Host "RBAC assignment applied: AcrPull on $acrResourceIdForAci for principal $acrAssignedPrincipalAci"
} catch {
    Write-Warning "RBAC phase reported errors (likely due to ACI being in Failed state). Role assignment is idempotent and should still exist. Continuing to final redeploy..."
}

# Phase 3: Redeploy ACI (now can pull image) with retry loop
$maxRetries = 3
$retryCount = 0
$success = $false

while (-not $success -and $retryCount -lt $maxRetries) {
    try {
        $attemptName = "$deploymentName-aci-redeploy-$retryCount"
        New-AzResourceGroupDeployment `
            -Name $attemptName `
            -ResourceGroupName $resourceGroupName `
            -TemplateFile $bicepFile `
            -TemplateParameterFile $parameterFile `
            -postgresPassword (ConvertTo-SecureString $postgresPasswordPlain -AsPlainText -Force) `
            -deployPhase "aciOnly" `
            -Verbose -ErrorAction Stop

        $success = $true
        Write-Host "ACI redeploy succeeded on attempt $($retryCount+1)" -ForegroundColor Green
        $deployment = Get-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -Name $attemptName
    } catch {
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Write-Warning "ACI redeploy attempt $retryCount failed (likely RBAC propagation). Retrying in 30s..."
            Start-Sleep -Seconds 30
        } else {
            Write-Error "ACI redeploy failed after $maxRetries attempts. Check ACR permissions and image availability."
            exit 1
        }
    }
}
#>