[CmdletBinding()]
param()

# Variables
$spName        = "sp-deployment"
$subscriptionId = "bb8f3354-1ce0-4efc-b2a7-8506304c5362"
$tenantId       = "a5dea08c-0cc9-40d8-acaa-cacf723e7b9b"
$outputPath     = Join-Path $PSScriptRoot "sp-deployment-credentials.json"
$rotationDays   = 90   # threshold for reminder

# 👉 Add your Key Vault name here
$vaultName      = "kv-wake-dev"
$secretName     = "sp-deployment-secret"

# Login to Azure (non-interactive)
az login --tenant $tenantId --allow-no-subscriptions
az account set --subscription $subscriptionId

# Check if SP already exists
$existingSp = az ad sp list --display-name $spName | ConvertFrom-Json

if ($existingSp.Count -gt 0) {
    Write-Host "Service principal '$spName' already exists."

    $lastReset = $null
    $daysSince = $null
    if (Test-Path $outputPath) {
        $existingCreds = Get-Content $outputPath | ConvertFrom-Json
        if ($existingCreds.lastReset) {
            $lastReset = [DateTime]::Parse($existingCreds.lastReset)
            $daysSince = (New-TimeSpan -Start $lastReset -End (Get-Date)).Days
            Write-Host "Last reset was $daysSince days ago (on $lastReset)."
        }
    }

    # Build prompt message with rotation policy check
    $promptMsg = "Do you want to force reset the secret"
    if ($lastReset) {
        $promptMsg += " (last reset: $lastReset, $daysSince days ago)"
        if ($daysSince -ge $rotationDays) {
            $promptMsg += " — strongly recommended to rotate"
        }
    }
    $promptMsg += "? (Y/N, default=N): "

    $choice = Read-Host $promptMsg

    if ($choice -eq "Y") {
        Write-Host "Force reset requested. Resetting secret..."
        $reset = az ad sp credential reset --id 3e7f72f0-5bb1-4e1e-9ab9-f1ebf9e40273 | ConvertFrom-Json
        $clientSecret = $reset.password
        $lastReset = (Get-Date).ToString("o")

        # 👉 Push new secret to Key Vault
        $clientSecretSecure = ConvertTo-SecureString $clientSecret -AsPlainText -Force
        Set-AzKeyVaultSecret -VaultName $vaultName -Name $secretName -SecretValue $clientSecretSecure
        Write-Host "Updated Key Vault '$vaultName' secret '$secretName'."
    }
    else {
        Write-Host "Keeping existing secret."
        $clientSecret = "<EXISTING-SECRET-NOT-RETRIEVABLE>"
        if (-not $lastReset) { $lastReset = (Get-Date).ToString("o") }
    }

    # Build JSON
    $spCredentials = @{
        clientId        = $existingSp[0].appId
        clientSecret    = $clientSecret
        subscriptionId  = $subscriptionId
        tenantId        = $tenantId
        activeDirectoryEndpointUrl     = "https://login.microsoftonline.com"
        resourceManagerEndpointUrl     = "https://management.azure.com/"
        activeDirectoryGraphResourceId = "https://graph.windows.net/"
        sqlManagementEndpointUrl       = "https://management.core.windows.net:8443/"
        galleryEndpointUrl             = "https://gallery.azure.com/"
        managementEndpointUrl          = "https://management.core.windows.net/"
        lastReset       = $lastReset
    }

    $spCredentials | ConvertTo-Json -Depth 10 | Out-File $outputPath -Encoding utf8
    Write-Host "Credentials saved to $outputPath"
}
else {
    Write-Host "Creating new service principal '$spName'..."

    $sp = az ad sp create-for-rbac `
      --name $spName `
      --role Contributor `
      --scopes /subscriptions/$subscriptionId `
      | ConvertFrom-Json

    $spCredentials = @{
        clientId        = $sp.appId
        clientSecret    = $sp.password
        subscriptionId  = $subscriptionId
        tenantId        = $tenantId
        activeDirectoryEndpointUrl     = "https://login.microsoftonline.com"
        resourceManagerEndpointUrl     = "https://management.azure.com/"
        activeDirectoryGraphResourceId = "https://graph.windows.net/"
        sqlManagementEndpointUrl       = "https://management.core.windows.net:8443/"
        galleryEndpointUrl             = "https://gallery.azure.com/"
        managementEndpointUrl          = "https://management.core.windows.net/"
        lastReset       = (Get-Date).ToString("o")
    }

    $spCredentials | ConvertTo-Json -Depth 10 | Out-File $outputPath -Encoding utf8

    Write-Host "Service principal created: $spName"
    Write-Host "Credentials saved to $outputPath"
    Write-Host "Last reset timestamp: $($spCredentials.lastReset)"

    # 👉 Push initial secret to Key Vault
    $clientSecretSecure = ConvertTo-SecureString $sp.password -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $vaultName -Name $secretName -SecretValue $clientSecretSecure
    Write-Host "Stored new secret in Key Vault '$vaultName' under name '$secretName'."
}
