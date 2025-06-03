# Azure Trading Services - Restart Script
# Starts previously stopped services for development work
# Provides options to start all or specific services

param(
    [string]$ResourceGroup = "rg-trading-hero",
    [string]$ConfigFile = "azure-trading-config-*.txt",
    [switch]$All = $false,
    [switch]$ADXOnly = $false,
    [switch]$ContainerAppsOnly = $false,
    [switch]$WhatIf = $false,
    [string[]]$SpecificApps = @()
)

# Colors for output
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    $args | Write-Output
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-Host "=== Azure Trading Services Restart Script ===" -ForegroundColor Cyan
Write-Host "Start your development services" -ForegroundColor Yellow

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

# Try to load configuration
$config = @{}
$configFiles = Get-ChildItem -Path $ConfigFile -ErrorAction SilentlyContinue
if ($configFiles.Count -gt 0) {
    $latestConfig = $configFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host "Loading config from: $($latestConfig.Name)" -ForegroundColor Gray
    
    Get-Content $latestConfig | ForEach-Object {
        if ($_ -match "^(\w+)\s*=\s*(.+)$") {
            $config[$matches[1]] = $matches[2].Trim('"')
        }
    }
}

# Get resource names
$AdxClusterName = $config["ADXCluster"]
$ContainerAppEnv = $config["ContainerAppsEnv"]

# Track what we're starting
$servicesToStart = @()
$estimatedDailyCost = 0

Write-Host "`n=== Checking Service Status ===" -ForegroundColor Cyan

