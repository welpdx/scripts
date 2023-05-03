@echo off

rem This script will attempt to find this systems Dell Service Tag
rem The tag will be recorded in info.txt on the desktop

mode 15,1
title [~]

set FILE="%~dp0\info.txt"

wmic bios get serialnumber >%FILE%
wmic csproduct get vendor >>%FILE%
wmic csproduct get name >>%FILE%
wmic os get caption >>%FILE%
start notepad %FILE%

pause