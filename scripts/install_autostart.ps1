<#
.SYNOPSIS
  把 waatchdog.py 注册为 Windows 任务计划，在当前用户登录时自动后台启动。

.USAGE
  右键以 PowerShell 运行，或在 PowerShell 中执行：
    powershell -ExecutionPolicy Bypass -File .\scripts\install_autostart.ps1

  卸载：
    powershell -ExecutionPolicy Bypass -File .\scripts\uninstall_autostart.ps1
#>

$ErrorActionPreference = 'Stop'

$TaskName   = 'PaperWaatchdog'
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$VbsPath    = Join-Path $ScriptDir 'start_waatchdog.vbs'

if (-not (Test-Path $VbsPath)) {
    throw "找不到启动器：$VbsPath"
}

# 检查 pythonw 是否可用
$pyw = Get-Command pythonw.exe -ErrorAction SilentlyContinue
if (-not $pyw) {
    Write-Warning "未在 PATH 中找到 pythonw.exe。请确认 Python 已安装并加入 PATH，"
    Write-Warning "或编辑 start_waatchdog.vbs 把 sPy 改成 pythonw.exe 的绝对路径。"
}

# 用 wscript.exe 静默执行 vbs
$Action    = New-ScheduledTaskAction `
    -Execute 'wscript.exe' `
    -Argument "`"$VbsPath`""

# 触发器：当前用户登录时
$Trigger   = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"

# 设置：允许电池供电运行、不超时、失败自动重启
$Settings  = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

# 当前用户的完整账户名（COMPUTER\User 或 DOMAIN\User）
$FullUser = "$env:USERDOMAIN\$env:USERNAME"

# 如果已存在则先删除
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "已移除旧任务：$TaskName"
}

Register-ScheduledTask `
    -TaskName    $TaskName `
    -Action      $Action `
    -Trigger     $Trigger `
    -Settings    $Settings `
    -User        $FullUser `
    -RunLevel    Limited `
    -Description 'Auto-start waatchdog.py (PDF watcher + HTTP server) at user logon.' | Out-Null

Write-Host "✅ 已注册任务计划：$TaskName"
Write-Host "   触发：当前用户登录时"
Write-Host "   启动器：$VbsPath"
Write-Host ""
Write-Host "现在立即启动一次，方便你马上访问 http://127.0.0.1:8000"
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 2

# 简单检查是否在监听
$listening = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
if ($listening) {
    Write-Host "✅ 服务已监听 127.0.0.1:8000，浏览器打开 http://127.0.0.1:8000 即可。"
} else {
    Write-Warning "未检测到 8000 端口监听。请查看日志：$(Join-Path (Split-Path $ScriptDir -Parent) 'waatchdog.log')"
}
