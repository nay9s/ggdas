@echo off
setlocal
title Safe Flutter Project Cleaner

pushd "%~dp0" || exit /b 1

if not exist "pubspec.yaml" (
    echo ERROR: pubspec.yaml was not found beside this script.
    echo Nothing was deleted.
    popd
    pause
    exit /b 1
)

if not exist "lib\" (
    echo ERROR: lib folder was not found beside this script.
    echo Nothing was deleted.
    popd
    pause
    exit /b 1
)

echo ========================================
echo Safe Flutter Project Cleaner
echo ========================================
echo.
echo Verified project:
echo %CD%
echo.
echo Only generated folders will be deleted:
echo   .dart_tool
echo   build
echo   android\.gradle
echo   android\app\build
echo   ios\Pods
echo   ios\.symlinks
echo.
echo Source folders such as lib, android, ios and test are preserved.
echo.
set /p "CONFIRM=Type CLEAN and press Enter to continue: "

if /i not "%CONFIRM%"=="CLEAN" (
    echo Cancelled. Nothing was deleted.
    popd
    pause
    exit /b 0
)

call :DeleteFolder ".dart_tool"
call :DeleteFolder "build"
call :DeleteFolder "android\.gradle"
call :DeleteFolder "android\app\build"
call :DeleteFolder "ios\Pods"
call :DeleteFolder "ios\.symlinks"

echo.
echo Cleaning completed.
popd
pause
exit /b 0

:DeleteFolder
if exist "%~1\" (
    echo Deleting: %CD%\%~1
    rmdir /s /q "%~1"
) else (
    echo Skipped:  %CD%\%~1 does not exist
)
exit /b 0
