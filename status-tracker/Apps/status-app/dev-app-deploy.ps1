# Connect to Azure
Connect-AzAccount

# Paths
$templateFile = "./bicep/main.bicep"
$parameterFile = "./bicep/params/dev.json"

# Read parameter file
$params = Get-Content $parameterFile | ConvertFrom-Json

# Extract values
$environment = $params.parameters.environment.value
$appName = $params.parameters.appName.value
$location = $params.parameters.location.value
$acrLoginServer = $params.parameters.acrLoginServer.value

# Derive ACR name from login server (e.g., acr-mycompany-dev.azurecr.io -> acr-mycompany-dev)
$acrName = $acrLoginServer.Split('.')[0]

# Build dynamic resource group name for app
$appResourceGroup = "rg-$appName-$environment"

Write-Host "Checking if ACR '$acrName' exists before deploying App Service..."

# Check if ACR exists
$acr = Get-AzContainerRegistry -Name $acrName -ErrorAction SilentlyContinue
if (-not $acr) {
    Write-Host "ERROR: Azure Container Registry '$acrName' does not exist. Please deploy ACR first." -ForegroundColor Red
    exit 1
}

Write-Host "ACR exists. Proceeding with App Service deployment..."

# Create app resource group if not exists
if (-not (Get-AzResourceGroup -Name $appResourceGroup -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $appResourceGroup -Location $location
}

# Deploy App Bicep template
New-AzResourceGroupDeployment `
    -ResourceGroupName $appResourceGroup `
    -TemplateFile $templateFile `
    -TemplateParameterFile $parameterFile