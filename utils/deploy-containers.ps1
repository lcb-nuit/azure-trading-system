# Azure Trading System - Fixed Container Deployment Script with Debug

param(
    [string]$AcrName = "tradingacr9383",
    [string]$ResourceGroup = "rg-trading-hero",
    [string]$ContainerAppEnv = "trading-env-9383",
    [string]$KeyVaultName = "kvtrading9383",
    [string]$Location = "eastus2",  # Added location parameter
    [switch]$SkipBuild = $false,
    [switch]$CreateDockerfiles = $false,
    [switch]$SkipLocalBuild = $false,
    [switch]$SkipSecrets = $false,
    [switch]$DebugMode = $true  # Added debug mode
)

# Load config from latest azure-trading-config-*.txt if present
$configFiles = Get-ChildItem -Path "azure-trading-config-*.txt" -ErrorAction SilentlyContinue
if ($configFiles.Count -gt 0) {
    $latestConfig = $configFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host "Loaded config: $($latestConfig.Name)" -ForegroundColor Gray
    $config = @{}
    Get-Content $latestConfig | ForEach-Object {
        if ($_ -match "^(\w+)\s*=\s*(.+)$") {
            $config[$matches[1]] = $matches[2].Trim('"')
        }
    }
    if (-not $PSBoundParameters.ContainsKey('AcrName') -or !$AcrName) { $AcrName = $config["ContainerRegistry"] }
    if (-not $PSBoundParameters.ContainsKey('ResourceGroup') -or !$ResourceGroup) { $ResourceGroup = $config["ResourceGroup"] }
    if (-not $PSBoundParameters.ContainsKey('ContainerAppEnv') -or !$ContainerAppEnv) { $ContainerAppEnv = $config["ContainerAppsEnv"] }
    if (-not $PSBoundParameters.ContainsKey('KeyVaultName') -or !$KeyVaultName) { $KeyVaultName = $config["KeyVault"] }
    if (-not $PSBoundParameters.ContainsKey('Location') -or !$Location) { $Location = $config["Location"] }
    Write-Host "Using: AcrName=$AcrName, ResourceGroup=$ResourceGroup, ContainerAppEnv=$ContainerAppEnv, KeyVaultName=$KeyVaultName, Location=$Location" -ForegroundColor Yellow
}

# Service definitions
$services = @(
    @{ 
        Name = "trading-web-app"
        Path = "./src/TradingSystem.Web"
        ProjectFile = "TradingSystem.Web.csproj"
        Image = "tradingsystem-web:latest"
        Port = 80
        Type = "Web"
    },
    @{ 
        Name = "trading-dataingestion-app"
        Path = "./src/TradingSystem.DataIngestion"
        ProjectFile = "TradingSystem.DataIngestion.csproj"
        Image = "tradingsystem-dataingestion:latest"
        Port = 80
        Type = "Worker"
    },
    @{ 
        Name = "trading-analysis-app"
        Path = "./src/TradingSystem.Analysis"
        ProjectFile = "TradingSystem.Analysis.csproj"
        Image = "tradingsystem-analysis:latest"
        Port = 80
        Type = "Worker"
    },
    @{ 
        Name = "trading-backtesting-app"
        Path = "./src/TradingSystem.Backtesting"
        ProjectFile = "TradingSystem.Backtesting.csproj"
        Image = "tradingsystem-backtesting:latest"
        Port = 80
        Type = "Worker"
    }
)

Write-Host "=== Azure Trading System Container Deployment ===" -ForegroundColor Cyan

# Function to delete existing container apps if needed
function Remove-ExistingApps {
    param([switch]$Force)
    
    Write-Host "`nChecking for existing Container Apps..." -ForegroundColor Yellow
    $existingApps = @()
    
    foreach ($svc in $services) {
        $exists = az containerapp show --name $svc.Name --resource-group $ResourceGroup 2>$null
        if ($exists) {
            $existingApps += $svc.Name
        }
    }
    
    if ($existingApps.Count -gt 0) {
        Write-Host "Found existing apps: $($existingApps -join ', ')" -ForegroundColor Yellow
        
        if (-not $Force) {
            $response = Read-Host "Do you want to delete existing apps and recreate them? This can help resolve persistent issues. (Y/N)"
            if ($response -ne 'Y' -and $response -ne 'y') {
                return $false
            }
        }
        
        foreach ($appName in $existingApps) {
            Write-Host "  Deleting $appName..." -ForegroundColor Gray
            az containerapp delete --name $appName --resource-group $ResourceGroup --yes 2>&1 | Out-Null
        }
        
        Write-Host "  Waiting for deletions to complete..." -ForegroundColor Gray
        Start-Sleep -Seconds 10
        
        return $true
    }
    
    return $false
}

