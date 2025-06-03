# Azure Trading Services - Detailed Properties Extractor
# Extracts and displays all properties for each service in your resource group

param(
    [string]$ResourceGroup = "rg-trading-hero",
    [string]$ConfigFile = "azure-trading-config-*.txt",
    [switch]$ExportToJson = $true,
    [switch]$ExportToHtml = $false,
    [switch]$ShowRawJson = $false,
    [string[]]$ServiceTypes = @()  # Empty = all services
)

# Colors for output
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    $args | Write-Output
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-Host "=== Azure Trading Services - Property Extractor ===" -ForegroundColor Cyan
Write-Host "Extracting detailed properties for all services" -ForegroundColor Yellow
Write-Host "Resource Group: $ResourceGroup" -ForegroundColor Gray
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# Check Azure login
try {
    $account = az account show 2>$null | ConvertFrom-Json
    Write-Host "Azure Account: $($account.user.name)" -ForegroundColor Gray
    $subscriptionId = $account.id
} catch {
    Write-ColorOutput Red "Not logged in to Azure. Please run: az login"
    exit 1
}

# Try to load configuration
$config = @{}
$configFiles = Get-ChildItem -Path $ConfigFile -ErrorAction SilentlyContinue
if ($configFiles.Count -gt 0) {
    $latestConfig = $configFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host "Configuration: $($latestConfig.Name)" -ForegroundColor Gray
    
    Get-Content $latestConfig | ForEach-Object {
        if ($_ -match "^(\w+)\s*=\s*(.+)$") {
            $config[$matches[1]] = $matches[2].Trim('"')
        }
    }
}

# Initialize results collection
$allServiceProperties = @{
    Metadata = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ResourceGroup = $ResourceGroup
        Subscription = $subscriptionId
        Account = $account.user.name
    }
    Services = @{}
}

Write-Host "`nExtracting service properties..." -ForegroundColor Yellow

# Helper function to extract key properties
function Get-KeyProperties($object, $serviceName) {
    $props = @{
        Name = $serviceName
        ResourceId = $object.id
        Location = $object.location
        Tags = $object.tags
        CreatedTime = $null
        LastModified = $null
    }
    
    # Try to find timestamps
    if ($object.PSObject.Properties['systemData']) {
        $props.CreatedTime = $object.systemData.createdAt
        $props.LastModified = $object.systemData.lastModifiedAt
    }
    
    return $props
}

# 1. Storage Account
if (-not $ServiceTypes -or "Storage" -in $ServiceTypes) {
    Write-Host "`n📊 Extracting Storage Account properties..." -ForegroundColor Cyan
    $StorageAccountName = $config["StorageAccount"]
    if ($StorageAccountName -and $StorageAccountName -ne "Not Created") {
        try {
            $storage = az storage account show --name $StorageAccountName --resource-group $ResourceGroup | ConvertFrom-Json
            
            $storageProps = @{
                BasicInfo = Get-KeyProperties $storage $StorageAccountName
                Properties = @{
                    Kind = $storage.kind
                    SkuName = $storage.sku.name
                    SkuTier = $storage.sku.tier
                    AccessTier = $storage.accessTier
                    MinimumTlsVersion = $storage.minimumTlsVersion
                    AllowBlobPublicAccess = $storage.allowBlobPublicAccess
                    NetworkAcls = $storage.networkAcls.defaultAction
                    SupportsHttpsTrafficOnly = $storage.supportsHttpsTrafficOnly
                    Encryption = @{
                        Services = $storage.encryption.services.PSObject.Properties.Name
                        KeySource = $storage.encryption.keySource
                    }
                    PrimaryLocation = $storage.primaryLocation
                    StatusOfPrimary = $storage.statusOfPrimary
                    CreationTime = $storage.creationTime
                    ProvisioningState = $storage.provisioningState
                }
                Endpoints = $storage.primaryEndpoints
                Usage = $null
            }
            
            # Get storage usage
            try {
                $usage = az storage account show-usage --name $StorageAccountName | ConvertFrom-Json
                $storageProps.Usage = @{
                    UsedGB = [math]::Round($usage.value / 1GB, 2)
                    Limit = $usage.limit
                    Unit = "GB"
                }
            } catch {}
            
            $allServiceProperties.Services["StorageAccount"] = $storageProps
            Write-Host "   ✓ Extracted $(($storageProps.Properties.PSObject.Properties).Count) properties" -ForegroundColor Green
        } catch {
            Write-Host "   ✗ Failed to extract Storage Account properties" -ForegroundColor Red
        }
    }
}

