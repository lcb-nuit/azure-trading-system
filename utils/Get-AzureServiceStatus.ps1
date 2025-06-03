# Azure Trading Services - Comprehensive Status Checker
# Shows the status of all services created by the initialization script

param(
    [string]$ResourceGroup = "rg-trading-hero",
    [string]$ConfigFile = "azure-trading-config-*.txt",
    [switch]$ShowCosts = $true,
    [switch]$ShowUrls = $false,
    [switch]$ExportToJson = $false
)

# Colors for output
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    $args | Write-Output
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-Host "=== Azure Trading Services Status Checker ===" -ForegroundColor Cyan
Write-Host "Checking all services in resource group: $ResourceGroup" -ForegroundColor Yellow
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# Check Azure login
try {
    $account = az account show 2>$null | ConvertFrom-Json
    Write-Host "Azure Account: $($account.user.name)" -ForegroundColor Gray
} catch {
    Write-ColorOutput Red "Not logged in to Azure. Please run: az login"
    exit 1
}

# Load config from latest azure-trading-config-*.txt if present
$configFiles = Get-ChildItem -Path "azure-trading-config-*.txt" -ErrorAction SilentlyContinue
if ($configFiles.Count -gt 0) {
    $latestConfig = $configFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host "Loaded config: $($latestConfig.Name)" -ForegroundColor Gray
    $config = @{}
    Get-Content $latestConfig | ForEach-Object {
        if ($_ -match "^([A-Za-z0-9_\-]+)\s*=\s*(.+)$") {
            $key = $matches[1].Trim()
            $val = $matches[2].Trim('"').Trim()
            $config[$key] = $val
        }
    }
    if ($config["ResourceGroup"]) { $ResourceGroup = $config["ResourceGroup"] }
    if ($config["StorageAccount"]) { $StorageAccountName = $config["StorageAccount"] }
    if ($config["ContainerRegistry"]) { $AcrName = $config["ContainerRegistry"] }
    if ($config["KeyVault"]) { $KeyVaultName = $config["KeyVault"] }
    if ($config["ADXCluster"]) { $AdxClusterName = $config["ADXCluster"] }
    if ($config["ADXDatabase"]) { $AdxDatabaseName = $config["ADXDatabase"] }
    if ($config["RedisCache"]) { $RedisName = $config["RedisCache"] }
    if ($config["SQLServer"]) { $SqlServerName = $config["SQLServer"] }
    if ($config["SQLDatabase"]) { $SqlDatabaseName = $config["SQLDatabase"] }
    if ($config["ContainerAppsEnv"]) { $ContainerAppEnv = $config["ContainerAppsEnv"] }
} else {
    Write-Host "No configuration file found. Using defaults." -ForegroundColor Yellow
}

# Service status tracking
$serviceStatuses = @()
$runningCost = 0
$stoppedCost = 0

Write-Host "`n" + "="*60 -ForegroundColor DarkGray

# 1. Resource Group
Write-Host "`n📁 RESOURCE GROUP" -ForegroundColor Cyan
$rgExists = az group show --name $ResourceGroup 2>$null
if ($rgExists) {
    $rg = $rgExists | ConvertFrom-Json
    Write-Host "   ✓ $ResourceGroup - EXISTS" -ForegroundColor Green
    Write-Host "   Location: $($rg.location)" -ForegroundColor Gray
} else {
    Write-Host "   ✗ $ResourceGroup - NOT FOUND" -ForegroundColor Red
    exit 1
}

# 2. Storage Account
Write-Host "`n💾 STORAGE ACCOUNT" -ForegroundColor Cyan
if ($StorageAccountName -and $StorageAccountName -ne "Not Created") {
    try {
        $storage = az storage account show --name $StorageAccountName --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
        Write-Host "   ✓ $StorageAccountName - ACTIVE" -ForegroundColor Green
        Write-Host "   SKU: $($storage.sku.name)" -ForegroundColor Gray
        if ($ShowUrls) {
            Write-Host "   Blob: https://$StorageAccountName.blob.core.windows.net/" -ForegroundColor Gray
        }
        $serviceStatuses += [PSCustomObject]@{
            Service = "Storage Account"
            Name = $StorageAccountName
            Status = "Active"
            DailyCost = 0.07
        }
        $runningCost += 0.07
    } catch {
        Write-Host "   ✗ $StorageAccountName - NOT FOUND" -ForegroundColor Red
    }
} else {
    Write-Host "   - Not configured" -ForegroundColor Gray
}