# 1. Check Azure Data Explorer
$adxAvailable = $false
if ($AdxClusterName -and $AdxClusterName -ne "Not Created") {
    Write-Host "`n1. Azure Data Explorer Cluster: $AdxClusterName" -ForegroundColor Yellow
    try {
        $adxState = az kusto cluster show `
            --name $AdxClusterName `
            --resource-group $ResourceGroup `
            --query "state" -o tsv 2>$null
        
        Write-Host "   Current Status: $adxState" -ForegroundColor $(if ($adxState -eq "Running") { "Green" } else { "Gray" })
        
        if ($adxState -ne "Running") {
            $adxAvailable = $true
            if ($All -or $ADXOnly) {
                $servicesToStart += [PSCustomObject]@{
                    Type = "ADX Cluster"
                    Name = $AdxClusterName
                    Action = "Start"
                    DailyCost = 4.50
                    StartTime = "5-10 minutes"
                }
                $estimatedDailyCost += 4.50
            }
        }
    } catch {
        Write-Host "   Status: Not found" -ForegroundColor Red
    }
} else {
    Write-Host "`n1. Azure Data Explorer: Not configured" -ForegroundColor Gray
}

# 2. Check Container Apps
$containerAppsAvailable = @()
if ($ContainerAppEnv -and $ContainerAppEnv -ne "Not Created") {
    Write-Host "`n2. Container Apps:" -ForegroundColor Yellow
    try {
        $containerApps = az containerapp list `
            --resource-group $ResourceGroup `
            --query "[?properties.environmentId.contains('$ContainerAppEnv')].{name:name, replicas:properties.template.scale.minReplicas}" `
            2>$null | ConvertFrom-Json
        
        foreach ($app in $containerApps) {
            $status = if ($app.replicas -gt 0) { "Running" } else { "Stopped" }
            $color = if ($app.replicas -gt 0) { "Green" } else { "Gray" }
            Write-Host "   - $($app.name): $status" -ForegroundColor $color
            
            if ($app.replicas -eq 0) {
                $containerAppsAvailable += $app.name
                
                # Check if we should start this app
                $shouldStart = $false
                if ($All -or $ContainerAppsOnly) {
                    $shouldStart = $true
                } elseif ($SpecificApps -contains $app.name) {
                    $shouldStart = $true
                }
                
                if ($shouldStart) {
                    $servicesToStart += [PSCustomObject]@{
                        Type = "Container App"
                        Name = $app.name
                        Action = "Scale to 1 replica"
                        DailyCost = 0.50
                        StartTime = "< 1 minute"
                    }
                    $estimatedDailyCost += 0.50
                }
            }
        }
        
        if ($containerAppsAvailable.Count -eq 0) {
            Write-Host "   All apps are already running" -ForegroundColor Green
        }
    } catch {
        Write-Host "   Container Apps not found" -ForegroundColor Red
    }
} else {
    Write-Host "`n2. Container Apps: Not configured" -ForegroundColor Gray
}

# If no services to start based on parameters, show menu
if ($servicesToStart.Count -eq 0 -and -not $All -and -not $ADXOnly -and -not $ContainerAppsOnly -and $SpecificApps.Count -eq 0) {
    Write-Host "`n=== Select Services to Start ===" -ForegroundColor Cyan
    
    $menuOptions = @()
    $optionIndex = 1
    
    if ($adxAvailable) {
        Write-Host "$optionIndex. Azure Data Explorer (~`$4.50/day, 5-10 min to start)" -ForegroundColor Yellow
        $menuOptions += @{Index=$optionIndex; Type="ADX"; Name=$AdxClusterName; Cost=4.50; Time="5-10 minutes"}
        $optionIndex++
    }
    
    foreach ($appName in $containerAppsAvailable) {
        Write-Host "$optionIndex. Container App: $appName (~`$0.50/day, immediate)" -ForegroundColor Yellow
        $menuOptions += @{Index=$optionIndex; Type="ContainerApp"; Name=$appName; Cost=0.50; Time="< 1 minute"}
        $optionIndex++
    }
    
    if ($menuOptions.Count -gt 0) {
        Write-Host "$optionIndex. Start ALL stopped services" -ForegroundColor Green
        Write-Host "0. Cancel" -ForegroundColor Red
        
        $selection = Read-Host "`nSelect option(s) - comma separated for multiple (e.g., 1,3)"
        
        if ($selection -eq "0") {
            Write-Host "Cancelled." -ForegroundColor Yellow
            exit 0
        }
        
        $selections = $selection -split ',' | ForEach-Object { $_.Trim() }
        
        foreach ($sel in $selections) {
            if ($sel -eq [string]$optionIndex) {
                # Start all
                foreach ($option in $menuOptions) {
                    $servicesToStart += [PSCustomObject]@{
                        Type = $option.Type
                        Name = $option.Name
                        Action = if ($option.Type -eq "ADX") { "Start" } else { "Scale to 1 replica" }
                        DailyCost = $option.Cost
                        StartTime = $option.Time
                    }
                    $estimatedDailyCost += $option.Cost
                }
            } else {
                $option = $menuOptions | Where-Object { $_.Index -eq [int]$sel }
                if ($option) {
                    $servicesToStart += [PSCustomObject]@{
                        Type = $option.Type
                        Name = $option.Name
                        Action = if ($option.Type -eq "ADX") { "Start" } else { "Scale to 1 replica" }
                        DailyCost = $option.Cost
                        StartTime = $option.Time
                    }
                    $estimatedDailyCost += $option.Cost
                }
            }
        }
    } else {
        Write-Host "`nAll services are already running!" -ForegroundColor Green
        exit 0
    }
}

# Show what will be started
if ($servicesToStart.Count -eq 0) {
    Write-Host "`nNo services to start based on your selection." -ForegroundColor Yellow
    exit 0
}

Write-Host "`n=== Services to Start ===" -ForegroundColor Cyan
$servicesToStart | Format-Table Type, Name, Action, @{L="Daily Cost";E={"`$$($_.DailyCost)"}}, StartTime -AutoSize
Write-Host "Total additional daily cost: `$$([math]::Round($estimatedDailyCost, 2))" -ForegroundColor Yellow

# Confirm
if (-not $WhatIf) {
    $response = Read-Host "`nProceed with starting these services? (Y/N)"
    if ($response -ne 'Y' -and $response -ne 'y') {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Start services
Write-Host "`n=== Starting Services ===" -ForegroundColor Cyan

# Start ADX
$adxServices = $servicesToStart | Where-Object { $_.Type -eq "ADX Cluster" }
foreach ($adx in $adxServices) {
    Write-Host "`nStarting Azure Data Explorer: $($adx.Name)" -ForegroundColor Yellow
    if (-not $WhatIf) {
        az kusto cluster start `
            --name $adx.Name `
            --resource-group $ResourceGroup `
            --no-wait 2>$null
        Write-Host "✓ ADX start command sent" -ForegroundColor Green
        Write-Host "  ⏱️  This will take 5-10 minutes to complete" -ForegroundColor Gray
        Write-Host "  💡 You can start working on other tasks while ADX starts" -ForegroundColor Gray
    } else {
        Write-Host "Would start ADX Cluster: $($adx.Name)" -ForegroundColor Gray
    }
}

# Start Container Apps
$containerAppServices = $servicesToStart | Where-Object { $_.Type -eq "Container App" }
foreach ($app in $containerAppServices) {
    Write-Host "`nStarting Container App: $($app.Name)" -ForegroundColor Yellow
    if (-not $WhatIf) {
        az containerapp scale `
            --name $app.Name `
            --resource-group $ResourceGroup `
            --min-replicas 1 `
            --max-replicas 3 2>$null
        Write-Host "✓ Container App started (1-3 replicas)" -ForegroundColor Green
    } else {
        Write-Host "Would start Container App: $($app.Name)" -ForegroundColor Gray
    }
}

# Save startup log
if (-not $WhatIf -and $servicesToStart.Count -gt 0) {
    $logEntry = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Action = "Restart"
        ServicesStarted = $servicesToStart.Count
        Services = $servicesToStart | Select-Object Type, Name
        EstimatedDailyCost = $estimatedDailyCost
        User = $account.user.name
    }
    
    $logFile = "azure-startup-log.json"
    if (Test-Path $logFile) {
        $logs = Get-Content $logFile | ConvertFrom-Json
        $logs += $logEntry
    } else {
        $logs = @($logEntry)
    }
    
    $logs | ConvertTo-Json -Depth 3 | Out-File $logFile
}

# Status check commands
Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
Write-Host "Services are starting up!" -ForegroundColor Green

if ($adxServices.Count -gt 0) {
    Write-Host "`nTo check ADX status:" -ForegroundColor Yellow
    Write-Host "  az kusto cluster show --name $AdxClusterName --resource-group $ResourceGroup --query state -o tsv" -ForegroundColor Gray
}

if ($containerAppServices.Count -gt 0) {
    Write-Host "`nTo check Container Apps status:" -ForegroundColor Yellow
    foreach ($app in $containerAppServices) {
        Write-Host "  az containerapp show --name $($app.Name) --resource-group $ResourceGroup --query 'properties.runningStatus' -o tsv" -ForegroundColor Gray
    }
}

Write-Host "`nTo check all services status, run:" -ForegroundColor Yellow
Write-Host "  .\Get-AzureServiceStatus.ps1" -ForegroundColor Gray

# Create status checking script
$statusScriptContent = @'
# Quick Status Check for Azure Trading Services
param([string]$ResourceGroup = "rg-trading-hero")

Write-Host "=== Azure Trading Services Status ===" -ForegroundColor Cyan

# Check ADX
$adxName = (Get-Content "azure-trading-config-*.txt" | Select-String "ADXCluster = " | ForEach-Object { $_ -replace 'ADXCluster = "?([^"]*)"?', '$1' }).Trim()
if ($adxName -and $adxName -ne "Not Created") {
    $state = az kusto cluster show --name $adxName --resource-group $ResourceGroup --query state -o tsv 2>$null
    Write-Host "ADX Cluster: $state" -ForegroundColor $(if ($state -eq "Running") { "Green" } else { "Yellow" })
}

# Check Container Apps
Write-Host "`nContainer Apps:" -ForegroundColor Cyan
az containerapp list --resource-group $ResourceGroup --query "[].{Name:name, Status:properties.runningStatus, Replicas:properties.template.scale.minReplicas}" -o table

# Check costs
Write-Host "`nDaily cost estimate based on running services" -ForegroundColor Yellow
'@

if (-not (Test-Path "Get-AzureServiceStatus.ps1")) {
    $statusScriptContent | Out-File "Get-AzureServiceStatus.ps1"
    Write-Host "`nCreated Get-AzureServiceStatus.ps1 for checking service status" -ForegroundColor Green
}

Write-Host "`n💡 Tip: Remember to shut down services when done to save costs!" -ForegroundColor Yellow
Write-Host "   Run: .\Shutdown-AzureServices.ps1" -ForegroundColor Gray