# 2. Container Registry
if (-not $ServiceTypes -or "ACR" -in $ServiceTypes) {
    Write-Host "`n🐳 Extracting Container Registry properties..." -ForegroundColor Cyan
    $AcrName = $config["ContainerRegistry"]
    if ($AcrName -and $AcrName -ne "Not Created") {
        try {
            $acr = az acr show --name $AcrName --resource-group $ResourceGroup | ConvertFrom-Json
            
            $acrProps = @{
                BasicInfo = Get-KeyProperties $acr $AcrName
                Properties = @{
                    LoginServer = $acr.loginServer
                    SkuName = $acr.sku.name
                    SkuTier = $acr.sku.tier
                    AdminUserEnabled = $acr.adminUserEnabled
                    CreationDate = $acr.creationDate
                    ProvisioningState = $acr.provisioningState
                    NetworkRuleSet = $acr.networkRuleSet.defaultAction
                    PublicNetworkAccess = $acr.publicNetworkAccess
                    ZoneRedundancy = $acr.zoneRedundancy
                    DataEndpointEnabled = $acr.dataEndpointEnabled
                    AnonymousPullEnabled = $acr.anonymousPullEnabled
                }
                Repositories = @()
                StorageUsage = $null
            }
            
            # Get repositories
            try {
                $repos = az acr repository list --name $AcrName --output json 2>$null | ConvertFrom-Json
                if ($repos) {
                    $acrProps.Repositories = $repos
                }
            } catch {}
            
            # Get usage
            try {
                $usage = az acr show-usage --name $AcrName --output json 2>$null | ConvertFrom-Json
                $acrProps.StorageUsage = @{
                    UsedGB = [math]::Round($usage.value[0].currentValue / 1GB, 2)
                    LimitGB = [math]::Round($usage.value[0].limit / 1GB, 2)
                }
            } catch {}
            
            $allServiceProperties.Services["ContainerRegistry"] = $acrProps
            Write-Host "   ✓ Extracted $(($acrProps.Properties.PSObject.Properties).Count) properties" -ForegroundColor Green
        } catch {
            Write-Host "   ✗ Failed to extract Container Registry properties" -ForegroundColor Red
        }
    }
}

# 3. Key Vault
if (-not $ServiceTypes -or "KeyVault" -in $ServiceTypes) {
    Write-Host "`n🔐 Extracting Key Vault properties..." -ForegroundColor Cyan
    $KeyVaultName = $config["KeyVault"]
    if ($KeyVaultName -and $KeyVaultName -ne "Not Created") {
        try {
            $kv = az keyvault show --name $KeyVaultName --resource-group $ResourceGroup | ConvertFrom-Json
            
            $kvProps = @{
                BasicInfo = Get-KeyProperties $kv $KeyVaultName
                Properties = @{
                    VaultUri = $kv.properties.vaultUri
                    TenantId = $kv.properties.tenantId
                    Sku = $kv.properties.sku.name
                    EnabledForDeployment = $kv.properties.enabledForDeployment
                    EnabledForDiskEncryption = $kv.properties.enabledForDiskEncryption
                    EnabledForTemplateDeployment = $kv.properties.enabledForTemplateDeployment
                    EnableSoftDelete = $kv.properties.enableSoftDelete
                    SoftDeleteRetentionInDays = $kv.properties.softDeleteRetentionInDays
                    EnableRbacAuthorization = $kv.properties.enableRbacAuthorization
                    ProvisioningState = $kv.properties.provisioningState
                    PublicNetworkAccess = $kv.properties.publicNetworkAccess
                    NetworkAcls = $kv.properties.networkAcls.defaultAction
                }
                Secrets = @()
                Keys = @()
                Certificates = @()
            }
            
            # Get secrets list (names only)
            try {
                $secrets = az keyvault secret list --vault-name $KeyVaultName --query "[].{name:name, enabled:attributes.enabled}" | ConvertFrom-Json
                $kvProps.Secrets = $secrets
            } catch {}
            
            $allServiceProperties.Services["KeyVault"] = $kvProps
            Write-Host "   ✓ Extracted $(($kvProps.Properties.PSObject.Properties).Count) properties" -ForegroundColor Green
        } catch {
            Write-Host "   ✗ Failed to extract Key Vault properties" -ForegroundColor Red
        }
    }
}

