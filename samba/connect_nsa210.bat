@echo off
chcp 65001 >nul
title Connect ZyXEL NSA210 Network Drive

set "NAS_IP=192.168.1.69"
set "DRIVE_LETTER=U:"
set "SHARE_NAME=download"

echo ========================================================
echo  Connect ZyXEL NSA210 Share Drive
echo  Target: \\%NAS_IP%\%SHARE_NAME%  -^>  %DRIVE_LETTER%
echo ========================================================
echo.

echo [*] Ping checking %NAS_IP% ...
ping -n 1 -w 1500 %NAS_IP% >nul 2>&1
if errorlevel 1 (
    echo.
    echo [X] Error: Cannot ping %NAS_IP%
    echo     Please check your network cable or NAS power.
    echo.
    pause
    exit /b 1
)
echo [+] Ping OK!

echo [*] Checking drive %DRIVE_LETTER% ...
net use %DRIVE_LETTER% >nul 2>&1
if not errorlevel 1 (
    echo [*] Drive %DRIVE_LETTER% already connected. Refreshing...
    net use %DRIVE_LETTER% /delete /y >nul 2>&1
)

echo [*] Mapping %DRIVE_LETTER% to \\%NAS_IP%\%SHARE_NAME% ...
net use %DRIVE_LETTER% "\\%NAS_IP%\%SHARE_NAME%" /persistent:yes >nul 2>&1

if not errorlevel 1 (
    echo.
    echo ========================================================
    echo  [OK] Connected successfully! Drive %DRIVE_LETTER% is ready.
    echo ========================================================
    echo.
    echo Opening File Explorer to %DRIVE_LETTER% ...
    start "" explorer.exe "%DRIVE_LETTER%\"
) else (
    echo.
    echo [X] Failed to connect drive.
    echo.
    echo Tips:
    echo 1. Make sure fix_smb.bat was executed as Administrator.
    echo 2. If SMB 1.0 was just enabled, please Restart your PC.
    echo.
    pause
    exit /b 1
)

ping 127.0.0.1 -n 3 >nul 2>&1
exit /b 0
