[CmdletBinding()]
param(
    [ValidateSet("dev","prod")]
    [string]$Environment,

    [Parameter()]
    [string] $BicepFile = (Join-Path -Path $PSScriptRoot -ChildPath "bicep/main.bicep"),  # Changed to main.bicep

    [Parameter()]
    [string] $ConfigFile,

    [Parameter()]
    [string] $ParameterFile
)

# Prompt if environment not supplied
if (-not $Environment) {
    $envChoice = Read-Host "Which environment do you want to deploy to? (dev/prod, default=dev)"
    if ([string]::IsNullOrWhiteSpace($envChoice)) {
        $Environment = "dev"
    } elseif ($envChoice -in @("dev","prod")) {
        $Environment = $envChoice
    } else {
        Write-Error "Invalid environment choice. Use dev or prod."
        exit
    }
}

# Resolve config/param paths AFTER environment is finalized
if (-not $ConfigFile) {
    $ConfigFile = Join-Path $PSScriptRoot "config.$Environment.json"
}
if (-not $ParameterFile) {
    $ParameterFile = Join-Path $PSScriptRoot "bicep/params/$Environment.json"
}

# Load config
$config = Get-Content $ConfigFile | ConvertFrom-Json

# Only run Connect-AzAccount locally
$subscriptionId = $config.SubscriptionId
if ($env:GITHUB_ACTIONS -or $env:TF_BUILD) {
    Write-Host "Running in CI/CD, assuming Azure login handled by pipeline."
} else {
    Connect-AzAccount -Tenant $config.TenantId -Subscription $subscriptionId
}

# Set context explicitly
Set-AzContext -Tenant $config.TenantId -Subscription $subscriptionId
$ctx = Get-AzContext
Write-Host "Active context: Tenant=$($ctx.Tenant.Id), Subscription=$($ctx.Subscription.Id)"

# Read parameter file
$params = Get-Content $ParameterFile | ConvertFrom-Json
$appName = $params.parameters.appName.value
$location  = $params.parameters.location.value
$vaultName = $params.parameters.vaultName.value  # For post-deploy

# Convert tags to hashtable
$tags = @{}
$config.Tags.PSObject.Properties | ForEach-Object {
    $tags[$_.Name] = $_.Value
}

# Build vault resource group name
$appResourceGroup = "$($config.ResourceGroupPrefix)-$appName"
Write-Host "Deploying StatusApp to Resource Group: $appResourceGroup in $Environment environment"

# Create RG if not exists
if (-not (Get-AzResourceGroup -Name $appResourceGroup -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $appResourceGroup -Location $config.DefaultLocation -Tag $tags
}

# Handle postgresPassword securely
if ($env:GITHUB_ACTIONS) {
    $postgresPassword = $env:POSTGRES_PASSWORD  # From GitHub Secrets
} else {
    $postgresPasswordSecure = Read-Host -AsSecureString -Prompt "Enter Postgres password"
    $postgresPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($postgresPasswordSecure))
}
if ([string]::IsNullOrEmpty($postgresPassword)) {
    Write-Error "Postgres password is required."
    exit
}

# Deploy StatusApp with Bicep (pass password dynamically)
New-AzResourceGroupDeployment `
    -ResourceGroupName $appResourceGroup `
    -TemplateFile $BicepFile `
    -TemplateParameterFile $ParameterFile `
    -postgresPassword $postgresPassword  # Dynamic pass

# Post-deploy: Get outputs from deployment
$deploymentName = Split-Path $BicepFile -LeafBase  # e.g., 'main'
$deployment = Get-AzResourceGroupDeployment -ResourceGroupName $appResourceGroup -Name $deploymentName
$dbFqdn = $deployment.Outputs.dbFqdn.Value
$storageAccountName = $deployment.Outputs.storageAccountName.Value
$storageAccountKey = $deployment.Outputs.storageAccountKey.Value

# Upload init.sql to file share
$ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
$initSqlPath = Join-Path $PSScriptRoot "../db/init.sql"  # Adjust if needed
Set-AzStorageFileContent -ShareName "init-sql" -Context $ctx -Path "init.sql" -Source $initSqlPath -Force
Write-Host "Uploaded init.sql to file share."

# Write DB connection string to KV (like your ACR secrets)
$connString = "postgresql://postgres:$postgresPassword@$dbFqdn:5432/statusdb?sslmode=disable"
Set-AzKeyVaultSecret -VaultName $vaultName -Name "db-connection-string" -SecretValue (ConvertTo-SecureString $connString -AsPlainText -Force)
Write-Host "Updated Key Vault with db-connection-string."