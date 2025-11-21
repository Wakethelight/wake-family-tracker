##not ready for production use##

[CmdletBinding()]
param(
    [ValidateSet("dev","prod")]
    [string]$Environment,

    [Parameter()]
    [string] $BicepFile = (Join-Path -Path $PSScriptRoot -ChildPath "bicep/acr.bicep"),

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
$acrName = $params.parameters.acrName.value

# Convert tags to hashtable
$tags = @{}
$config.Tags.PSObject.Properties | ForEach-Object {
    $tags[$_.Name] = $_.Value
}

# Build ACR resource group name
$acrResourceGroup = "$($config.ResourceGroupPrefix)-$acrName"
Write-Host "Deploying ACR to Resource Group: $acrResourceGroup in $Environment environment"

# Create ACR RG if not exists
if (-not (Get-AzResourceGroup -Name $acrResourceGroup -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $acrResourceGroup -Location $config.DefaultLocation -Tag $tags
}

# Deploy ACR with Bicep
$deployment = New-AzResourceGroupDeployment `
    -ResourceGroupName $acrResourceGroup `
    -TemplateFile $BicepFile `
    -TemplateParameterFile $ParameterFile

# Extract outputs
$acrLoginServer = $deployment.Outputs['acrLoginServer'].Value
$acrId          = $deployment.Outputs['acrId'].Value

# Console
Write-Host "ACR Login Server: $acrLoginServer"
Write-Host "ACR Resource ID: $acrId"

# File
$outputData = @{
    acrLoginServer = $acrLoginServer
    acrId          = $acrId
}
$outputPath = Join-Path $PSScriptRoot "outputs.$Environment.json"
$outputData | ConvertTo-Json | Out-File $outputPath -Encoding utf8

# Key Vault
Set-AzKeyVaultSecret -VaultName $config.vaultName.value -Name "acrLoginServer" -Value $acrLoginServer
Set-AzKeyVaultSecret -VaultName $config.vaultName.value -Name "acrId" -Value $acrId