# 3. Container Registry
Write-Host "`n🐳 CONTAINER REGISTRY" -ForegroundColor Cyan
if ($AcrName -and $AcrName -ne "Not Created") {
    try {
        $acr = az acr show --name $AcrName --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
        Write-Host "   ✓ $AcrName - ACTIVE" -ForegroundColor Green
        Write-Host "   SKU: $($acr.sku.name)" -ForegroundColor Gray
        if ($ShowUrls) {
            Write-Host "   URL: $AcrName.azurecr.io" -ForegroundColor Gray
        }
        $serviceStatuses += [PSCustomObject]@{
            Service = "Container Registry"
            Name = $AcrName
            Status = "Active"
            DailyCost = 0.16
        }
        $runningCost += 0.16
    } catch {
        Write-Host "   ✗ $AcrName - NOT FOUND" -ForegroundColor Red
    }
} else {
    Write-Host "   - Not configured" -ForegroundColor Gray
}

# 4. Key Vault
Write-Host "`n🔐 KEY VAULT" -ForegroundColor Cyan
if ($KeyVaultName -and $KeyVaultName -ne "Not Created") {
    try {
        $kv = az keyvault show --name $KeyVaultName --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
        Write-Host "   ✓ $KeyVaultName - ACTIVE" -ForegroundColor Green
        
        # Count secrets
        $secretCount = (az keyvault secret list --vault-name $KeyVaultName --query "length(@)" -o tsv 2>$null)
        Write-Host "   Secrets: $secretCount" -ForegroundColor Gray
        if ($ShowUrls) {
            Write-Host "   URI: $($kv.properties.vaultUri)" -ForegroundColor Gray
        }
        $serviceStatuses += [PSCustomObject]@{
            Service = "Key Vault"
            Name = $KeyVaultName
            Status = "Active"
            DailyCost = 0.01
        }
        $runningCost += 0.01
    } catch {
        Write-Host "   ✗ $KeyVaultName - NOT FOUND" -ForegroundColor Red
    }
} else {
    Write-Host "   - Not configured" -ForegroundColor Gray
}