# 4. Azure Data Explorer
if (-not $ServiceTypes -or "ADX" -in $ServiceTypes) {
    Write-Host "`n📊 Extracting Azure Data Explorer properties..." -ForegroundColor Cyan
    $AdxClusterName = $config["ADXCluster"]
    if ($AdxClusterName -and $AdxClusterName -ne "Not Created") {
        try {
            $adx = az kusto cluster show --name $AdxClusterName --resource-group $ResourceGroup | ConvertFrom-Json
            
            $adxProps = @{
                BasicInfo = Get-KeyProperties $adx $AdxClusterName
                Properties = @{
                    State = $adx.state
                    ProvisioningState = $adx.provisioningState
                    Uri = $adx.uri
                    DataIngestionUri = $adx.dataIngestionUri
                    StateReason = $adx.stateReason
                    TrustedExternalTenants = $adx.trustedExternalTenants
                    EngineType = $adx.engineType
                    EnableDiskEncryption = $adx.enableDiskEncryption
                    EnableStreamingIngest = $adx.enableStreamingIngest
                    EnablePurge = $adx.enablePurge
                    EnableDoubleEncryption = $adx.enableDoubleEncryption
                    PublicNetworkAccess = $adx.publicNetworkAccess
                    Sku = @{
                        Name = $adx.sku.name
                        Tier = $adx.sku.tier
                        Capacity = $adx.sku.capacity
                    }
                }
                Databases = @()
            }
            
            # Get databases
            try {
                $dbs = az kusto database list --cluster-name $AdxClusterName --resource-group $ResourceGroup | ConvertFrom-Json
                foreach ($db in $dbs) {
                    $adxProps.Databases += @{
                        Name = $db.name
                        Type = $db.type
                        Location = $db.location
                        Kind = $db.kind
                    }
                }
            } catch {}
            
            $allServiceProperties.Services["AzureDataExplorer"] = $adxProps
            Write-Host "   ✓ Extracted $(($adxProps.Properties.PSObject.Properties).Count) properties" -ForegroundColor Green
        } catch {
            Write-Host "   ✗ Failed to extract ADX properties" -ForegroundColor Red
        }
    }
}

# 5. Redis Cache
if (-not $ServiceTypes -or "Redis" -in $ServiceTypes) {
    Write-Host "`n🔴 Extracting Redis Cache properties..." -ForegroundColor Cyan
    $RedisName = $config["RedisCache"]
    if ($RedisName -and $RedisName -ne "Not Created") {
        try {
            $redis = az redis show --name $RedisName --resource-group $ResourceGroup | ConvertFrom-Json
            
            $redisProps = @{
                BasicInfo = Get-KeyProperties $redis $RedisName
                Properties = @{
                    HostName = $redis.hostName
                    Port = $redis.port
                    SslPort = $redis.sslPort
                    ProvisioningState = $redis.provisioningState
                    RedisVersion = $redis.redisVersion
                    Sku = @{
                        Name = $redis.sku.name
                        Family = $redis.sku.family
                        Capacity = $redis.sku.capacity
                    }
                    EnableNonSslPort = $redis.enableNonSslPort
                    MinimumTlsVersion = $redis.minimumTlsVersion
                    PublicNetworkAccess = $redis.publicNetworkAccess
                    RedisConfiguration = $redis.redisConfiguration
                    AccessKeys = "Hidden for security"
                    SubnetId = $redis.subnetId
                    StaticIP = $redis.staticIP
                    Instances = $redis.instances
                }
            }
            
            $allServiceProperties.Services["RedisCache"] = $redisProps
            Write-Host "   ✓ Extracted $(($redisProps.Properties.PSObject.Properties).Count) properties" -ForegroundColor Green
        } catch {
            Write-Host "   ✗ Failed to extract Redis properties" -ForegroundColor Red
        }
    }
}

