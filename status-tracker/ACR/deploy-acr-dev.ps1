# Connect to Azure
Connect-AzAccount

# Paths
$templateFile = "./bicep/acr.bicep"
$parameterFile = "./bicep/params/dev.json"

# Read parameter file
$params = Get-Content $parameterFile | ConvertFrom-Json

# Extract values
$acrName = $params.parameters.acrName.value
$location = $params.parameters.location.value

# Build ACR resource group name
$acrResourceGroup = "rg-$acrName"

Write-Host "Deploying ACR to Resource Group: $acrResourceGroup"

# Create ACR resource group if not exists
if (-not (Get-AzResourceGroup -Name $acrResourceGroup -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $acrResourceGroup -Location $location
}

# Deploy ACR Bicep template
New-AzResourceGroupDeployment `
    -ResourceGroupName $acrResourceGroup `
    -TemplateFile $templateFile `
    -TemplateParameterFile $parameterFile