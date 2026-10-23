$out = 'D:\tmp\lab\hyperv\adapted\logs\estado-actual.txt'
Remove-Item $out -ErrorAction SilentlyContinue
"=== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File $out -Encoding utf8
Import-Module Hyper-V
$vm = Get-VM -Name samba-dc1
$vm | Select-Object Name, State, Uptime, Heartbeat, IntegrationServicesState,
    AutomaticStartAction, AutomaticStopAction, Status |
    Format-List | Out-String | Out-File $out -Append -Encoding utf8
Get-VMIntegrationService -VMName samba-dc1 |
    Select-Object Name, Enabled, PrimaryStatusDescription, SecondaryStatusDescription |
    Format-Table -AutoSize | Out-String -Width 200 | Out-File $out -Append -Encoding utf8
"--- eventos 18500/18502/18504 ---" | Out-File $out -Append -Encoding utf8
Get-WinEvent -LogName 'Microsoft-Windows-Hyper-V-Worker-Admin' -MaxEvents 60 -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -like '*samba-dc1*' -and $_.Id -in 18500,18502,18504,18506 } |
    Select-Object TimeCreated, Id, @{n='Msg';e={($_.Message -replace '\s+',' ')}} |
    Format-Table -AutoSize -Wrap | Out-String -Width 200 | Out-File $out -Append -Encoding utf8
