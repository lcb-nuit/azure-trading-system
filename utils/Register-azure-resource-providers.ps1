# Azure Resource Provider Registration Script
# Run this BEFORE the initialization script

Write-Host "=== Registering Required Azure Resource Providers ===" -ForegroundColor Cyan
Write-Host "This may take a few minutes..." -ForegroundColor Yellow

# List of required providers for trading system
$providers = @(
    "Microsoft.ContainerRegistry",
    "Microsoft.KeyVault",
    "Microsoft.Kusto",
    "Microsoft.Cache",
    "Microsoft.Sql",
    "Microsoft.App",
    "Microsoft.OperationalInsights",
    "Microsoft.Storage",
    "Microsoft.Network",
    "Microsoft.Compute"
)

# Register each provider
foreach ($provider in $providers) {
    Write-Host "`nRegistering $provider..." -ForegroundColor Yellow
    try {
        az provider register --namespace $provider --wait
        Write-Host "✓ $provider registered successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Failed to register $provider" -ForegroundColor Red
    }
}

# Check registration status
Write-Host "`n=== Checking Registration Status ===" -ForegroundColor Cyan
az provider list --query "[?contains(namespace, 'Microsoft.')].{Provider:namespace, Status:registrationState}" --output table | Select-String -Pattern ($providers -join "|")

Write-Host "`n✓ All providers registered! You can now run the initialization script." -ForegroundColor Green