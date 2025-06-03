# Azure Trading System - Enhanced Service Initialization Script
# Features: Configurable services, unique naming, error handling, better region support

param(
    [string]$ResourceGroup = "trading-hero-rgp",
    [string]$Location = "eastus2",  # East US 2 for better availability
    [switch]$IncludeADX = $true,    # ADX is expensive, make it optional
    [switch]$IncludeSQL = $true,
    [switch]$IncludeRedis = $true,
    [switch]$IncludeContainerApps = $true,
    [switch]$UseUniqueNames = $true,
    [switch]$SkipProviderRegistration = $false,
    [switch]$DryRun = $false
)

# Generate unique suffix for globally unique names
$RandomSuffix = if ($UseUniqueNames) { Get-Random -Minimum 1000 -Maximum 9999 } else { "" }

# Configuration Variables with unique names
$AcrName = if ($UseUniqueNames) { "tradingacr$RandomSuffix" } else { "tradingsystemacr" }
$KeyVaultName = "kvtrading$RandomSuffix"  # KV names must be 3-24 chars, alphanumeric
$AdxClusterName = "tradingadx$RandomSuffix"
$AdxDatabaseName = "TradingData"
$RedisName = "trading-redis-$RandomSuffix"
$SqlServerName = "trading-sql-$RandomSuffix"
$SqlDatabaseName = "TradingSystemDB"
$ContainerAppEnv = "trading-env-$RandomSuffix"
$StorageAccountName = "tradingstor$RandomSuffix"

# Service Principal name
$SpName = "sp-trading-system-$RandomSuffix"

# Script Variables
$ErrorCount = 0
$CreatedResources = @()

# Colors for output
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    $args | Write-Output
    $host.UI.RawUI.ForegroundColor = $fc
}

# Error handling function
function Handle-Error($ServiceName, $ErrorMessage) {
    Write-Host "   ✗ Failed to create $ServiceName" -ForegroundColor Red
    Write-Host "   Error: $ErrorMessage" -ForegroundColor Red
    $script:ErrorCount++
}

# Success tracking function
function Track-Success($ResourceType, $ResourceName) {
    $script:CreatedResources += [PSCustomObject]@{
        Type = $ResourceType
        Name = $ResourceName
        Status = "Created"
    }
}

Write-ColorOutput Green "=== Azure Trading System Enhanced Initialization ==="

# Display configuration
Write-Host "`nConfiguration:" -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroup"
Write-Host "  Location: $Location"
Write-Host "  Unique Names: $UseUniqueNames"
Write-Host "  Include ADX: $IncludeADX"
Write-Host "  Include SQL: $IncludeSQL"
Write-Host "  Include Redis: $IncludeRedis"
Write-Host "  Include Container Apps: $IncludeContainerApps"
Write-Host "  Dry Run: $DryRun"

if ($DryRun) {
    Write-Host "`nDRY RUN MODE - No resources will be created" -ForegroundColor Yellow
}

# Check if logged in to Azure
Write-Host "`nChecking Azure login status..." -ForegroundColor Yellow
try {
    $account = az account show 2>$null | ConvertFrom-Json
    Write-Host "Logged in as: $($account.user.name)" -ForegroundColor Green
    Write-Host "Subscription: $($account.name)" -ForegroundColor Green
} catch {
    Write-ColorOutput Red "Not logged in to Azure. Please run: az login"
    exit 1
}

# Register required providers
if (-not $SkipProviderRegistration) {
    Write-Host "`nRegistering required resource providers..." -ForegroundColor Yellow
    $providers = @(
        "Microsoft.ContainerRegistry",
        "Microsoft.KeyVault",
        "Microsoft.Cache",
        "Microsoft.Sql",
        "Microsoft.App",
        "Microsoft.OperationalInsights",
        "Microsoft.Storage"
    )
    
    if ($IncludeADX) {
        $providers += "Microsoft.Kusto"
    }
    
    foreach ($provider in $providers) {
        if (-not $DryRun) {
            Write-Host "  Registering $provider..." -NoNewline
            az provider register --namespace $provider 2>$null
            Write-Host " Done" -ForegroundColor Green
        } else {
            Write-Host "  Would register $provider" -ForegroundColor Gray
        }
    }
}

