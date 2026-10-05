$ErrorActionPreference = 'Continue'
Set-Location 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro'
$log = 'verification\r3\build.log'
"=== dotnet build FluentPomodoro.csproj -c Release -v m ===" | Out-File $log -Encoding utf8
& dotnet build FluentPomodoro.csproj -c Release -v m 2>&1 | Tee-Object -FilePath $log -Append
"EXITCODE=$LASTEXITCODE" | Tee-Object -FilePath $log -Append

$plog = 'verification\r3\publish.log'
"=== dotnet publish ... -o .\verify-dist-r3 ===" | Out-File $plog -Encoding utf8
& dotnet publish FluentPomodoro.csproj -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
  -p:EnableCompressionInSingleFile=true -o .\verify-dist-r3 2>&1 | Tee-Object -FilePath $plog -Append
"EXITCODE=$LASTEXITCODE" | Tee-Object -FilePath $plog -Append

Get-ChildItem .\verify-dist-r3 | Select-Object Name, Length | Format-Table -AutoSize | Tee-Object -FilePath $plog -Append
$exe = '.\verify-dist-r3\FluentPomodoro.exe'
if (Test-Path $exe) {
  $h = (Get-FileHash $exe -Algorithm SHA256).Hash
  "SHA256=$h" | Tee-Object -FilePath $plog -Append
  "EXE_BYTES=$((Get-Item $exe).Length)" | Tee-Object -FilePath $plog -Append
}
"BUILD_R3_DONE"