# 6. SQL Server and Database
if (-not $ServiceTypes -or "SQL" -in $ServiceTypes) {
    Write-Host "`n🗄️ Extracting SQL Server properties..." -ForegroundColor Cyan
    $SqlServerName = $config["SQLServer"]
    if ($SqlServerName -and $SqlServerName -ne "Not Created") {
        try {
            $sql = az sql server show --name $SqlServerName --resource-group $ResourceGroup | ConvertFrom-Json
            
            $sqlProps = @{
                BasicInfo = Get-KeyProperties $sql $SqlServerName
                Properties = @{
                    FullyQualifiedDomainName = $sql.fullyQualifiedDomainName
                    State = $sql.state
                    Version = $sql.version
                    AdministratorLogin = $sql.administratorLogin
                    PublicNetworkAccess = $sql.publicNetworkAccess
                    MinimalTlsVersion = $sql.minimalTlsVersion
                    RestrictOutboundNetworkAccess = $sql.restrictOutboundNetworkAccess
                }
                Databases = @()
                FirewallRules = @()
            }
            
            # Get databases
            try {
                $dbs = az sql db list --server $SqlServerName --resource-group $ResourceGroup | ConvertFrom-Json
                foreach ($db in $dbs) {
                    if ($db.name -ne "master") {
                        $sqlProps.Databases += @{
                            Name = $db.name
                            Status = $db.status
                            Edition = $db.edition
                            ServiceObjectiveName = $db.currentServiceObjectiveName
                            MaxSizeBytes = $db.maxSizeBytes
                            MaxSizeGB = [math]::Round($db.maxSizeBytes / 1GB, 2)
                            CreationDate = $db.creationDate
                            EarliestRestoreDate = $db.earliestRestoreDate
                            ZoneRedundant = $db.zoneRedundant
                            CurrentBackupStorageRedundancy = $db.currentBackupStorageRedundancy
                        }
                    }
                }
            } catch {}
            
            # Get firewall rules
            try {
                $rules = az sql server firewall-rule list --server $SqlServerName --resource-group $ResourceGroup | ConvertFrom-Json
                foreach ($rule in $rules) {
                    $sqlProps.FirewallRules += @{
                        Name = $rule.name
                        StartIpAddress = $rule.startIpAddress
                        EndIpAddress = $rule.endIpAddress
                    }
                }
            } catch {}
            
            $allServiceProperties.Services["SQLServer"] = $sqlProps
            Write-Host "   ✓ Extracted $(($sqlProps.Properties.PSObject.Properties).Count) properties" -ForegroundColor Green
        } catch {
            Write-Host "   ✗ Failed to extract SQL Server properties" -ForegroundColor Red
        }
    }
}

# 7. Container Apps Environment
if (-not $ServiceTypes -or "ContainerApps" -in $ServiceTypes) {
    Write-Host "`n📦 Extracting Container Apps properties..." -ForegroundColor Cyan
    $ContainerAppEnv = $config["ContainerAppsEnv"]
    if ($ContainerAppEnv -and $ContainerAppEnv -ne "Not Created") {
        try {
            $env = az containerapp env show --name $ContainerAppEnv --resource-group $ResourceGroup | ConvertFrom-Json
            
            $envProps = @{
                BasicInfo = Get-KeyProperties $env $ContainerAppEnv
                Properties = @{
                    ProvisioningState = $env.properties.provisioningState
                    InternalLoadBalancerEnabled = $env.properties.internalLoadBalancerEnabled
                    AppLogsConfiguration = $env.properties.appLogsConfiguration.destination
                    ZoneRedundant = $env.properties.zoneRedundant
                    VnetConfiguration = $env.properties.vnetConfiguration
                    DefaultDomain = $env.properties.defaultDomain
                    StaticIp = $env.properties.staticIp
                }
                Apps = @()
            }
            
            # Get all apps in this environment
            try {
                $apps = az containerapp list --resource-group $ResourceGroup --query "[?properties.environmentId.contains('$ContainerAppEnv')]" | ConvertFrom-Json
                foreach ($app in $apps) {
                    $appProps = @{
                        Name = $app.name
                        ProvisioningState = $app.properties.provisioningState
                        RunningStatus = $app.properties.runningStatus
                        LatestRevision = $app.properties.latestRevisionName
                        Configuration = @{
                            ActiveRevisionsMode = $app.properties.configuration.activeRevisionsMode
                            Ingress = @{
                                Enabled = $null -ne $app.properties.configuration.ingress
                                External = $app.properties.configuration.ingress.external
                                TargetPort = $app.properties.configuration.ingress.targetPort
                                Transport = $app.properties.configuration.ingress.transport
                                Fqdn = $app.properties.configuration.ingress.fqdn
                            }
                            Registries = $app.properties.configuration.registries.Count
                        }
                        Template = @{
                            Containers = $app.properties.template.containers.Count
                            Scale = @{
                                MinReplicas = $app.properties.template.scale.minReplicas
                                MaxReplicas = $app.properties.template.scale.maxReplicas
                            }
                        }
                    }
                    $envProps.Apps += $appProps
                }
            } catch {}
            
            $allServiceProperties.Services["ContainerApps"] = $envProps
            Write-Host "   ✓ Extracted $(($envProps.Properties.PSObject.Properties).Count) properties" -ForegroundColor Green
        } catch {
            Write-Host "   ✗ Failed to extract Container Apps properties" -ForegroundColor Red
        }
    }
}

