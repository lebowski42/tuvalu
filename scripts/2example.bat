:: Version| v3.1.2
:: Remove | @echo off
:: Remove | del %Systemdrive%\helloworld.png

:: URL|ALL|http://upload.wikimedia.org/wikipedia/commons/8/81/Hello_World.png|packages/2example/helloworld.png

@echo off


copy %Z%\packages\2example\helloworld.png %Systemdrive%\
