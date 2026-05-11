#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Download live DreamMaker workers from Cloudflare to local ACTIVE/ directory
    
.DESCRIPTION
    Fetches dreammaker-tier0, dreammaker-tier1, and hiddify-panel-proxy
    scripts from Cloudflare Workers and saves to ACTIVE/ with proper naming.
    
.EXAMPLE
    .\download-workers.ps1
#>

$ErrorActionPreference = 'Stop'

# Configuration
$wranglerPath = "C:\Users\Dreammaker\Desktop\sh\files (3)\.wrangler"
$activePath = Join-Path $wranglerPath "ACTIVE"
$envFile = Join-Path $wranglerPath ".env"

Write-Host "📥 DreamMaker Worker Download Script" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

# Check prerequisites
Write-Host "`n📋 Checking prerequisites..." -ForegroundColor Yellow

if (-not (Test-Path $wranglerPath)) {
    Write-Host "❌ ERROR: .wrangler directory not found at $wranglerPath" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ .wrangler directory found" -ForegroundColor Green

if (-not (Test-Path $activePath)) {
    Write-Host "❌ ERROR: ACTIVE directory not found" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ ACTIVE directory found" -ForegroundColor Green

if (-not (Test-Path $envFile)) {
    Write-Host "⚠️  WARNING: .env not found. Using existing environment variables." -ForegroundColor Yellow
} else {
    Write-Host "  ✓ .env file found" -ForegroundColor Green
}

# Check if wrangler is installed
Write-Host "`n🔍 Checking for wrangler CLI..." -ForegroundColor Yellow
try {
    $wranglerVersion = wrangler --version 2>&1
    Write-Host "  ✓ wrangler found: $wranglerVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ ERROR: wrangler CLI not found. Install with: npm install -g wrangler" -ForegroundColor Red
    exit 1
}

# Download workers
Write-Host "`n📥 Downloading workers from Cloudflare..." -ForegroundColor Cyan

$workers = @(
    @{
        name = "dreammaker-tier0"
        output = "tier0.js"
        description = "Subscription builder (fetch handler)"
    },
    @{
        name = "dreammaker-tier1"
        output = "tier1.js"
        description = "Health monitor (scheduled handler)"
    },
    @{
        name = "hiddify-panel-proxy"
        output = "hiddify-panel-proxy.js"
        description = "Admin panel proxy"
    }
)

$failed = @()
$successful = @()

foreach ($worker in $workers) {
    Write-Host "`n  [1/3] Downloading $($worker.name)..." -ForegroundColor Cyan
    Write-Host "        $($worker.description)" -ForegroundColor Gray
    
    $outputPath = Join-Path $activePath $worker.output
    
    try {
        # Change to ACTIVE directory for download
        Push-Location $activePath
        
        wrangler workers download $worker.name -o $worker.output 2>&1 | ForEach-Object {
            if ($_ -match "error|Error|ERROR") {
                Write-Host "        ⚠️  $_" -ForegroundColor Yellow
            }
        }
        
        Pop-Location
        
        if (Test-Path $outputPath) {
            $size = (Get-Item $outputPath).Length / 1KB
            Write-Host "        ✓ Downloaded: $([math]::Round($size, 1)) KB" -ForegroundColor Green
            $successful += $worker.name
        } else {
            Write-Host "        ❌ Download failed (file not created)" -ForegroundColor Red
            $failed += $worker.name
        }
    } catch {
        Write-Host "        ❌ ERROR: $_" -ForegroundColor Red
        $failed += $worker.name
    }
}

# Summary
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "📊 Download Summary" -ForegroundColor Cyan

if ($successful.Count -gt 0) {
    Write-Host "`n✅ Successfully downloaded ($($successful.Count)/3):" -ForegroundColor Green
    foreach ($name in $successful) {
        Write-Host "   ✓ $name" -ForegroundColor Green
    }
}

if ($failed.Count -gt 0) {
    Write-Host "`n❌ Failed to download ($($failed.Count)/3):" -ForegroundColor Red
    foreach ($name in $failed) {
        Write-Host "   ✗ $name" -ForegroundColor Red
    }
    Write-Host "`n💡 Troubleshooting tips:" -ForegroundColor Yellow
    Write-Host "   • Check CLOUDFLARE_API_TOKEN in .env" -ForegroundColor Gray
    Write-Host "   • Run: wrangler login" -ForegroundColor Gray
    Write-Host "   • Verify worker names exist: wrangler workers list" -ForegroundColor Gray
}

if ($successful.Count -eq 3) {
    Write-Host "`n🎉 All workers downloaded successfully!" -ForegroundColor Green
    Write-Host "`n📄 Files in ACTIVE/:" -ForegroundColor Cyan
    Get-ChildItem $activePath -File | Where-Object { $_.Extension -eq '.js' } | ForEach-Object {
        Write-Host "   ✓ $($_.Name) ($([math]::Round($_.Length / 1KB, 1)) KB)" -ForegroundColor Green
    }
}

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

# Next steps
Write-Host "📋 Next Steps:" -ForegroundColor Yellow
Write-Host "   1. Review tier0.js, tier1.js in ACTIVE/" -ForegroundColor Gray
Write-Host "   2. Compare with STRATEGY_REPORT.md for version info" -ForegroundColor Gray
Write-Host "   3. Check wrangler.toml for KV/DB bindings" -ForegroundColor Gray
Write-Host "   4. Run: wrangler deploy --dry-run" -ForegroundColor Gray
Write-Host "`n"

exit 0
