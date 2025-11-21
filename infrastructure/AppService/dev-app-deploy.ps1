##not ready for production use##

[CmdletBinding()]
param(
    [ValidateSet("dev","prod")]
    [string]$Environment,

    [ValidateSet("container","managed")]
    [string]$DeployMode = "container",

    [Parameter()]
    [string] $BicepFile = (Join-Path -Path $PSScriptRoot -ChildPath "bicep/main.bicep"),

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
$acrName          = $params.parameters.acrName.value
$appServicePlan   = $params.parameters.appServicePlanName.value
$webAppName       = $params.parameters.webAppName.value
$postgresName     = $params.parameters.postgresName.value
$postgresAdmin    = $params.parameters.postgresAdmin.value
$postgresPassword = $params.parameters.postgresPassword.value

# Convert tags to hashtable
$tags = @{}
$config.Tags.PSObject.Properties | ForEach-Object {
    $tags[$_.Name] = $_.Value
}

# Build resource group name
$resourceGroup = "$($config.ResourceGroupPrefix)-$webAppName-$Environment"
Write-Host "Deploying infra to Resource Group: $resourceGroup in $Environment environment"

# Create RG if not exists
if (-not (Get-AzResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $resourceGroup -Location $config.DefaultLocation -Tag $tags
}

# Read ACR secrets from Key Vault (already created in step 2)
$acrLoginServer = (Get-AzKeyVaultSecret -VaultName $config.vaultName -Name "acrLoginServer").SecretValueText
$acrId          = (Get-AzKeyVaultSecret -VaultName $config.vaultName -Name "acrId").SecretValueText

# Deploy infra with Bicep
$deployment = New-AzResourceGroupDeployment `
    -ResourceGroupName $resourceGroup `
    -TemplateFile $BicepFile `
    -TemplateParameterFile $ParameterFile `
    -deployMode $DeployMode `
    -acrLoginServer $acrLoginServer `
    -acrId $acrId `
    -postgresName $postgresName `
    -postgresAdmin $postgresAdmin `
    -postgresPassword $postgresPassword

# Extract outputs
$webAppUrl      = $deployment.Outputs['webAppUrl'].Value
$dbConnString   = $deployment.Outputs['dbConnectionString'].Value

# Console
Write-Host "App Service URL: $webAppUrl"
Write-Host "DB Connection String: $dbConnString"

# File
$outputData = @{
    acrLoginServer   = $acrLoginServer
    acrId            = $acrId
    webAppUrl        = $webAppUrl
    dbConnectionString = $dbConnString
}
$outputPath = Join-Path $PSScriptRoot "outputs.$Environment.json"
$outputData | ConvertTo-Json | Out-File $outputPath -Encoding utf8

# Store DB connection string in Key Vault
Set-AzKeyVaultSecret -VaultName $config.vaultName -Name "dbConnectionString" -Value $dbConnString

# Get the App Service identity principal ID
$appService = Get-AzWebApp -ResourceGroupName $resourceGroup -Name $webAppName

# Assign Key Vault access to App Service managed identity
Set-AzKeyVaultAccessPolicy -VaultName $config.vaultName -ObjectId $appService.Identity.PrincipalId -PermissionsToSecrets get,list
