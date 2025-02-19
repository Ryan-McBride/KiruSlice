@echo off
setlocal enabledelayedexpansion

:: ==============================================================================
:: 1. Input Check & Setup
:: ==============================================================================
if "%~1"=="" (
    echo Please drag and drop a video file onto this script.
    pause
    exit /b
)
set "input=%~1"
for %%F in ("%input%") do set "base=%%~nF"

:: ==============================================================================
:: 2. Convert or Pass Through MP4
:: ==============================================================================
if /I not "%~x1"==".mp4" (
    echo Converting "%input%" to MP4...
    ffmpeg -i "%input%" -c:v libx264 -c:a aac "%base%_converted.mp4"
    set "input=%base%_converted.mp4"
) else (
    echo File is already MP4, creating a working copy...
    copy "%input%" "%base%_converted.mp4" >nul
    set "input=%base%_converted.mp4"
)

:: ==============================================================================
:: 3. Detect and Save Scene Changes 
:: ==============================================================================
echo Detecting scene changes...
ffmpeg -hide_banner -i "%input%" -filter_complex "[0:v]select='gt(scene,0.7)',showinfo[v]" -map "[v]" -f null - 2> scene_log.txt

:: ==============================================================================
:: 4. Search Scene Log for Timestamps
::    Extracts the value following "pts_time:" and removes any leading "+"
:: ==============================================================================
if exist scenes.txt del scenes.txt
for /f "usebackq delims=" %%A in ("scene_log.txt") do (
    echo %%A | findstr /C:"pts_time:" >nul
    if not errorlevel 1 (
        set "line=%%A"
        set "value=!line:*pts_time:=!"
        for /f "tokens=1" %%B in ("!value!") do (
            set "timestamp=%%B"
            set "timestamp=!timestamp:+=!"
            echo !timestamp! >> scenes.txt
        )
    )
)

if not exist scenes.txt (
    echo No scene changes detected.
    pause
    exit /b
)
for %%Z in (scenes.txt) do set "filesize=%%~zZ"
if "!filesize!"=="0" (
    echo scenes.txt is empty. No scene changes detected.
    pause
    exit /b
)

:: ==============================================================================
:: 5. Get Video Duration
:: ==============================================================================
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "%input%" > duration.txt
set /p duration=<duration.txt
del duration.txt

for /f "delims=" %%x in ('powershell -NoProfile -Command "[double]::Parse('%duration%').ToString('F3')"') do set "duration=%%x"
echo Video duration: !duration!

if "!duration!"=="" (
    echo Failed to retrieve video duration.
    pause
    exit /b
)

:: ==============================================================================
:: 6. Setup Output Folder and Timestamps List
:: ==============================================================================
set "outputFolder=%base%_scenes"
if not exist "%outputFolder%" mkdir "%outputFolder%"

(
    echo 0
    type scenes.txt
    echo !duration!
) > timestamps.txt

:: ==============================================================================
:: 7. Split Video into Scene Segments
:: ==============================================================================
set "prev="
set "sceneCount=0"
for /f "usebackq tokens=*" %%T in ("timestamps.txt") do (
    set "curr=%%T"
    set "curr=!curr:+=!"
    for /f "tokens=* delims= " %%X in ("!curr!") do set "curr=%%X"
    if "!curr!"=="" (
         echo Skipping empty timestamp: %%T
    ) else (
         if defined prev (
             for /f "delims=" %%a in ('powershell -NoProfile -Command "([double](!curr!) - [double](!prev!)).ToString('F3')"') do set "segDuration=%%a"
             set /a sceneCount+=1
             set "outfile=%outputFolder%\scene_!sceneCount!.mp4"
             echo Creating segment !sceneCount!: start=!prev!, duration=!segDuration!
             ffmpeg -y -ss !prev! -i "%input%" -t !segDuration! -c copy "!outfile!"
         )
         set "prev=!curr!"
    )
)

echo.
echo Done splitting video into scenes.

:: ==============================================================================
:: 8. Cleanup Temp Files
:: ==============================================================================
echo Cleaning up intermediate files...
del scene_log.txt 2>nul
del scenes.txt 2>nul
del timestamps.txt 2>nul
if exist select del select 2>nul
if exist Stream del Stream 2>nul
if exist "%base%_converted.mp4" del "%base%_converted.mp4" 2>nul

echo Cleanup complete.
pause
