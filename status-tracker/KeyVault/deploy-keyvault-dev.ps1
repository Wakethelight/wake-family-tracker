# Connect to Azure
Connect-AzAccount

# Paths
$templateFile = "./bicep/keyvault.bicep"
$parameterFile = "./bicep/params/dev.json"

# Read parameter file
$params = Get-Content $parameterFile | ConvertFrom-Json

# Extract values
$vaultName = $params.parameters.acrName.value
$location = $params.parameters.location.value

# Build vault resource group name
$vaultResourceGroup = "rg-$vaultName"

Write-Host "Deploying KeyVault to Resource Group: $vaultResourceGroup"

# Create ACR resource group if not exists
if (-not (Get-AzResourceGroup -Name $vaultResourceGroup -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $vaultResourceGroup -Location $location
}

# Deploy ACR Bicep template
New-AzResourceGroupDeployment `
    -ResourceGroupName $vaultResourceGroup `
    -TemplateFile $templateFile `
    -TemplateParameterFile $parameterFile