Remove-Item su_extensions.rbz -ErrorAction SilentlyContinue
Remove-Item su_extensions.zip -ErrorAction SilentlyContinue
Compress-Archive -Path su_extensions,su_extensions.rb -DestinationPath su_extensions.zip
Rename-Item su_extensions.zip su_extensions.rbz
Write-Host "Success :)"
