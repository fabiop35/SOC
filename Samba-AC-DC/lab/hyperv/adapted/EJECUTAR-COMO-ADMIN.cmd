@echo off
setlocal
rem Lanzador con UAC. Ejecuta la adaptacion completa y deja la VM encendida.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%~dp0ejecutar-todo.ps1','-LeaveRunning'"
endlocal
