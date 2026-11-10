@echo off
:: Batch script to fix Windows 11 24H2 SMB connection to ZyXEL NSA210
echo ========================================================
echo  Configuring Windows 11 SMB for ZyXEL NSA210
echo ========================================================

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Requesting Administrator privileges...
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo [+] Disabling SMB Client Mandatory Signing...
powershell -NoProfile -Command "Set-SmbClientConfiguration -RequireSecuritySignature $false -Confirm:$false"

echo [+] Enabling Insecure Guest Logons...
powershell -NoProfile -Command "Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -Confirm:$false"

echo [+] Setting LanmanWorkstation registry keys...
reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v AllowInsecureGuestAuth /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v RequireSecuritySignature /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v EnableSecuritySignature /t REG_DWORD /d 0 /f

echo [+] Restarting Workstation service...
powershell -NoProfile -Command "Restart-Service LanmanWorkstation -Force"

echo ========================================================
echo  SMB Configuration Complete!
echo ========================================================
echo Testing connection to \\192.168.1.69...
net view \\192.168.1.69
echo.
pause