# Display summary
Write-Host "`n=== Extraction Summary ===" -ForegroundColor Cyan
Write-Host "Total services analyzed: $($allServiceProperties.Services.Count)" -ForegroundColor Green

foreach ($service in $allServiceProperties.Services.Keys) {
    $propCount = 0
    if ($allServiceProperties.Services[$service].Properties) {
        $propCount = ($allServiceProperties.Services[$service].Properties.PSObject.Properties).Count
    }
    Write-Host "  - $service : $propCount properties" -ForegroundColor Gray
}

# Export to JSON
if ($ExportToJson) {
    $jsonFile = "azure-service-properties-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $allServiceProperties | ConvertTo-Json -Depth 10 | Out-File $jsonFile
    Write-Host "`n📄 Exported to JSON: $jsonFile" -ForegroundColor Green
}

# Export to HTML
if ($ExportToHtml) {
    $htmlFile = "azure-service-properties-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Azure Service Properties Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; }
        h2 { color: #106ebe; margin-top: 30px; }
        h3 { color: #323130; }
        .service { background: white; padding: 20px; margin: 20px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .property { margin: 5px 0; padding: 5px; }
        .property-name { font-weight: bold; color: #106ebe; }
        .property-value { color: #323130; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th { background-color: #0078d4; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        .metadata { background: #e1f5fe; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
    </style>
</head>
<body>
    <h1>Azure Service Properties Report</h1>
    <div class="metadata">
        <h3>Report Metadata</h3>
        <p><strong>Generated:</strong> $($allServiceProperties.Metadata.Timestamp)</p>
        <p><strong>Resource Group:</strong> $($allServiceProperties.Metadata.ResourceGroup)</p>
        <p><strong>Account:</strong> $($allServiceProperties.Metadata.Account)</p>
    </div>
"@

    foreach ($serviceName in $allServiceProperties.Services.Keys) {
        $service = $allServiceProperties.Services[$serviceName]
        $html += "<div class='service'>"
        $html += "<h2>$serviceName</h2>"
        
        # Basic Info
        if ($service.BasicInfo) {
            $html += "<h3>Basic Information</h3>"
            $html += "<table>"
            foreach ($prop in $service.BasicInfo.PSObject.Properties) {
                $html += "<tr><td class='property-name'>$($prop.Name)</td><td class='property-value'>$($prop.Value)</td></tr>"
            }
            $html += "</table>"
        }
        
        # Properties
        if ($service.Properties) {
            $html += "<h3>Properties</h3>"
            $html += "<table>"
            foreach ($prop in $service.Properties.PSObject.Properties) {
                $value = if ($prop.Value -is [PSCustomObject]) { 
                    $prop.Value | ConvertTo-Json -Compress 
                } else { 
                    $prop.Value 
                }
                $html += "<tr><td class='property-name'>$($prop.Name)</td><td class='property-value'>$value</td></tr>"
            }
            $html += "</table>"
        }
        
        $html += "</div>"
    }
    
    $html += "</body></html>"
    $html | Out-File $htmlFile
    Write-Host "📄 Exported to HTML: $htmlFile" -ForegroundColor Green
}

# Show raw JSON if requested
if ($ShowRawJson) {
    Write-Host "`n=== Raw JSON Output ===" -ForegroundColor Cyan
    $allServiceProperties | ConvertTo-Json -Depth 10
}

Write-Host "`nProperty extraction completed!" -ForegroundColor Green