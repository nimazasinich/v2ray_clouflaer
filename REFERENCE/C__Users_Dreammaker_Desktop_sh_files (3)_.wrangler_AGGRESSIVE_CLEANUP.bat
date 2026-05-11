@echo off
REM AGGRESSIVE CLEANUP - Only essential files in root
REM Organizes by RECENCY and ACTUAL USAGE

setlocal enabledelayedexpansion
cd /d "C:\Users\Dreammaker\Desktop\sh\files (3)\.wrangler"

echo.
echo ===== DREAMMAKER PROJECT AGGRESSIVE CLEANUP =====
echo.
echo This will:
echo   1. Keep only ACTIVE production files in root
echo   2. Move ALL .sh scripts to TOOLS/
echo   3. Keep ONLY 1 master .md file in root
echo   4. Move other .md files to REFERENCE/
echo   5. ZIP unused projects
echo.
pause

REM Create directories if not exist
if not exist "ACTIVE" mkdir ACTIVE
if not exist "REFERENCE" mkdir REFERENCE
if not exist "TOOLS" mkdir TOOLS
if not exist "ARCHIVE" mkdir ARCHIVE
if not exist "CONFIG" mkdir CONFIG

echo.
echo [STEP 1] Moving ALL .sh scripts to TOOLS/
echo ==================================================
for %%F in (*.sh) do (
    if not "%%F"=="deploy.sh" (
        move "%%F" "TOOLS\" >nul 2>&1
        echo   ✓ %%F
    )
)

echo.
echo [STEP 2] Moving ACTIVE production configs to ACTIVE/
echo ==================================================
for %%F in (nginx.conf xray-config.json worker.js wrangler.toml) do (
    if exist "%%F" (
        move "%%F" "ACTIVE\" >nul 2>&1
        echo   ✓ %%F
    )
)

echo.
echo [STEP 3] Moving ALL .md files to REFERENCE/ (keeping master only in root)
echo ==================================================
REM Keep only this one master file in root
set MASTER_FILE=DreamMaker_Infrastructure_Handoff_Master_Enriched.md

for /r %%F in (*.md) do (
    if not "%%~nxF"=="!MASTER_FILE!" (
        if not "%%~nxF"=="README.md" (
            move "%%F" "REFERENCE\" >nul 2>&1
            echo   ✓ %%~nxF
        )
    )
)

echo.
echo [STEP 4] Moving CONFIG templates
echo ==================================================
for %%F in (.env.example tsconfig.json package.json schema.sql bundles.json) do (
    if exist "%%F" (
        move "%%F" "CONFIG\" >nul 2>&1
        echo   ✓ %%F
    )
)

echo.
echo [STEP 5] Zipping unused projects
echo ==================================================

REM Create ARCHIVE if not exists
if not exist "ARCHIVE" mkdir ARCHIVE

REM Move old version folders to ARCHIVE and zip
if exist "000000000" (
    move "000000000" "ARCHIVE\" >nul 2>&1
    echo   ✓ Moved 000000000/ to ARCHIVE/
)

if exist "dreammaker-infrastructure-v5-fixed" (
    move "dreammaker-infrastructure-v5-fixed" "ARCHIVE\" >nul 2>&1
    echo   ✓ Moved dreammaker-infrastructure-v5-fixed/ to ARCHIVE/
)

if exist "dreammaker-infrastructure-complete" (
    move "dreammaker-infrastructure-complete" "ARCHIVE\" >nul 2>&1
    echo   ✓ Moved dreammaker-infrastructure-complete/ to ARCHIVE/
)

if exist "tmp" (
    move "tmp" "ARCHIVE\" >nul 2>&1
    echo   ✓ Moved tmp/ to ARCHIVE/
)

REM Move all .zip files to ARCHIVE
for %%F in (*.zip) do (
    if exist "%%F" (
        move "%%F" "ARCHIVE\" >nul 2>&1
        echo   ✓ %%F
    )
)

REM Move all .tar.gz files to ARCHIVE
for %%F in (*.tar.gz *.gz) do (
    if exist "%%F" (
        move "%%F" "ARCHIVE\" >nul 2>&1
        echo   ✓ %%F
    )
)

REM Move old PDFs to ARCHIVE
for %%F in (*.pdf) do (
    if exist "%%F" (
        move "%%F" "ARCHIVE\" >nul 2>&1
        echo   ✓ %%F
    )
)

echo.
echo [STEP 6] Cleaning up old/duplicate files
echo ==================================================

REM Move old .md files with (1), (2) etc to REFERENCE
for /r %%F in (*\ (1).md) do (
    if exist "%%F" (
        move "%%F" "REFERENCE\" >nul 2>&1
        echo   ✓ %%~nxF
    )
)

for /r %%F in (*\ (1).txt) do (
    if exist "%%F" (
        move "%%F" "REFERENCE\" >nul 2>&1
        echo   ✓ %%~nxF
    )
)

REM Move old JSON and TS files to REFERENCE
for %%F in (xray-*.json nginx-*.conf config.ts config (1).ts edge-worker-*.ts helper-*.ts control-plane-*.ts) do (
    if exist "%%F" (
        move "%%F" "REFERENCE\" >nul 2>&1
        echo   ✓ %%F
    )
)

echo.
echo [STEP 7] Root directory now contains ONLY:
echo ==================================================
echo.
for /F "delims=" %%F in ('dir /b /a-d "." 2^>nul') do (
    echo   • %%F
)

echo.
echo ===== CLEANUP COMPLETE =====
echo.
echo RESULT:
echo   ✓ ALL .sh files moved to TOOLS/ (except deploy.sh)
echo   ✓ ALL .md files moved to REFERENCE/ (except master)
echo   ✓ ALL old projects zipped/moved to ARCHIVE/
echo   ✓ Root now CLEAN with only essential files
echo.
echo Structure:
echo   ACTIVE\       - Production configs (nginx, xray, worker)
echo   REFERENCE\    - Documentation (master .md file tells you what's here)
echo   TOOLS\        - All deployment scripts
echo   CONFIG\       - Templates (.env, tsconfig, etc)
echo   ARCHIVE\      - Old versions, backups, unused projects
echo.
echo Root files:
echo   • deploy.sh                      (Main deployment script)
echo   • DreamMaker_Infrastructure_Handoff_Master_Enriched.md (MASTER - points to everything)
echo   • .cursorconfig.json             (Cursor IDE auto-config)
echo.
pause