# Check Azure login
Write-Host "`nChecking Azure login..." -ForegroundColor Yellow
try {
    $account = az account show 2>$null | ConvertFrom-Json
    Write-Host "Logged in as: $($account.user.name)" -ForegroundColor Green
} catch {
    Write-Host "Not logged in. Please run: az login" -ForegroundColor Red
    exit 1
}

# Function to create Dockerfile
function Create-Dockerfile {
    param(
        [string]$Path,
        [string]$ProjectFile,
        [string]$Type
    )
    
    $projectDir = Split-Path -Leaf $Path
    $dockerfilePath = Join-Path $Path "Dockerfile"
    if (Test-Path $dockerfilePath) {
        Remove-Item $dockerfilePath -Force
    }
    $dllName = $ProjectFile -replace '\.csproj$', '.dll'
    $dockerfileContent = @"
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS base
WORKDIR /app
EXPOSE 80
EXPOSE 443

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Copy csproj and restore
COPY ["$projectDir/$ProjectFile", "$projectDir/"]
COPY ["TradingSystem.Core/TradingSystem.Core.csproj", "TradingSystem.Core/"]
RUN dotnet restore "$projectDir/$ProjectFile"

# Copy everything and build
COPY . .
RUN dotnet build "$projectDir/$ProjectFile" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "$projectDir/$ProjectFile" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .

ENV ASPNETCORE_URLS=http://+:80
ENV ASPNETCORE_ENVIRONMENT=Production

ENTRYPOINT ["dotnet", "$dllName"]
"@

    $dockerfileContent | Out-File -FilePath $dockerfilePath -Encoding UTF8
    Write-Host "Created Dockerfile: $dockerfilePath" -ForegroundColor Green
}

# Always delete and regenerate Dockerfiles for all services
Write-Host "`nDeleting old Dockerfiles and regenerating..." -ForegroundColor Yellow
foreach ($svc in $services) {
    $dockerfilePath = Join-Path $svc.Path "Dockerfile"
    if (Test-Path $dockerfilePath) {
        Remove-Item $dockerfilePath -Force
        Write-Host "  Deleted: $dockerfilePath" -ForegroundColor Gray
    }
    Create-Dockerfile -Path $svc.Path -ProjectFile $svc.ProjectFile -Type $svc.Type
}

