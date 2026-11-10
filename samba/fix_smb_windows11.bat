@echo off
chcp 65001 >nul
echo ========================================================
echo  Configuring Windows 11 SMB for ZyXEL NSA210
echo ========================================================

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] กำลังขอสิทธิ์ Administrator...
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo [+] 1. กำลังเปิดใช้งานฟีเจอร์ SMB 1.0 Client ผ่าน DISM...
dism.exe /online /enable-feature /featurename:SMB1Protocol /featurename:SMB1Protocol-Client /all /norestart

echo [+] 2. ปลดล็อก SMB Mandatory Signing...
powershell -NoProfile -Command "Set-SmbClientConfiguration -RequireSecuritySignature $false -Confirm:$false"

echo [+] 3. เปิดอนุญาต Insecure Guest Logons...
powershell -NoProfile -Command "Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -Confirm:$false"

echo [+] 4. ตั้งค่า Registry LanmanWorkstation...
reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v AllowInsecureGuestAuth /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v RequireSecuritySignature /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v EnableSecuritySignature /t REG_DWORD /d 0 /f

echo [+] 5. รีสตาร์ท Workstation Service...
powershell -NoProfile -Command "Restart-Service LanmanWorkstation -Force"

echo ========================================================
echo  SMB Configuration Complete!
echo ========================================================

sc query mrxsmb10 >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo ************************************************************
    echo  [!] สำคัญมาก: ต้องทำการ Restart (รีบูตเครื่องคอมพิวเตอร์) 1 ครั้ง
    echo  เพื่อให้ Windows โหลดไดรเวอร์ SMB 1.0 เข้าสู่ระบบ
    echo ************************************************************
    echo.
    echo หลังจากรีสตาร์ทเสร็จ ให้เปิด File Explorer แล้วพิมพ์:
    echo \\192.168.1.69\download
) else (
    echo [+] ไดรเวอร์ SMB 1.0 พร้อมใช้งานแล้ว!
    echo ทดสอบเชื่อมต่อไปยัง \\192.168.1.69\download ...
    net use \\192.168.1.69\download
)

echo.
pause