# 1. Create Resource Group
Write-Host "`n1. Creating Resource Group..." -ForegroundColor Yellow
if (-not $DryRun) {
    try {
        az group create `
            --name $ResourceGroup `
            --location $Location `
            --output none 2>$null
        Write-Host "   ✓ Resource Group created" -ForegroundColor Green
        Track-Success "ResourceGroup" $ResourceGroup
    } catch {
        Handle-Error "Resource Group" $_
    }
} else {
    Write-Host "   Would create Resource Group: $ResourceGroup" -ForegroundColor Gray
}

# 2. Create Storage Account (for blob storage)
Write-Host "`n2. Creating Storage Account..." -ForegroundColor Yellow
if (-not $DryRun) {
    try {
        az storage account create `
            --name $StorageAccountName `
            --resource-group $ResourceGroup `
            --location $Location `
            --sku Standard_LRS `
            --kind StorageV2 `
            --output none 2>$null
        Write-Host "   ✓ Storage Account created: $StorageAccountName" -ForegroundColor Green
        Track-Success "StorageAccount" $StorageAccountName
    } catch {
        Handle-Error "Storage Account" $_
    }
} else {
    Write-Host "   Would create Storage Account: $StorageAccountName" -ForegroundColor Gray
}

# 3. Create Azure Container Registry
Write-Host "`n3. Creating Azure Container Registry..." -ForegroundColor Yellow
if (-not $DryRun) {
    # Check if name is available
    $acrAvailable = az acr check-name --name $AcrName --query nameAvailable -o tsv 2>$null
    
    if ($acrAvailable -eq "false") {
        Write-Host "   Name '$AcrName' is not available, generating new name..." -ForegroundColor Yellow
        $RandomSuffix = Get-Random -Minimum 10000 -Maximum 99999
        $AcrName = "tradingacr$RandomSuffix"
    }
    
    try {
        az acr create `
            --name $AcrName `
            --resource-group $ResourceGroup `
            --sku Basic `
            --admin-enabled true `
            --location $Location `
            --output none 2>$null
        Write-Host "   ✓ Container Registry created: $AcrName" -ForegroundColor Green
        Write-Host "   ✓ Admin user enabled for easy authentication" -ForegroundColor Green
        Track-Success "ContainerRegistry" $AcrName
    } catch {
        Handle-Error "Container Registry" $_
    }
} else {
    Write-Host "   Would create Container Registry: $AcrName" -ForegroundColor Gray
}

# 4. Create Azure Key Vault
Write-Host "`n4. Creating Azure Key Vault..." -ForegroundColor Yellow
if (-not $DryRun) {
    try {
        az keyvault create `
            --name $KeyVaultName `
            --resource-group $ResourceGroup `
            --location $Location `
            --enable-rbac-authorization false `
            --output none 2>$null
        Write-Host "   ✓ Key Vault created: $KeyVaultName" -ForegroundColor Green
        Track-Success "KeyVault" $KeyVaultName
    } catch {
        Handle-Error "Key Vault" $_
    }
} else {
    Write-Host "   Would create Key Vault: $KeyVaultName" -ForegroundColor Gray
}

# 5. Create Azure Data Explorer (Optional)
if ($IncludeADX) {
    Write-Host "`n5. Creating Azure Data Explorer Cluster (this takes ~10 minutes)..." -ForegroundColor Yellow
    Write-Host "   ⚠️  This will cost ~$137/month for 24/7 operation" -ForegroundColor Yellow
    
    if (-not $DryRun) {
        try {
            az kusto cluster create `
                --name $AdxClusterName `
                --resource-group $ResourceGroup `
                --location $Location `
                --sku name="Dev(No SLA)_Standard_E2a_v4" tier="Basic" `
                --output none 2>$null
            Write-Host "   ✓ ADX Cluster created: $AdxClusterName" -ForegroundColor Green
            Track-Success "ADXCluster" $AdxClusterName
            
            # Create ADX Database
            Write-Host "   Creating ADX Database..." -ForegroundColor Yellow
            az kusto database create `
                --cluster-name $AdxClusterName `
                --database-name $AdxDatabaseName `
                --resource-group $ResourceGroup `
                --read-write-database soft-delete-period=P365D hot-cache-period=P31D location=$Location `
                --output none 2>$null
            Write-Host "   ✓ ADX Database created" -ForegroundColor Green
            Track-Success "ADXDatabase" $AdxDatabaseName
        } catch {
            Handle-Error "Azure Data Explorer" $_
        }
    } else {
        Write-Host "   Would create ADX Cluster: $AdxClusterName" -ForegroundColor Gray
    }
} else {
    Write-Host "`n5. Skipping Azure Data Explorer (not included)" -ForegroundColor Gray
}

# 6. Create Azure Cache for Redis (Optional)
if ($IncludeRedis) {
    Write-Host "`n6. Creating Azure Cache for Redis..." -ForegroundColor Yellow
    if (-not $DryRun) {
        try {
            az redis create `
                --name $RedisName `
                --resource-group $ResourceGroup `
                --location $Location `
                --sku Basic `
                --vm-size c0 `
                --output none 2>$null
            Write-Host "   ✓ Redis Cache created: $RedisName" -ForegroundColor Green
            Track-Success "RedisCache" $RedisName
        } catch {
            Handle-Error "Redis Cache" $_
        }
    } else {
        Write-Host "   Would create Redis Cache: $RedisName" -ForegroundColor Gray
    }
} else {
    Write-Host "`n6. Skipping Redis Cache (not included)" -ForegroundColor Gray
}

# 7. Create Azure SQL Database (Optional)
if ($IncludeSQL) {
    Write-Host "`n7. Creating Azure SQL Server and Database..." -ForegroundColor Yellow
    
    if (-not $DryRun) {
        $SqlAdminUser = Read-Host "Enter SQL Admin Username"
        $SqlAdminPassword = Read-Host "Enter SQL Admin Password" -AsSecureString
        $SqlAdminPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($SqlAdminPassword))
        
        try {
            az sql server create `
                --name $SqlServerName `
                --resource-group $ResourceGroup `
                --location $Location `
                --admin-user $SqlAdminUser `
                --admin-password $SqlAdminPasswordPlain `
                --output none 2>$null
            Write-Host "   ✓ SQL Server created: $SqlServerName" -ForegroundColor Green
            Track-Success "SQLServer" $SqlServerName
            
            # Create database
            az sql db create `
                --resource-group $ResourceGroup `
                --server $SqlServerName `
                --name $SqlDatabaseName `
                --edition Standard `
                --capacity 10 `
                --output none 2>$null
            Write-Host "   ✓ SQL Database created (S0 tier)" -ForegroundColor Green
            Track-Success "SQLDatabase" $SqlDatabaseName
            
            # Allow Azure services
            az sql server firewall-rule create `
                --resource-group $ResourceGroup `
                --server $SqlServerName `
                --name AllowAzureServices `
                --start-ip-address 0.0.0.0 `
                --end-ip-address 0.0.0.0 `
                --output none 2>$null
        } catch {
            Handle-Error "SQL Server" $_
        }
    } else {
        Write-Host "   Would create SQL Server: $SqlServerName" -ForegroundColor Gray
    }
} else {
    Write-Host "`n7. Skipping SQL Database (not included)" -ForegroundColor Gray
}

# 8. Create Container Apps Environment (Optional)
if ($IncludeContainerApps) {
    Write-Host "`n8. Creating Container Apps Environment..." -ForegroundColor Yellow
    if (-not $DryRun) {
        # Check if environment already exists
        $envExists = az containerapp env show --name $ContainerAppEnv --resource-group $ResourceGroup 2>$null
        if ($envExists) {
            Write-Host "   ✓ Container Apps Environment already exists: $ContainerAppEnv" -ForegroundColor Green
        } else {
            try {
                # First create Log Analytics workspace for Container Apps
                $logWorkspaceName = "log-trading-$RandomSuffix"
                Write-Host "   Creating Log Analytics workspace..." -ForegroundColor Gray
                
                az monitor log-analytics workspace create `
                    --resource-group $ResourceGroup `
                    --workspace-name $logWorkspaceName `
                    --location $Location `
                    --output none 2>$null
                
                # Get workspace details
                $workspaceId = az monitor log-analytics workspace show `
                    --resource-group $ResourceGroup `
                    --workspace-name $logWorkspaceName `
                    --query customerId -o tsv
                
                $workspaceKey = az monitor log-analytics workspace get-shared-keys `
                    --resource-group $ResourceGroup `
                    --workspace-name $logWorkspaceName `
                    --query primarySharedKey -o tsv
                
                # Create Container Apps environment WITH system-assigned identity
                Write-Host "   Creating Container Apps Environment..." -ForegroundColor Gray
                az containerapp env create `
                    --name $ContainerAppEnv `
                    --resource-group $ResourceGroup `
                    --location $Location `
                    --logs-workspace-id $workspaceId `
                    --logs-workspace-key $workspaceKey `
                    --assign-identity `
                    --output none 2>$null
                    
                Write-Host "   ✓ Container Apps Environment created: $ContainerAppEnv" -ForegroundColor Green
                Track-Success "ContainerAppEnv" $ContainerAppEnv
                Track-Success "LogAnalytics" $logWorkspaceName

            } catch {
                Handle-Error "Container Apps Environment" $_
            }
        }
    } else {
        Write-Host "   Would create Container Apps Environment: $ContainerAppEnv" -ForegroundColor Gray
    }
} else {
    Write-Host "`n8. Skipping Container Apps Environment (not included)" -ForegroundColor Gray
}

# 9. Store connection strings in Key Vault
if (-not $DryRun -and $CreatedResources.Count -gt 0) {
    Write-Host "`n9. Storing connection strings in Key Vault..." -ForegroundColor Yellow
    
    # Storage Account connection string
    if ($CreatedResources.Name -contains $StorageAccountName) {
        try {
            $StorageKey = az storage account keys list `
                --account-name $StorageAccountName `
                --resource-group $ResourceGroup `
                --query "[0].value" -o tsv 2>$null
            
            $StorageConnection = "DefaultEndpointsProtocol=https;AccountName=$StorageAccountName;AccountKey=$StorageKey;EndpointSuffix=core.windows.net"
            
            az keyvault secret set `
                --vault-name $KeyVaultName `
                --name "StorageConnection" `
                --value $StorageConnection `
                --output none 2>$null
                
            Write-Host "   ✓ Storage connection string saved" -ForegroundColor Green
        } catch {
            Write-Host "   Failed to store Storage connection string" -ForegroundColor Red
        }
    }
    
    # Redis connection string
    if ($IncludeRedis -and $CreatedResources.Name -contains $RedisName) {
        try {
            $RedisKeys = az redis list-keys `
                --name $RedisName `
                --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
            
            $RedisHost = az redis show `
                --name $RedisName `
                --resource-group $ResourceGroup `
                --query hostName -o tsv 2>$null
            
            if ($RedisHost -and $RedisKeys) {
                # Properly format Redis connection string
                $RedisConnection = "${RedisHost}:6380,password=$($RedisKeys.primaryKey),ssl=True,abortConnect=False"
                
                az keyvault secret set `
                    --vault-name $KeyVaultName `
                    --name "RedisConnection" `
                    --value $RedisConnection `
                    --output none 2>$null
                    
                Write-Host "   ✓ Redis connection string saved" -ForegroundColor Green
            }
        } catch {
            Write-Host "   Failed to store Redis connection string" -ForegroundColor Red
        }
    }
    
    # SQL connection string
    if ($IncludeSQL -and $CreatedResources.Name -contains $SqlServerName) {
        $SqlConnection = "Server=tcp:$SqlServerName.database.windows.net,1433;Initial Catalog=$SqlDatabaseName;Persist Security Info=False;User ID=$SqlAdminUser;Password=$SqlAdminPasswordPlain;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
        
        az keyvault secret set `
            --vault-name $KeyVaultName `
            --name "SqlConnection" `
            --value $SqlConnection `
            --output none 2>$null
            
        Write-Host "   ✓ SQL connection string saved" -ForegroundColor Green
    }
    
    # ACR credentials
    if ($CreatedResources.Name -contains $AcrName) {
        try {
            $AcrCreds = az acr credential show --name $AcrName --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
            
            az keyvault secret set `
                --vault-name $KeyVaultName `
                --name "AcrLoginServer" `
                --value "$AcrName.azurecr.io" `
                --output none 2>$null
            
            az keyvault secret set `
                --vault-name $KeyVaultName `
                --name "AcrUsername" `
                --value $AcrCreds.username `
                --output none 2>$null
            
            az keyvault secret set `
                --vault-name $KeyVaultName `
                --name "AcrPassword" `
                --value $AcrCreds.passwords[0].value `
                --output none 2>$null
                
            Write-Host "   ✓ ACR credentials saved" -ForegroundColor Green
        } catch {
            Write-Host "   Failed to store ACR credentials" -ForegroundColor Red
        }
    }
    
    # ADX connection info
    if ($IncludeADX -and $CreatedResources.Name -contains $AdxClusterName) {
        $AdxUri = "https://$AdxClusterName.$Location.kusto.windows.net"
        az keyvault secret set `
            --vault-name $KeyVaultName `
            --name "AdxClusterUri" `
            --value $AdxUri `
            --output none 2>$null
        
        az keyvault secret set `
            --vault-name $KeyVaultName `
            --name "AdxDatabase" `
            --value $AdxDatabaseName `
            --output none 2>$null
            
        Write-Host "   ✓ ADX connection info saved" -ForegroundColor Green
    }
    
    Write-Host "   ✓ All connection strings stored in Key Vault" -ForegroundColor Green
}

# 10. Create Service Principal
if (-not $DryRun) {
    Write-Host "`n10. Creating Service Principal..." -ForegroundColor Yellow
    try {
        $SubscriptionId = az account show --query id -o tsv
        $SpOutput = az ad sp create-for-rbac `
            --name $SpName `
            --role Contributor `
            --scopes /subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup 2>$null | ConvertFrom-Json
        
        if ($SpOutput) {
            $AppId = $SpOutput.appId
            $ClientSecret = $SpOutput.password
            $TenantId = $SpOutput.tenant
            
            # Store in Key Vault
            az keyvault secret set --vault-name $KeyVaultName --name "AzureClientId" --value $AppId --output none 2>$null
            az keyvault secret set --vault-name $KeyVaultName --name "AzureClientSecret" --value $ClientSecret --output none 2>$null
            az keyvault secret set --vault-name $KeyVaultName --name "AzureTenantId" --value $TenantId --output none 2>$null
            
            Write-Host "   ✓ Service Principal created" -ForegroundColor Green
            Track-Success "ServicePrincipal" $SpName
            
            # Grant ADX permissions if ADX was created
            if ($IncludeADX -and $CreatedResources.Name -contains $AdxClusterName) {
                Write-Host "   Granting ADX permissions..." -ForegroundColor Yellow
                try {
                    az kusto database-principal-assignment create `
                        --cluster-name $AdxClusterName `
                        --database-name $AdxDatabaseName `
                        --principal-assignment-name "tradingSystemAccess" `
                        --principal-id $AppId `
                        --principal-type "App" `
                        --role "Admin" `
                        --tenant-id $TenantId `
                        --resource-group $ResourceGroup `
                        --output none 2>$null
                    Write-Host "   ✓ ADX permissions granted" -ForegroundColor Green
                } catch {
                    Write-Host "   Failed to grant ADX permissions" -ForegroundColor Red
                }
            }
        }
    } catch {
        Handle-Error "Service Principal" $_
    }
}

# Save configuration to file
if (-not $DryRun) {
    $configContent = @"
# Azure Trading System Configuration
# Generated: $(Get-Date)
# Script Version: Enhanced with Options

ResourceGroup = "$ResourceGroup"
Location = "$Location"
StorageAccount = "$StorageAccountName"
ContainerRegistry = "$AcrName"
ContainerRegistryUrl = "$AcrName.azurecr.io"
KeyVault = "$KeyVaultName"
ServicePrincipal = "$SpName"

# Optional Services
ADXCluster = "$(if ($IncludeADX) { $AdxClusterName } else { 'Not Created' })"
ADXDatabase = "$(if ($IncludeADX) { $AdxDatabaseName } else { 'Not Created' })"
RedisCache = "$(if ($IncludeRedis) { $RedisName } else { 'Not Created' })"
SQLServer = "$(if ($IncludeSQL) { $SqlServerName } else { 'Not Created' })"
SQLDatabase = "$(if ($IncludeSQL) { $SqlDatabaseName } else { 'Not Created' })"
ContainerAppsEnv = "$(if ($IncludeContainerApps) { $ContainerAppEnv } else { 'Not Created' })"

# Errors: $ErrorCount
"@
    
    # Add container app definitions to config
    $configContent += @"
# ContainerApps
ContainerApp_trading-web-app = "trading-web-app,$AcrName.azurecr.io/tradingsystem-web:latest,80"
ContainerApp_trading-dataingestion-app = "trading-dataingestion-app,$AcrName.azurecr.io/tradingsystem-dataingestion:latest,80"
ContainerApp_trading-analysis-app = "trading-analysis-app,$AcrName.azurecr.io/tradingsystem-analysis:latest,80"
ContainerApp_trading-backtesting-app = "trading-backtesting-app,$AcrName.azurecr.io/tradingsystem-backtesting:latest,80"
"@

    $configContent | Out-File "azure-trading-config-$RandomSuffix.txt"
}

# Summary
Write-Host "`n=== Initialization Summary ===" -ForegroundColor Cyan
Write-Host "`nCreated Resources:" -ForegroundColor Green
$CreatedResources | Format-Table Type, Name, Status -AutoSize

if ($ErrorCount -gt 0) {
    Write-Host "`nErrors encountered: $ErrorCount" -ForegroundColor Red
    Write-Host "Please check the error messages above and retry failed services individually." -ForegroundColor Yellow
}

Write-Host "`nConfiguration saved to: azure-trading-config-$RandomSuffix.txt" -ForegroundColor Green

# Display important notes
Write-Host "`n=== Important Notes ===" -ForegroundColor Cyan
Write-Host "1. ACR Admin User is enabled for easy authentication" -ForegroundColor Yellow
Write-Host "2. Container Apps will use ACR admin credentials (no managed identity needed)" -ForegroundColor Yellow
Write-Host "3. All connection strings are stored in Key Vault: $KeyVaultName" -ForegroundColor Yellow
Write-Host "4. Redis connection uses SSL on port 6380" -ForegroundColor Yellow

# Display cost estimate
Write-Host "`nEstimated Monthly Costs (5.5 hours/day):" -ForegroundColor Cyan
$totalCost = 0
if ($IncludeADX) { 
    Write-Host "  ADX Cluster: ~`$31.19" -ForegroundColor Yellow
    $totalCost += 31.19
}
if ($IncludeSQL) { 
    Write-Host "  SQL Database (S0): ~`$3.42" -ForegroundColor Yellow
    $totalCost += 3.42
}
if ($IncludeRedis) { 
    Write-Host "  Redis Cache: ~`$3.64" -ForegroundColor Yellow
    $totalCost += 3.64
}
if ($IncludeContainerApps) { 
    Write-Host "  Container Apps: ~`$25.05" -ForegroundColor Yellow
    $totalCost += 25.05
}
Write-Host "  Storage + Registry + KV: ~`$7.30" -ForegroundColor Yellow
$totalCost += 7.30
Write-Host "  TOTAL: ~`$$($totalCost)/month" -ForegroundColor Green

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Review the configuration file: azure-trading-config-$RandomSuffix.txt"
Write-Host "2. Update deploy-containers.ps1 with these values:"
Write-Host "   - AcrName = `"$AcrName`""
Write-Host "   - ResourceGroup = `"$ResourceGroup`""
Write-Host "   - ContainerAppEnv = `"$ContainerAppEnv`""
Write-Host "   - KeyVaultName = `"$KeyVaultName`""
Write-Host "3. Build and push Docker images to ACR"
Write-Host "4. Deploy containers using: .\deploy-containers.ps1"
Write-Host "5. Set up the auto start/stop schedule for cost savings"