if (-not $SkipBuild) {
    # Test local builds first (unless skipped)
    if (-not $SkipLocalBuild) {
        Write-Host "`n=== Testing Local Builds First ===" -ForegroundColor Yellow
        Write-Host "This ensures all projects compile correctly before Docker builds..." -ForegroundColor Gray
        
        $localBuildResults = @()
        $localBuildFailed = $false
        
        foreach ($svc in $services) {
            Write-Host "`nBuilding locally: $($svc.Name)" -ForegroundColor Cyan
            $projectPath = Join-Path $svc.Path $svc.ProjectFile
            
            # Clean before build
            Write-Host "  Cleaning project..." -ForegroundColor Gray
            $cleanResult = dotnet clean $projectPath -c Release 2>&1
            
            # Restore packages
            Write-Host "  Restoring packages..." -ForegroundColor Gray
            $restoreResult = dotnet restore $projectPath 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  ✗ Package restore failed" -ForegroundColor Red
                Write-Host $restoreResult -ForegroundColor Red
                $localBuildResults += @{ Name = $svc.Name; Status = 'Failed'; Stage = 'Restore' }
                $localBuildFailed = $true
                continue
            }
            
            # Build project
            Write-Host "  Building project..." -ForegroundColor Gray
            $buildResult = dotnet build $projectPath -c Release --no-restore 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  ✗ Build failed" -ForegroundColor Red
                Write-Host $buildResult -ForegroundColor Red
                $localBuildResults += @{ Name = $svc.Name; Status = 'Failed'; Stage = 'Build' }
                $localBuildFailed = $true
            } else {
                Write-Host "  ✓ Local build successful" -ForegroundColor Green
                $localBuildResults += @{ Name = $svc.Name; Status = 'Success'; Stage = 'Complete' }
            }
        }
        
        # Local build summary
        Write-Host "`n=== Local Build Summary ===" -ForegroundColor Yellow
        foreach ($r in $localBuildResults) {
            $color = if ($r.Status -eq 'Success') { 'Green' } else { 'Red' }
            Write-Host ("{0,-30} {1,-10} {2}" -f $r.Name, $r.Status, $r.Stage) -ForegroundColor $color
        }
        
        if ($localBuildFailed) {
            Write-Host "`nLocal builds failed. This usually indicates:" -ForegroundColor Yellow
            Write-Host "  - Missing NuGet packages" -ForegroundColor Gray
            Write-Host "  - Compilation errors in code" -ForegroundColor Gray
            Write-Host "  - Project reference issues" -ForegroundColor Gray
            
            $response = Read-Host "`nDo you want to continue with Docker builds anyway? (Y/N)"
            if ($response -ne 'Y' -and $response -ne 'y') {
                Write-Host "Exiting due to local build failures." -ForegroundColor Red
                exit 1
            }
        } else {
            Write-Host "`nAll local builds succeeded! Proceeding with Docker builds..." -ForegroundColor Green
        }
    }
    
    # Log in to ACR
    Write-Host "`nLogging in to ACR..." -ForegroundColor Yellow
    az acr login --name $AcrName
    
    # Build and push Docker images
    Write-Host "`n=== Docker Image Builds ===" -ForegroundColor Yellow
    $buildAttempts = 0
    $buildSuccesses = 0
    $buildResults = @()
    $pushResults = @()
    
    foreach ($svc in $services) {
        $imageFull = "$AcrName.azurecr.io/$($svc.Image)"
        $dockerfilePath = Join-Path $svc.Path "Dockerfile"
        $projectDir = Split-Path -Leaf $svc.Path
        Write-Host "`nBuilding Docker image: $imageFull" -ForegroundColor Cyan
        $buildAttempts++
        
        # Docker build with --no-cache to ensure fresh build
        $buildResult = docker build --no-cache -f $dockerfilePath -t $imageFull ./src 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $buildSuccesses++
            $buildResults += @{ Name = $svc.Name; Image = $imageFull; Status = 'Success'; Message = '' }
            Write-Host "✓ Docker build successful" -ForegroundColor Green
            
            # Push to ACR
            Write-Host "Pushing image: $imageFull" -ForegroundColor Cyan
            $pushResult = docker push $imageFull 2>&1
            if ($LASTEXITCODE -eq 0) {
                $pushResults += @{ Name = $svc.Name; Image = $imageFull; Status = 'Success'; Message = '' }
                Write-Host "✓ Push successful" -ForegroundColor Green
            } else {
                $pushResults += @{ Name = $svc.Name; Image = $imageFull; Status = 'Failed'; Message = $pushResult }
                Write-Host "✗ Push failed" -ForegroundColor Red
                Write-Host $pushResult -ForegroundColor Red
            }
        } else {
            $buildResults += @{ Name = $svc.Name; Image = $imageFull; Status = 'Failed'; Message = $buildResult }
            Write-Host "✗ Docker build failed" -ForegroundColor Red
            Write-Host $buildResult -ForegroundColor Red
        }
    }
    
    # Build summary table
    Write-Host "`n=== Docker Build Summary ===" -ForegroundColor Yellow
    foreach ($r in $buildResults) {
        $color = if ($r.Status -eq 'Success') { 'Green' } else { 'Red' }
        Write-Host ("{0,-30} {1,-10}" -f $r.Name, $r.Status) -ForegroundColor $color
    }
    
    # If more than half builds failed, abort
    if ($buildSuccesses -lt [math]::Ceiling($buildAttempts/2)) {
        Write-Host "More than half of Docker builds failed. Aborting deployment." -ForegroundColor Red
        exit 1
    }
    
    # If some but not all builds failed, prompt
    if ($buildSuccesses -ne $buildAttempts) {
        $response = Read-Host "Some Docker builds failed. Would you like to continue with deployment? (Y/N)"
        if ($response -ne 'Y' -and $response -ne 'y') {
            Write-Host "Exiting as requested due to Docker build failures." -ForegroundColor Red
            exit 1
        }
    }
    
    # Push summary table
    Write-Host "`n=== Push Summary ===" -ForegroundColor Yellow
    foreach ($r in $pushResults) {
        $color = if ($r.Status -eq 'Success') { 'Green' } else { 'Red' }
        Write-Host ("{0,-30} {1,-10}" -f $r.Name, $r.Status) -ForegroundColor $color
    }
    
    # If any push failed, abort (do not prompt)
    if ($pushResults | Where-Object { $_.Status -eq 'Failed' }) {
        Write-Host "One or more images failed to push. Aborting deployment." -ForegroundColor Red
        exit 1
    }
} else {
    # Skip build was specified
    Write-Host "`nSkipping builds as requested (-SkipBuild flag was used)" -ForegroundColor Yellow
}

# Get secrets from Key Vault
Write-Host "`nFetching secrets from Key Vault..." -ForegroundColor Yellow
$secretsRetrieved = $false
$secrets = @{}

