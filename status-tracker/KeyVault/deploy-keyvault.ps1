[CmdletBinding()]
param(
    [ValidateSet("dev","prod")]
    [string]$Environment,

    [Parameter()]
    [string] $BicepFile = (Join-Path -Path $PSScriptRoot -ChildPath "bicep/keyvault.bicep"),

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
$vaultName = $params.parameters.vaultName.value
$location  = $params.parameters.location.value

# Convert tags to hashtable
$tags = @{}
$config.Tags.PSObject.Properties | ForEach-Object {
    $tags[$_.Name] = $_.Value
}

# Build vault resource group name
$vaultResourceGroup = "$($config.ResourceGroupPrefix)-$vaultName"
Write-Host "Deploying KeyVault to Resource Group: $vaultResourceGroup in $Environment environment"

# Create RG if not exists
if (-not (Get-AzResourceGroup -Name $vaultResourceGroup -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $vaultResourceGroup -Location $config.DefaultLocation -Tag $tags
}

# Deploy KeyVault with Bicep
New-AzResourceGroupDeployment `
    -ResourceGroupName $vaultResourceGroup `
    -TemplateFile $BicepFile `
    -TemplateParameterFile $ParameterFile
