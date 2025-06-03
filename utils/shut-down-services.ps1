# Azure Trading Services - Daily Shutdown Script
# Stops billable services to save costs during development
# Services will NOT auto-start - you must manually start them when needed

param(
    [string]$ResourceGroup = "rg-trading-hero",
    [string]$ConfigFile = "azure-trading-config-*.txt",
    [switch]$Force = $false,
    [switch]$WhatIf = $false
)

# Colors for output
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    $args | Write-Output
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-Host "=== Azure Trading Services Shutdown Script ===" -ForegroundColor Cyan
Write-Host "This will stop billable services to save costs" -ForegroundColor Yellow

if ($WhatIf) {
    Write-Host "`nWHAT-IF MODE: No changes will be made" -ForegroundColor Yellow
}

# Check Azure login
try {
    $account = az account show 2>$null | ConvertFrom-Json
    Write-Host "`nLogged in as: $($account.user.name)" -ForegroundColor Green
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
}

# Services that can be stopped
$stoppableServices = @()
$alwaysOnServices = @()
$savingsEstimate = 0

Write-Host "`n=== Checking Services ===" -ForegroundColor Cyan

# 1. Check Azure Data Explorer (Biggest cost)
if ($AdxClusterName -and $AdxClusterName -ne "Not Created") {
    Write-Host "`n1. Azure Data Explorer Cluster: $AdxClusterName" -ForegroundColor Yellow
    try {
        $adxState = az kusto cluster show `
            --name $AdxClusterName `
            --resource-group $ResourceGroup `
            --query "state" -o tsv 2>$null
        
        if ($adxState -eq "Running") {
            Write-Host "   Status: Running" -ForegroundColor Green
            Write-Host "   Daily Cost: ~$4.50" -ForegroundColor Yellow
            $stoppableServices += [PSCustomObject]@{
                Type = "ADX Cluster"
                Name = $AdxClusterName
                Status = "Running"
                DailyCost = 4.50
            }
            $savingsEstimate += 4.50
        } else {
            Write-Host "   Status: $adxState" -ForegroundColor Gray
        }
    } catch {
        Write-Host "   Status: Not found" -ForegroundColor Red
    }
} else {
    Write-Host "`n1. Azure Data Explorer: Not configured" -ForegroundColor Gray
}

# 2. Check Container Apps
Write-Host "`n2. Container Apps Environment: $ContainerAppEnv" -ForegroundColor Yellow
if ($ContainerAppEnv -and $ContainerAppEnv -ne "Not Created") {
    try {
        # List all container apps in the environment
        $containerApps = az containerapp list `
            --resource-group $ResourceGroup `
            --query "[?properties.environmentId.contains('$ContainerAppEnv')].{name:name, replicas:properties.template.scale.minReplicas}" `
            2>$null | ConvertFrom-Json
        
        if ($containerApps.Count -gt 0) {
            foreach ($app in $containerApps) {
                if ($app.replicas -gt 0) {
                    Write-Host "   App: $($app.name) - Running ($($app.replicas) replicas)" -ForegroundColor Green
                    $stoppableServices += [PSCustomObject]@{
                        Type = "Container App"
                        Name = $app.name
                        Status = "Running"
                        DailyCost = 0.50  # Rough estimate per app
                    }
                    $savingsEstimate += 0.50
                } else {
                    Write-Host "   App: $($app.name) - Already stopped" -ForegroundColor Gray
                }
            }
        } else {
            Write-Host "   No container apps found" -ForegroundColor Gray
        }
    } catch {
        Write-Host "   Container Apps not found" -ForegroundColor Red
    }
} else {
    Write-Host "   Container Apps: Not configured" -ForegroundColor Gray
}

# 3. Services that are always on (can't be stopped)
Write-Host "`n3. Always-On Services (cannot be stopped):" -ForegroundColor Yellow
$alwaysOnServices = @(
    @{Service="SQL Database (Basic/S0)"; Note="Billed even when idle"; DailyCost=0.16},
    @{Service="Redis Cache (Basic)"; Note="Cannot be stopped"; DailyCost=0.53},
    @{Service="Storage Account"; Note="Pay for storage used"; DailyCost=0.07},
    @{Service="Container Registry"; Note="Pay for storage used"; DailyCost=0.16},
    @{Service="Key Vault"; Note="Pay per operation"; DailyCost=0.01}
)

foreach ($service in $alwaysOnServices) {
    Write-Host "   - $($service.Service): $($service.Note)" -ForegroundColor Gray
}

$alwaysOnCost = ($alwaysOnServices | Measure-Object -Property DailyCost -Sum).Sum

# Show summary
Write-Host "`n=== Cost Summary ===" -ForegroundColor Cyan
Write-Host "Stoppable services daily cost: `$$([math]::Round($savingsEstimate, 2))" -ForegroundColor Yellow
Write-Host "Always-on services daily cost: `$$([math]::Round($alwaysOnCost, 2))" -ForegroundColor Gray
Write-Host "Total potential daily savings: `$$([math]::Round($savingsEstimate, 2))" -ForegroundColor Green

if ($stoppableServices.Count -eq 0) {
    Write-Host "`nNo services to stop. All stoppable services are already stopped." -ForegroundColor Green
    exit 0
}

# Confirm shutdown
if (-not $Force -and -not $WhatIf) {
    Write-Host "`nServices to stop:" -ForegroundColor Yellow
    $stoppableServices | Format-Table Type, Name, Status, @{L="Daily Cost";E={"`$$($_.DailyCost)"}} -AutoSize
    
    $response = Read-Host "`nDo you want to stop these services? (Y/N)"
    if ($response -ne 'Y' -and $response -ne 'y') {
        Write-Host "Shutdown cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Add robust shutdown retry logic for up to 30 minutes
$maxAttempts = 30
$attempt = 0
$allStopped = $false
while (-not $allStopped -and $attempt -lt $maxAttempts) {
    $attempt++
    Write-Host "\nShutdown attempt $attempt..." -ForegroundColor Yellow
    # Shutdown services
    Write-Host "`n=== Shutting Down Services ===" -ForegroundColor Cyan

    # Stop ADX Cluster
    $adxService = $stoppableServices | Where-Object { $_.Type -eq "ADX Cluster" }
    if ($adxService) {
        Write-Host "`nStopping Azure Data Explorer..." -ForegroundColor Yellow
        if (-not $WhatIf) {
            az kusto cluster stop `
                --name $adxService.Name `
                --resource-group $ResourceGroup `
                --no-wait 2>$null
            Write-Host "✓ ADX stop command sent (takes 5-10 minutes to complete)" -ForegroundColor Green
        } else {
            Write-Host "Would stop ADX Cluster: $($adxService.Name)" -ForegroundColor Gray
        }
    }

    # Stop Container Apps
    $containerAppServices = $stoppableServices | Where-Object { $_.Type -eq "Container App" }
    if ($containerAppServices) {
        Write-Host "`nStopping Container Apps..." -ForegroundColor Yellow
        foreach ($app in $containerAppServices) {
            if (-not $WhatIf) {
                Write-Host "  Stopping $($app.Name)..." -NoNewline
                az containerapp scale `
                    --name $app.Name `
                    --resource-group $ResourceGroup `
                    --min-replicas 0 `
                    --max-replicas 0 2>$null
                Write-Host " Done" -ForegroundColor Green
            } else {
                Write-Host "Would stop Container App: $($app.Name)" -ForegroundColor Gray
            }
        }
    }

    # Save shutdown log
    if (-not $WhatIf) {
        $logEntry = @{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Action = "Shutdown"
            ServicesStopped = $stoppableServices.Count
            EstimatedDailySavings = $savingsEstimate
            User = $account.user.name
        }
        
        $logFile = "azure-shutdown-log.json"
        if (Test-Path $logFile) {
            $logs = Get-Content $logFile | ConvertFrom-Json
            if ($logs -isnot [System.Collections.IEnumerable]) {
                $logs = @($logs)
            }
            $logs += $logEntry
        } else {
            $logs = @($logEntry)
        }
        $logs | ConvertTo-Json -Depth 3 | Out-File $logFile
        Write-Host "`nShutdown logged to: $logFile" -ForegroundColor Gray
    }

    # After attempting to stop services, check status
    $stillRunning = @()
    # Check ADX
    if ($AdxClusterName -and $AdxClusterName -ne "Not Created") {
        $adxState = az kusto cluster show --name $AdxClusterName --resource-group $ResourceGroup --query state -o tsv 2>$null
        if ($adxState -eq "Running") { $stillRunning += "ADXCluster:$AdxClusterName" }
    }
    # Check Redis
    if ($RedisName -and $RedisName -ne "Not Created") {
        $redisState = az redis show --name $RedisName --resource-group $ResourceGroup --query provisioningState -o tsv 2>$null
        if ($redisState -eq "Succeeded") { $stillRunning += "Redis:$RedisName" }
    }
    # Check SQL
    if ($SqlServerName -and $SqlServerName -ne "Not Created") {
        # SQL can't be stopped, skip
    }
    # Check Container Apps
    if ($ContainerAppEnv -and $ContainerAppEnv -ne "Not Created") {
        $json = az containerapp list --resource-group $ResourceGroup --query "[?properties.environmentId.contains('$ContainerAppEnv')]" 2>$null
        if ($json -and $json.Trim().StartsWith('[')) {
            $apps = $json | ConvertFrom-Json
        } else {
            $apps = @()
        }
        foreach ($app in $apps) {
            $replicas = $app.properties.template.scale.minReplicas
            if ($replicas -gt 0) { $stillRunning += "ContainerApp:$($app.name)" }
        }
    }
    if ($stillRunning.Count -eq 0) {
        $allStopped = $true
        Write-Host "\nAll services are stopped!" -ForegroundColor Green
    } else {
        Write-Host "\nStill running: $($stillRunning -join ', ')" -ForegroundColor Red
        if ($attempt -lt $maxAttempts) {
            Write-Host "Retrying shutdown in 60 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 60
            # Re-run shutdown logic for any still running
            # (You may want to re-invoke the shutdown commands here if needed)
        } else {
            Write-Host "\nSome services could not be stopped after $maxAttempts attempts." -ForegroundColor Red
        }
    }
}

# Final summary
Write-Host "`n=== Shutdown Complete ===" -ForegroundColor Green
Write-Host "Services have been stopped to save costs." -ForegroundColor Green
Write-Host "Estimated daily savings: `$$([math]::Round($savingsEstimate, 2))" -ForegroundColor Yellow
Write-Host "`nTo start services again, use the Start-AzureServices.ps1 script" -ForegroundColor Cyan
Write-Host "or start them manually when needed for development." -ForegroundColor Cyan

# Create a simple start script if it doesn't exist
$startScriptContent = @'
# Quick Start Script for Azure Trading Services
param([string]$ResourceGroup = "rg-trading-hero")

Write-Host "=== Starting Azure Trading Services ===" -ForegroundColor Green

# Start ADX (if needed)
$adxName = Read-Host "Enter ADX Cluster name (or press Enter to skip)"
if ($adxName) {
    Write-Host "Starting ADX Cluster..." -ForegroundColor Yellow
    az kusto cluster start --name $adxName --resource-group $ResourceGroup --no-wait
    Write-Host "ADX start command sent (takes 5-10 minutes)" -ForegroundColor Green
}

# Start Container Apps
$appName = Read-Host "Enter Container App name (or press Enter to skip)"
if ($appName) {
    Write-Host "Starting Container App..." -ForegroundColor Yellow
    az containerapp scale --name $appName --resource-group $ResourceGroup --min-replicas 1 --max-replicas 3
    Write-Host "Container App started" -ForegroundColor Green
}

Write-Host "`nServices starting up!" -ForegroundColor Green
'@

if (-not (Test-Path "Start-AzureServices.ps1")) {
    $startScriptContent | Out-File "Start-AzureServices.ps1"
    Write-Host "`nCreated Start-AzureServices.ps1 for when you need to restart services" -ForegroundColor Green
}