if (-not $SkipSecrets) {
    try {
        # Get SQL Connection
        $SqlConnection = az keyvault secret show --vault-name $KeyVaultName --name SqlConnection --query value -o tsv 2>$null
        if ($SqlConnection) {
            $secrets["sqlconnection"] = $SqlConnection
            Write-Host "✓ Retrieved SQL Connection" -ForegroundColor Green
            if ($DebugMode) {
                Write-Host "[DEBUG] SQL Connection Length: $($SqlConnection.Length)" -ForegroundColor Magenta
                Write-Host "[DEBUG] SQL Connection First 20 chars: $($SqlConnection.Substring(0, [Math]::Min(20, $SqlConnection.Length)))..." -ForegroundColor Magenta
            }
            $secretsRetrieved = $true
        } else {
            Write-Host "✗ SQL Connection not found in Key Vault" -ForegroundColor Yellow
            Write-Host "  Creating dummy SQL connection secret..." -ForegroundColor Gray
            az keyvault secret set --vault-name $KeyVaultName --name SqlConnection --value "Server=dummy;Database=dummy;User Id=dummy;Password=dummy;" 2>&1 | Out-Null
            $SqlConnection = "Server=dummy;Database=dummy;User Id=dummy;Password=dummy;"
            $secrets["sqlconnection"] = $SqlConnection
        }
        
        # Get Redis Connection
        $RedisConnection = az keyvault secret show --vault-name $KeyVaultName --name RedisConnection --query value -o tsv 2>$null
        if ($RedisConnection) {
            # Fix Redis connection if hostname is missing
            if ($RedisConnection -match "^,password=") {
                Write-Host "  Fixing Redis connection string..." -ForegroundColor Yellow
                # Try to get Redis hostname
                $redisName = "trading-redis-9383"
                $redisHost = az redis show --name $redisName --resource-group $ResourceGroup --query hostName -o tsv 2>$null
                if ($redisHost) {
                    # Ensure we add the port number (6380 for SSL)
                    $RedisConnection = "${redisHost}:6380${RedisConnection}"
                    Write-Host "  Fixed Redis connection with host: $redisHost" -ForegroundColor Green
                    
                    # Update the Key Vault with the fixed connection string
                    Write-Host "  Updating Key Vault with fixed Redis connection..." -ForegroundColor Yellow
                    az keyvault secret set --vault-name $KeyVaultName --name RedisConnection --value $RedisConnection 2>&1 | Out-Null
                    Write-Host "  ✓ Key Vault updated" -ForegroundColor Green
                } else {
                    # Fallback if we can't get the host
                    Write-Host "  Warning: Could not retrieve Redis host, using placeholder" -ForegroundColor Yellow
                    $RedisConnection = "redis-placeholder.redis.cache.windows.net:6380${RedisConnection}"
                }
            }
            $secrets["redisconnection"] = $RedisConnection
            Write-Host "✓ Retrieved Redis Connection" -ForegroundColor Green
            if ($DebugMode) {
                Write-Host "[DEBUG] Redis Connection Length: $($RedisConnection.Length)" -ForegroundColor Magenta
                Write-Host "[DEBUG] Redis Connection First 20 chars: $($RedisConnection.Substring(0, [Math]::Min(20, $RedisConnection.Length)))..." -ForegroundColor Magenta
            }
            $secretsRetrieved = $true
        } else {
            Write-Host "✗ Redis Connection not found in Key Vault" -ForegroundColor Yellow
            Write-Host "  Creating dummy Redis connection secret..." -ForegroundColor Gray
            az keyvault secret set --vault-name $KeyVaultName --name RedisConnection --value "dummy.redis.cache.windows.net:6380,password=dummy,ssl=True,abortConnect=False" 2>&1 | Out-Null
            $RedisConnection = "dummy.redis.cache.windows.net:6380,password=dummy,ssl=True,abortConnect=False"
            $secrets["redisconnection"] = $RedisConnection
        }
        
        if ($DebugMode) {
            Write-Host "`n[DEBUG] Secrets Dictionary Contents:" -ForegroundColor Magenta
            foreach ($key in $secrets.Keys) {
                Write-Host "[DEBUG]   Key: $key, Value Length: $($secrets[$key].Length)" -ForegroundColor Magenta
            }
        }
        
    } catch {
        Write-Host "Error retrieving secrets from Key Vault: $_" -ForegroundColor Red
    }
} else {
    Write-Host "Skipping secrets retrieval as requested (-SkipSecrets flag was used)" -ForegroundColor Yellow
}

# Ensure Container Apps Environment exists
Write-Host "`nChecking Container Apps Environment..." -ForegroundColor Yellow
$envExists = az containerapp env show --name $ContainerAppEnv --resource-group $ResourceGroup 2>$null

