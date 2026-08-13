@echo off
rem yazi の opener (cmd.exe /C 実行) から PowerShell 版を呼ぶための薄いラッパー。
rem %~dp0 は自分の置き場所なので、.ps1 と 2 本セットで配ること。
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0open-on-mac.ps1" %*
