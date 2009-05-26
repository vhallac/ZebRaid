@echo off
if "%1"=="" goto error
git archive --format=zip --prefix=ZebRaid/ HEAD >ZebRaid-%1.zip
goto end

:error
echo "Usage: release <version>"

:end