if (-not $envExists) {
    Write-Host "✗ Container Apps Environment '$ContainerAppEnv' not found" -ForegroundColor Red
    Write-Host "Creating Container Apps Environment..." -ForegroundColor Yellow
    
    # First create Log Analytics workspace if it doesn't exist
    $logWorkspaceName = "log-$ContainerAppEnv"
    Write-Host "  Checking Log Analytics workspace..." -ForegroundColor Gray
    
    $logExists = az monitor log-analytics workspace show `
        --resource-group $ResourceGroup `
        --workspace-name $logWorkspaceName 2>$null
    
    if (-not $logExists) {
        Write-Host "  Creating Log Analytics workspace: $logWorkspaceName" -ForegroundColor Yellow
        $createLogResult = az monitor log-analytics workspace create `
            --resource-group $ResourceGroup `
            --workspace-name $logWorkspaceName `
            --location $Location `
            --output none 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ✗ Failed to create Log Analytics workspace" -ForegroundColor Red
            Write-Host $createLogResult -ForegroundColor Red
            Write-Host "`nCannot proceed without Container Apps Environment. Exiting." -ForegroundColor Red
            exit 1
        }
        Write-Host "  ✓ Log Analytics workspace created" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Log Analytics workspace exists" -ForegroundColor Green
    }
    
    # Get workspace details
    Write-Host "  Getting workspace details..." -ForegroundColor Gray
    $workspaceId = az monitor log-analytics workspace show `
        --resource-group $ResourceGroup `
        --workspace-name $logWorkspaceName `
        --query customerId -o tsv
    
    $workspaceKey = az monitor log-analytics workspace get-shared-keys `
        --resource-group $ResourceGroup `
        --workspace-name $logWorkspaceName `
        --query primarySharedKey -o tsv
    
    if (-not $workspaceId -or -not $workspaceKey) {
        Write-Host "  ✗ Failed to get Log Analytics workspace details" -ForegroundColor Red
        Write-Host "Cannot proceed without workspace details. Exiting." -ForegroundColor Red
        exit 1
    }
    
    # Create Container Apps Environment
    Write-Host "  Creating Container Apps Environment: $ContainerAppEnv" -ForegroundColor Yellow
    $createEnvResult = az containerapp env create `
        --name $ContainerAppEnv `
        --resource-group $ResourceGroup `
        --location $Location `
        --logs-workspace-id $workspaceId `
        --logs-workspace-key $workspaceKey `
        --output none 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Container Apps Environment created successfully!" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to create Container Apps Environment" -ForegroundColor Red
        Write-Host $createEnvResult -ForegroundColor Red
        Write-Host "`nCannot proceed without Container Apps Environment. Exiting." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "✓ Container Apps Environment exists: $ContainerAppEnv" -ForegroundColor Green
}

# Ensure Container Apps can access ACR
Write-Host "`nConfiguring ACR access for Container Apps..." -ForegroundColor Yellow

# Get ACR credentials
$acrUsername = az acr credential show --name $AcrName --query username -o tsv 2>$null
$acrPassword = az acr credential show --name $AcrName --query "passwords[0].value" -o tsv 2>$null

if ($acrUsername -and $acrPassword) {
    Write-Host "✓ Retrieved ACR credentials" -ForegroundColor Green
    
    if ($DebugMode) {
        Write-Host "[DEBUG] ACR Username: $acrUsername" -ForegroundColor Magenta
        Write-Host "[DEBUG] ACR Server: $AcrName.azurecr.io" -ForegroundColor Magenta
    }
} else {
    Write-Host "✗ Failed to retrieve ACR credentials" -ForegroundColor Red
    Write-Host "Ensure you have access to ACR: $AcrName" -ForegroundColor Yellow
}

# Deploy/update Container Apps
Write-Host "`nDeploying Container Apps..." -ForegroundColor Yellow
$deployResults = @()

