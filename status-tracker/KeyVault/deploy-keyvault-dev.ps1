# Connect to Azure
Connect-AzAccount

# Get the folder where the script lives
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Paths relative to script location
$bicepFile = Join-Path $scriptDir "bicep/keyvault.bicep"
$parameterFile = Join-Path $scriptDir "bicep/params/dev.json"

# Read parameter file
$params = Get-Content $parameterFile | ConvertFrom-Json

# Extract values
$vaultName = $params.parameters.vaultName.value
$location = $params.parameters.location.value

# Build vault resource group name
$vaultResourceGroup = "rg-$vaultName"

Write-Host "Deploying KeyVault to Resource Group: $vaultResourceGroup"

# Create KeyVault resource group if not exists
if (-not (Get-AzResourceGroup -Name $vaultResourceGroup -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $vaultResourceGroup -Location $location
}

# Deploy keyvault Bicep template
az deployment group create `
    --resource-group $vaultResourceGroup `
    --template-file $bicepFile `
    --parameters $parameterFile