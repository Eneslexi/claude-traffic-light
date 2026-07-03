' Claude Trafik Lambasi - gizli baslatici (hook ve masaustu icin)
Set sh = CreateObject("WScript.Shell")
psScript = sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\.claude\traffic_light.ps1"
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScript & """", 0, False
Set sh = Nothing