# 5. Azure Data Explorer
Write-Host "`n📊 AZURE DATA EXPLORER" -ForegroundColor Cyan
if ($AdxClusterName -and $AdxClusterName -ne "Not Created") {
    try {
        $adx = az kusto cluster show --name $AdxClusterName --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
        $adxState = $adx.state
        $statusColor = if ($adxState -eq "Running") { "Green" } elseif ($adxState -eq "Stopped") { "Yellow" } else { "Red" }
        
        Write-Host "   $(if ($adxState -eq 'Running') {'✓'} else {'○'}) $AdxClusterName - $adxState" -ForegroundColor $statusColor
        Write-Host "   SKU: $($adx.sku.name)" -ForegroundColor Gray
        
        $dailyCost = if ($adxState -eq "Running") { 4.50 } else { 0 }
        $serviceStatuses += [PSCustomObject]@{
            Service = "ADX Cluster"
            Name = $AdxClusterName
            Status = $adxState
            DailyCost = $dailyCost
        }
        
        if ($adxState -eq "Running") {
            $runningCost += 4.50
        } else {
            $stoppedCost += 4.50
        }
        
        # Check database
        if ($AdxDatabaseName -and $AdxDatabaseName -ne "Not Created") {
            try {
                $db = az kusto database show --cluster-name $AdxClusterName --database-name $AdxDatabaseName --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
                Write-Host "   Database: $AdxDatabaseName" -ForegroundColor Gray
            } catch {
                Write-Host "   Database: Not found" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "   ✗ $AdxClusterName - NOT FOUND" -ForegroundColor Red
    }
} else {
    Write-Host "   - Not configured" -ForegroundColor Gray
}

# 6. Redis Cache
Write-Host "`n🔴 REDIS CACHE" -ForegroundColor Cyan
if ($RedisName -and $RedisName -ne "Not Created") {
    try {
        $redis = az redis show --name $RedisName --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
        $provisioningState = $redis.provisioningState
        $statusColor = if ($provisioningState -eq "Succeeded") { "Green" } else { "Yellow" }
        
        Write-Host "   ✓ $RedisName - $provisioningState" -ForegroundColor $statusColor
        Write-Host "   SKU: $($redis.sku.name) ($($redis.sku.capacity))" -ForegroundColor Gray
        if ($ShowUrls) {
            Write-Host "   Host: $($redis.hostName)" -ForegroundColor Gray
        }
        
        $serviceStatuses += [PSCustomObject]@{
            Service = "Redis Cache"
            Name = $RedisName
            Status = "Active"
            DailyCost = 0.53
        }
        $runningCost += 0.53
    } catch {
        Write-Host "   ✗ $RedisName - NOT FOUND" -ForegroundColor Red
    }
} else {
    Write-Host "   - Not configured" -ForegroundColor Gray
}

# 7. SQL Server & Database
Write-Host "`n🗄️  SQL SERVER" -ForegroundColor Cyan
if ($SqlServerName -and $SqlServerName -ne "Not Created") {
    try {
        $sqlServer = az sql server show --name $SqlServerName --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
        Write-Host "   ✓ $SqlServerName - ACTIVE" -ForegroundColor Green
        Write-Host "   State: $($sqlServer.state)" -ForegroundColor Gray
        if ($ShowUrls) {
            Write-Host "   FQDN: $($sqlServer.fullyQualifiedDomainName)" -ForegroundColor Gray
        }
        
        # Check database
        if ($SqlDatabaseName -and $SqlDatabaseName -ne "Not Created") {
            try {
                $sqlDb = az sql db show --name $SqlDatabaseName --server $SqlServerName --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
                Write-Host "   Database: $SqlDatabaseName - $($sqlDb.status)" -ForegroundColor Green
                Write-Host "   Edition: $($sqlDb.edition) (S$($sqlDb.currentServiceObjectiveName))" -ForegroundColor Gray
                
                $serviceStatuses += [PSCustomObject]@{
                    Service = "SQL Database"
                    Name = "$SqlServerName/$SqlDatabaseName"
                    Status = $sqlDb.status
                    DailyCost = 0.16
                }
                $runningCost += 0.16
            } catch {
                Write-Host "   Database: Not found" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "   ✗ $SqlServerName - NOT FOUND" -ForegroundColor Red
    }
} else {
    Write-Host "   - Not configured" -ForegroundColor Gray
}

# 8. Container Apps Environment
Write-Host "`n📦 CONTAINER APPS" -ForegroundColor Cyan
if ($ContainerAppEnv -and $ContainerAppEnv -ne "Not Created") {
    try {
        $env = az containerapp env show --name $ContainerAppEnv --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
        Write-Host "   ✓ Environment: $ContainerAppEnv - $($env.properties.provisioningState)" -ForegroundColor Green
        
        # List all container apps
        $apps = az containerapp list --resource-group $ResourceGroup --query "[?properties.environmentId.contains('$ContainerAppEnv')]" 2>$null | ConvertFrom-Json
        
        if ($apps.Count -gt 0) {
            Write-Host "   Apps:" -ForegroundColor Yellow
            foreach ($app in $apps) {
                $replicas = $app.properties.template.scale.minReplicas
                $status = if ($replicas -gt 0) { "RUNNING" } else { "STOPPED" }
                $statusColor = if ($replicas -gt 0) { "Green" } else { "Yellow" }
                $icon = if ($replicas -gt 0) { "✓" } else { "○" }
                
                Write-Host "     $icon $($app.name) - $status ($replicas replicas)" -ForegroundColor $statusColor
                
                if ($ShowUrls -and $app.properties.configuration.ingress.fqdn) {
                    Write-Host "       URL: https://$($app.properties.configuration.ingress.fqdn)" -ForegroundColor Gray
                }
                
                $dailyCost = if ($replicas -gt 0) { 0.50 } else { 0 }
                $serviceStatuses += [PSCustomObject]@{
                    Service = "Container App"
                    Name = $app.name
                    Status = $status
                    DailyCost = $dailyCost
                }
                
                if ($replicas -gt 0) {
                    $runningCost += 0.50
                } else {
                    $stoppedCost += 0.50
                }
            }
        } else {
            Write-Host "   No apps deployed" -ForegroundColor Gray
        }
    } catch {
        Write-Host "   ✗ $ContainerAppEnv - NOT FOUND" -ForegroundColor Red
    }
} else {
    Write-Host "   - Not configured" -ForegroundColor Gray
}

# 9. Service Principal
Write-Host "`n👤 SERVICE PRINCIPAL" -ForegroundColor Cyan
$SpName = $config["ServicePrincipal"]
if ($SpName -and $SpName -ne "Not Created") {
    try {
        $sp = az ad sp list --display-name $SpName --query "[0]" 2>$null | ConvertFrom-Json
        if ($sp) {
            Write-Host "   ✓ $SpName - ACTIVE" -ForegroundColor Green
            Write-Host "   App ID: $($sp.appId)" -ForegroundColor Gray
        } else {
            Write-Host "   ✗ $SpName - NOT FOUND" -ForegroundColor Red
        }
    } catch {
        Write-Host "   ✗ $SpName - ERROR" -ForegroundColor Red
    }
} else {
    Write-Host "   - Not configured" -ForegroundColor Gray
}

Write-Host "`n" + "="*60 -ForegroundColor DarkGray

# Cost Summary
if ($ShowCosts) {
    Write-Host "`n💰 COST SUMMARY (Daily)" -ForegroundColor Cyan
    Write-Host "   Running Services: `$$([math]::Round($runningCost, 2))/day" -ForegroundColor Green
    Write-Host "   Stopped Services: `$$([math]::Round($stoppedCost, 2))/day (potential)" -ForegroundColor Yellow
    Write-Host "   Monthly (30 days): `$$([math]::Round($runningCost * 30, 2))" -ForegroundColor White
    Write-Host "   Monthly (5.5hrs/day): `$$([math]::Round($runningCost * 30 * 0.229, 2))" -ForegroundColor Gray
}

# Service Summary
Write-Host "`n📊 SERVICE SUMMARY" -ForegroundColor Cyan
$runningCount = ($serviceStatuses | Where-Object { $_.Status -in @("Active", "RUNNING", "Running", "Online") }).Count
$stoppedCount = ($serviceStatuses | Where-Object { $_.Status -in @("STOPPED", "Stopped") }).Count
$totalCount = $serviceStatuses.Count

Write-Host "   Total Services: $totalCount" -ForegroundColor White
Write-Host "   Running: $runningCount" -ForegroundColor Green
Write-Host "   Stopped: $stoppedCount" -ForegroundColor Yellow

# Export to JSON if requested
if ($ExportToJson) {
    $report = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ResourceGroup = $ResourceGroup
        Services = $serviceStatuses
        CostSummary = @{
            DailyRunning = [math]::Round($runningCost, 2)
            DailyStopped = [math]::Round($stoppedCost, 2)
            Monthly247 = [math]::Round($runningCost * 30, 2)
            Monthly55Hours = [math]::Round($runningCost * 30 * 0.229, 2)
        }
        ServiceCounts = @{
            Total = $totalCount
            Running = $runningCount
            Stopped = $stoppedCount
        }
    }
    
    $jsonFile = "azure-status-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $report | ConvertTo-Json -Depth 3 | Out-File $jsonFile
    Write-Host "`n📄 Report exported to: $jsonFile" -ForegroundColor Green
}

Write-Host "`n" + "="*60 -ForegroundColor DarkGray
Write-Host "Status check completed at $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray