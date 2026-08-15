@echo off
chcp 936 >nul
setlocal enabledelayedexpansion

REM ============================================================
REM  GetFit - 一键打包并安装到所有已连接的 Android 设备
REM  自动执行：依赖拉取 -> APK 构建 -> 设备检测 -> 安装
REM ============================================================

REM 切换到脚本所在目录（即项目根目录）
cd /d "%~dp0"

REM 非交互模式：设置 GETFIT_NONINTERACTIVE=1 可跳过末尾 pause，便于 CI/自动化
set "NONINTERACTIVE=%GETFIT_NONINTERACTIVE%"

REM 颜色与标题
title GetFit 一键打包安装工具
echo ============================================================
echo   GetFit 一键打包并安装到已连接的 Android 设备
echo ============================================================
echo.
echo 项目目录: %cd%
echo.

REM ---------- 步骤 0：环境检查 ----------
echo [0/4] 环境检查...
where flutter >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到 flutter 命令，请确认 Flutter SDK 已加入 PATH。
    goto :error_exit
)
where adb >nul 2>nul
if errorlevel 1 (
    echo [警告] 未在 PATH 中找到 adb，将依赖 flutter 内置的 adb。
)
echo       Flutter 与 ADB 检测通过。
echo.

REM ---------- 步骤 1：拉取依赖 ----------
echo [1/4] 拉取 Flutter 依赖 (flutter pub get)...
call flutter pub get
if errorlevel 1 (
    echo [错误] flutter pub get 失败，请检查 pubspec.yaml 或网络。
    goto :error_exit
)
echo       依赖拉取完成。
echo.

REM ---------- 步骤 2：构建 Release APK ----------
echo [2/4] 构建 Release APK (flutter build apk --release)...
echo       提示: 首次构建可能耗时较久，请耐心等待...
call flutter build apk --release
if errorlevel 1 (
    echo [错误] APK 构建失败，请查看上方日志。
    goto :error_exit
)
echo       APK 构建成功。
echo.

REM ---------- 步骤 3：定位生成的 APK ----------
set "APK_PATH=build\app\outputs\flutter-apk\app-release.apk"
if not exist "%APK_PATH%" (
    echo [错误] 未找到构建产物: %APK_PATH%
    goto :error_exit
)
echo [3/4] 已定位 APK: %APK_PATH%
echo.

REM ---------- 步骤 4：检测设备并安装 ----------
echo [4/4] 检测已连接的 Android 设备...
REM 使用 adb devices (不加 -l)，输出格式为 "<serial>\t<state>"，
REM 只取第二列为 "device" 的行（过滤 offline / unauthorized 等）
for /f "skip=1 tokens=1,2" %%a in ('adb devices') do (
    if "%%b"=="device" (
        set /a device_count+=1
        set "device_!device_count!=%%a"
    )
)

if not defined device_count (
    echo [警告] 未检测到已连接的 Android 设备。
    echo        请确认:
    echo          1. 设备已开启 USB 调试或通过网络 adb 连接
    echo          2. 已执行 'adb devices' 能看到设备
    echo          3. 设备已授权此电脑调试
    goto :error_exit
)

echo       共检测到 %device_count% 台 Android 设备，开始安装...
echo.

set /a success_count=0
set /a fail_count=0

for /l %%i in (1,1,%device_count%) do (
    set "cur_device=!device_%%i!"
    echo ------------------------------------------------------
    echo   正在安装到设备 [!cur_device!]
    echo ------------------------------------------------------
    adb -s !cur_device! install -r -t "%APK_PATH%"
    if !errorlevel! equ 0 (
        echo       [成功] 设备 !cur_device! 安装完成。
        set /a success_count+=1
    ) else (
        echo       [失败] 设备 !cur_device! 安装失败（错误码 !errorlevel!）。
        set /a fail_count+=1
    )
    echo.
)

REM ---------- 结果汇总 ----------
echo ============================================================
echo   安装结果汇总
echo ============================================================
echo   成功: %success_count% 台
echo   失败: %fail_count% 台
echo   APK 路径: %cd%\%APK_PATH%
echo ============================================================
echo.

if %fail_count% gtr 0 (
    echo [提示] 部分设备安装失败可能原因:
    echo          - 应用已安装且签名不一致，请先卸载: adb -s 设备ID uninstall com.example.getfit
    echo          - 设备存储空间不足
    echo          - APK 架构不匹配（例如 x86 设备安装了 arm-only 包）
    echo.
)

echo 完成。
if "%NONINTERACTIVE%"=="1" exit /b 0
echo 按任意键退出...
pause >nul
exit /b 0

:error_exit
echo.
echo ============================================================
echo   执行失败，已中止。
echo ============================================================
if "%NONINTERACTIVE%"=="1" exit /b 1
echo 按任意键退出...
pause >nul
exit /b 1