foreach ($svc in $services) {
    $imageFull = "$AcrName.azurecr.io/$($svc.Image)"
    Write-Host "`nDeploying: $($svc.Name)" -ForegroundColor Green
    
    # Check if app exists
    $exists = az containerapp show --name $svc.Name --resource-group $ResourceGroup 2>$null
    $deployStatus = ''
    $deployMsg = ''
    
    if ($exists) {
        Write-Host "  Updating existing app..." -ForegroundColor Yellow
        # Update with proper secret syntax
        if ($secrets.Count -gt 0 -and -not $SkipSecrets) {
            # First update the image
            Write-Host "    Step 1: Updating image..." -ForegroundColor Gray
            $updateImageArgs = @(
                "containerapp", "update",
                "--name", $svc.Name,
                "--resource-group", $ResourceGroup,
                "--image", $imageFull
            )
            
            $cmdOutput = & az @updateImageArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "    Failed to update image" -ForegroundColor Red
                Write-Host $cmdOutput -ForegroundColor Red
            }
            
            # Then set secrets using containerapp secret set
            Write-Host "    Step 2: Setting secrets..." -ForegroundColor Gray
            foreach ($key in $secrets.Keys) {
                $secretValue = $secrets[$key]
                Write-Host "      Setting secret: $key" -ForegroundColor Gray
                
                $setSecretArgs = @(
                    "containerapp", "secret", "set",
                    "--name", $svc.Name,
                    "--resource-group", $ResourceGroup,
                    "--secrets", "${key}=${secretValue}"
                )
                
                if ($DebugMode) {
                    # Don't show actual secret values in debug
                    $debugSecret = if ($key -eq "sqlconnection") { "***SQL_CONNECTION***" } else { "***REDIS_CONNECTION***" }
                    Write-Host "[DEBUG] Setting secret $key with value length: $($secretValue.Length)" -ForegroundColor Magenta
                }
                
                $cmdOutput = & az @setSecretArgs 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "      Failed to set secret $key" -ForegroundColor Red
                    if ($DebugMode) {
                        Write-Host $cmdOutput -ForegroundColor Red
                    }
                }
            }
            
            # Finally update environment variables
            Write-Host "    Step 3: Setting environment variables..." -ForegroundColor Gray
            $updateEnvArgs = @(
                "containerapp", "update",
                "--name", $svc.Name,
                "--resource-group", $ResourceGroup,
                "--set-env-vars",
                "ASPNETCORE_ENVIRONMENT=Production",
                "SQLCONNECTION=secretref:sqlconnection",
                "REDISCONNECTION=secretref:redisconnection"
            )
            
            if ($DebugMode) {
                Write-Host "[DEBUG] Update Env Command:" -ForegroundColor Magenta
                Write-Host "az $($updateEnvArgs -join ' ')" -ForegroundColor Magenta
            }
            
            $cmdOutput = & az @updateEnvArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "    Failed to set environment variables" -ForegroundColor Red
                Write-Host $cmdOutput -ForegroundColor Red
            }
        } else {
            az containerapp update `
                --name $svc.Name `
                --resource-group $ResourceGroup `
                --image $imageFull `
                --set-env-vars "ASPNETCORE_ENVIRONMENT=Production"
        }
    } else {
        Write-Host "  Creating new app..." -ForegroundColor Yellow
        # Create with proper syntax
        if ($secrets.Count -gt 0 -and -not $SkipSecrets) {
            # Step 1: Create the app with just the image and registry credentials
            Write-Host "  Step 1: Creating container app with ACR authentication..." -ForegroundColor Gray
            $createArgs = @(
                "containerapp", "create",
                "--name", $svc.Name,
                "--resource-group", $ResourceGroup,
                "--environment", $ContainerAppEnv,
                "--image", $imageFull,
                "--target-port", $svc.Port.ToString(),
                "--ingress", "external",
                "--min-replicas", "0",
                "--max-replicas", "1"
            )
            
            # Add registry credentials if available
            if ($acrUsername -and $acrPassword) {
                $createArgs += "--registry-server"
                $createArgs += "$AcrName.azurecr.io"
                $createArgs += "--registry-username"
                $createArgs += $acrUsername
                $createArgs += "--registry-password"
                $createArgs += $acrPassword
            }
            
            if ($DebugMode) {
                Write-Host "[DEBUG] Initial Create Command:" -ForegroundColor Magenta
                # Don't show password in debug output
                $debugArgs = $createArgs -replace $acrPassword, "***PASSWORD***"
                Write-Host "az $($debugArgs -join ' ')" -ForegroundColor Magenta
            }
            
            # Execute initial creation
            $cmdOutput = & az @createArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[ERROR] Failed to create container app" -ForegroundColor Red
                Write-Host $cmdOutput -ForegroundColor Red
                $deployStatus = 'Failed'
                $deployMsg = "Error code: $LASTEXITCODE"
                $deployResults += @{ Name = $svc.Name; Status = $deployStatus; Message = $deployMsg }
                continue
            }
            
            Write-Host "  ✓ Container app created" -ForegroundColor Green
            
            # Step 2: Add secrets
            Write-Host "  Step 2: Adding secrets..." -ForegroundColor Gray
            foreach ($key in $secrets.Keys) {
                $secretValue = $secrets[$key]
                Write-Host "    Setting secret: $key" -ForegroundColor Gray
                
                $setSecretArgs = @(
                    "containerapp", "secret", "set",
                    "--name", $svc.Name,
                    "--resource-group", $ResourceGroup,
                    "--secrets", "${key}=${secretValue}"
                )
                
                if ($DebugMode) {
                    Write-Host "[DEBUG] Setting secret $key with value length: $($secretValue.Length)" -ForegroundColor Magenta
                }
                
                $cmdOutput = & az @setSecretArgs 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "    Failed to set secret $key" -ForegroundColor Red
                    if ($DebugMode) {
                        Write-Host $cmdOutput -ForegroundColor Red
                    }
                }
            }
            
            # Step 3: Update environment variables
            Write-Host "  Step 3: Setting environment variables..." -ForegroundColor Gray
            $updateEnvArgs = @(
                "containerapp", "update",
                "--name", $svc.Name,
                "--resource-group", $ResourceGroup,
                "--set-env-vars",
                "ASPNETCORE_ENVIRONMENT=Production",
                "SQLCONNECTION=secretref:sqlconnection",
                "REDISCONNECTION=secretref:redisconnection"
            )
            
            if ($DebugMode) {
                Write-Host "[DEBUG] Update Env Command:" -ForegroundColor Magenta
                Write-Host "az $($updateEnvArgs -join ' ')" -ForegroundColor Magenta
            }
            
            $cmdOutput = & az @updateEnvArgs 2>&1
            if ($LASTEXITCODE -eq 0) {
                $deployStatus = 'Success'
                # Get the URL
                $appUrl = az containerapp show --name $svc.Name --resource-group $ResourceGroup --query "properties.configuration.ingress.fqdn" -o tsv 2>$null
                if ($appUrl) {
                    $deployMsg = "URL: https://$appUrl"
                    Write-Host "  URL: https://$appUrl" -ForegroundColor Cyan
                }
                Write-Host "  ✓ Deployment successful" -ForegroundColor Green
            } else {
                $deployStatus = 'Failed'
                $deployMsg = "Failed to set environment variables"
                Write-Host "  ✗ Failed to set environment variables" -ForegroundColor Red
                Write-Host $cmdOutput -ForegroundColor Red
            }
        } else {
            # Create without secrets
            $createArgs = @(
                "containerapp", "create",
                "--name", $svc.Name,
                "--resource-group", $ResourceGroup,
                "--environment", $ContainerAppEnv,
                "--image", $imageFull,
                "--target-port", $svc.Port.ToString(),
                "--ingress", "external",
                "--min-replicas", "0",
                "--max-replicas", "1"
            )
            
            # Add registry credentials if available
            if ($acrUsername -and $acrPassword) {
                $createArgs += "--registry-server"
                $createArgs += "$AcrName.azurecr.io"
                $createArgs += "--registry-username"
                $createArgs += $acrUsername
                $createArgs += "--registry-password"
                $createArgs += $acrPassword
            }
            
            $createArgs += "--env-vars"
            $createArgs += "ASPNETCORE_ENVIRONMENT=Production"
            
            & az @createArgs
        }
    }
    
    if ($LASTEXITCODE -eq 0 -and $deployStatus -ne 'Failed') {
        $deployStatus = 'Success'
        # Get the URL
        $appUrl = az containerapp show --name $svc.Name --resource-group $ResourceGroup --query "properties.configuration.ingress.fqdn" -o tsv 2>$null
        if ($appUrl) {
            $deployMsg = "URL: https://$appUrl"
            Write-Host "  URL: https://$appUrl" -ForegroundColor Cyan
        }
        Write-Host "  ✓ Deployment successful" -ForegroundColor Green
    } elseif ($deployStatus -ne 'Failed') {
        $deployStatus = 'Failed'
        $deployMsg = "Error code: $LASTEXITCODE"
        Write-Host "  ✗ Deployment failed" -ForegroundColor Red
    }
    
    if ($deployStatus) {
        $deployResults += @{ Name = $svc.Name; Status = $deployStatus; Message = $deployMsg }
    }
}

