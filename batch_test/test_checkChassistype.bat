@echo off

set "chassisType=8"

if "%chassisType%"=="8" (
    echo Chassis type is Portable with power.
    set "pctype=lt"
    echo pc type: "lt"
) 
if "%chassisType%"=="9" (
    echo Chassis type is Laptop.
    set "pctype=lt"
    echo pc type: "lt"
) 
if "%chassisType%"=="10" (
    echo Chassis type is Notebook.
    set "pctype=lt"
    echo pc type: "lt"
) 
if "%chassisType%"=="3" (
    echo Chassis type is Workstation.
    set "pctype=ws"
    echo pc type: "ws"
) 
if not "%chassisType%"=="8" if not "%chassisType%"=="9" if not "%chassisType%"=="10" if not "%chassisType%"=="3" (
    echo Chassis type other ("IDK")
    set "pctype=IDK"
    echo pc type: "idk"
)


pause
