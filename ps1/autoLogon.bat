@echo off
:checkAdmin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo This script requires administrative privileges. Restarting with admin rights...
    powershell Start-Process -Verb RunAs -FilePath %0
    exit /b
)

cls
:menu
echo Select your Choice
echo 1. Enable Local Account Auto Logon
echo 2. Enable Domain Account Auto Logon
echo 3. Disable Local Account Auto Logon
echo 4. Disable Domain Account Auto Logon
echo 5. Exit
set /p "choice=Enter your choice (1-5): "

if "%choice%"=="1" goto EnableLocalAutoLogon
if "%choice%"=="2" goto EnableDomainAutoLogon
if "%choice%"=="3" goto DisableLocalAutoLogon
if "%choice%"=="4" goto DisableDomainAutoLogon
if "%choice%"=="5" goto end

echo Invalid choice. Please enter a valid choice (1-5).
pause
goto menu

:EnableLocalAutoLogon
set /p "Username=Enter the username for Local Account Auto Logon (e.g., administrator): "
set /p "Password=Enter the password for Local Account Auto Logon (e.g., purple pass): "
echo reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d %Username% /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d %Username% /f
echo reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d %Password% /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d %Password% /f
echo reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
echo Local Account Auto Logon configured successfully.
pause
goto end

:EnableDomainAutoLogon
for /f "skip=1 tokens=*" %%a in ('wmic computersystem get domain') do (
  set "DomainName=%%a"
  goto SetDomainKeys
)

:SetDomainKeys
set /p "Username=Enter the username for Domain Account Auto Logon: "
set /p "Password=Enter the password for Domain Account Auto Logon: "
echo reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
echo reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultDomainName /t REG_SZ /d %DomainName% /f
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultDomainName /t REG_SZ /d %DomainName% /f
echo reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d %Password% /f
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d %Password% /f
echo reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d %Username% /f
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d %Username% /f
echo Domain Account Auto Logon configured successfully.
pause
goto end

:DisableLocalAutoLogon
echo reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /f
echo reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /f
echo reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /f
echo Local Account Auto Logon disabled successfully.
pause
goto end

:DisableDomainAutoLogon
echo reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /f
reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /f
echo reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultDomainName /f
reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultDomainName /f
echo reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /f
reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /f
echo reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /f
reg delete "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /f
echo Domain Account Auto Logon disabled successfully.
pause
goto end

:end
echo Exiting: %~nx0
timeout /t 3 /nobreak > nul
exit /b