# Deployment summary
Write-Host "`n=== Deployment Summary ===" -ForegroundColor Yellow
foreach ($r in $deployResults) {
    $color = if ($r.Status -eq 'Success') { 'Green' } else { 'Red' }
    Write-Host ("{0,-30} {1,-10} {2}" -f $r.Name, $r.Status, $r.Message) -ForegroundColor $color
}

# Handle failed deployments
if ($deployResults | Where-Object { $_.Status -eq 'Failed' }) {
    $response = Read-Host "Some deployments failed. Would you like to retry failed deployments (R), skip and continue (S), or abort (A)? [R/S/A]"
    if ($response -eq 'A' -or $response -eq 'a') {
        Write-Host "Exiting as requested due to deployment failures." -ForegroundColor Red
        exit 1
    } elseif ($response -eq 'R' -or $response -eq 'r') {
        foreach ($svc in $services) {
            $deployResult = $deployResults | Where-Object { $_.Name -eq $svc.Name }
            if ($deployResult.Status -eq 'Failed') {
                $imageFull = "$AcrName.azurecr.io/$($svc.Image)"
                Write-Host "Retrying deployment for: $($svc.Name)" -ForegroundColor Yellow
                
                # Check if app exists
                $exists = az containerapp show --name $svc.Name --resource-group $ResourceGroup 2>$null
                
                if ($exists) {
                    Write-Host "  Updating existing app..." -ForegroundColor Yellow
                    if ($secrets.Count -gt 0 -and -not $SkipSecrets) {
                        # First update the image
                        Write-Host "    Updating image on retry..." -ForegroundColor Gray
                        $updateImageArgs = @(
                            "containerapp", "update",
                            "--name", $svc.Name,
                            "--resource-group", $ResourceGroup,
                            "--image", $imageFull
                        )
                        
                        & az @updateImageArgs 2>&1 | Out-Null
                        
                        # Set secrets
                        foreach ($key in $secrets.Keys) {
                            $secretValue = $secrets[$key]
                            $setSecretArgs = @(
                                "containerapp", "secret", "set",
                                "--name", $svc.Name,
                                "--resource-group", $ResourceGroup,
                                "--secrets", "${key}=${secretValue}"
                            )
                            & az @setSecretArgs 2>&1 | Out-Null
                        }
                        
                        # Update environment variables
                        $updateEnvArgs = @(
                            "containerapp", "update",
                            "--name", $svc.Name,
                            "--resource-group", $ResourceGroup,
                            "--set-env-vars",
                            "ASPNETCORE_ENVIRONMENT=Production",
                            "SQLCONNECTION=secretref:sqlconnection",
                            "REDISCONNECTION=secretref:redisconnection"
                        )
                        
                        & az @updateEnvArgs
                    } else {
                        az containerapp update `
                            --name $svc.Name `
                            --resource-group $ResourceGroup `
                            --image $imageFull `
                            --set-env-vars "ASPNETCORE_ENVIRONMENT=Production"
                    }
                } else {
                    Write-Host "  Creating new app..." -ForegroundColor Yellow
                    if ($secrets.Count -gt 0 -and -not $SkipSecrets) {
                        # Build create command with proper argument handling
                        $createArgs = @(
                            "containerapp", "create",
                            "--name", $svc.Name,
                            "--resource-group", $ResourceGroup,
                            "--environment", $ContainerAppEnv,
                            "--image", $imageFull,
                            "--target-port", $svc.Port.ToString(),
                            "--ingress", "external",
                            "--min-replicas", "0",
                            "--max-replicas", "1"
                        )
                        
                        # Add registry credentials if available
                        if ($acrUsername -and $acrPassword) {
                            $createArgs += "--registry-server"
                            $createArgs += "$AcrName.azurecr.io"
                            $createArgs += "--registry-username"
                            $createArgs += $acrUsername
                            $createArgs += "--registry-password"
                            $createArgs += $acrPassword
                        }
                        
                        # Add each secret as a separate argument
                        foreach ($key in $secrets.Keys) {
                            $secretValue = $secrets[$key]
                            $createArgs += "--secrets"
                            $createArgs += "${key}=${secretValue}"
                        }
                        
                        # Add environment variables
                        $createArgs += "--env-vars"
                        $createArgs += "ASPNETCORE_ENVIRONMENT=Production"
                        $createArgs += "SQLCONNECTION=secretref:sqlconnection"
                        $createArgs += "REDISCONNECTION=secretref:redisconnection"
                        
                        # Execute using call operator
                        & az @createArgs
                    } else {
                        az containerapp create `
                            --name $svc.Name `
                            --resource-group $ResourceGroup `
                            --environment $ContainerAppEnv `
                            --image $imageFull `
                            --target-port $svc.Port `
                            --ingress external `
                            --min-replicas 0 `
                            --max-replicas 1 `
                            --env-vars "ASPNETCORE_ENVIRONMENT=Production"
                    }
                }
            }
        }
        Write-Host "Retry complete. Please check the summary above for final status." -ForegroundColor Yellow
    }
}

Write-Host "`n=== Deployment Summary ===" -ForegroundColor Cyan

# Show status of all apps
Write-Host "`nChecking deployment status..." -ForegroundColor Yellow
$deployedApps = az containerapp list --resource-group $ResourceGroup --query "[].{Name:name, Status:properties.provisioningState, URL:properties.configuration.ingress.fqdn}" -o table 2>$null

if ($deployedApps) {
    Write-Host $deployedApps
}

Write-Host "`nDeployment complete!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Check application logs: az containerapp logs show --name [app-name] --resource-group $ResourceGroup" -ForegroundColor Gray
Write-Host "2. Scale apps up: .\Restart-AzureServices.ps1" -ForegroundColor Gray
Write-Host "3. View in portal: https://portal.azure.com/#resource/subscriptions/{subscriptionId}/resourceGroups/$ResourceGroup/overview" -ForegroundColor Gray

if (-not $secretsRetrieved) {
    Write-Host "`nWARNING: No real secrets were found in Key Vault. Dummy values were used." -ForegroundColor Yellow
    Write-Host "To add real secrets, run:" -ForegroundColor Yellow
    Write-Host "  az keyvault secret set --vault-name $KeyVaultName --name SqlConnection --value 'your-real-connection-string'" -ForegroundColor Gray
    Write-Host "  az keyvault secret set --vault-name $KeyVaultName --name RedisConnection --value 'your-real-redis-connection'" -ForegroundColor Gray
}

# Additional helper to fix Redis connection if needed
Write-Host "`nIf you still have Redis connection issues, run this helper command:" -ForegroundColor Yellow
Write-Host @'
# Fix Redis Connection Helper
$redisHost = az redis show --name trading-redis-8632 --resource-group trading-hero-rgp --query hostName -o tsv
$redisKey = az redis list-keys --name trading-redis-8632 --resource-group trading-hero-rgp --query primaryKey -o tsv
$fixedRedis = "${redisHost}:6380,password=${redisKey},ssl=True,abortConnect=False"
az keyvault secret set --vault-name kvtrading8632 --name RedisConnection --value $fixedRedis
'@ -ForegroundColor Gray