param([string]$OutFile = 'D:\tmp\lab\hyperv\adapted\logs\eventos-previos.txt')
$logs = 'Microsoft-Windows-Hyper-V-VMMS-Admin',
        'Microsoft-Windows-Hyper-V-Worker-Admin',
        'Microsoft-Windows-Hyper-V-VMMS-Operational'
Remove-Item $OutFile -ErrorAction SilentlyContinue
foreach ($l in $logs) {
    "=== $l ===" | Out-File $OutFile -Append -Encoding utf8
    try {
        Get-WinEvent -LogName $l -MaxEvents 300 -ErrorAction Stop |
            Where-Object { $_.Message -like '*samba-dc1*' } |
            Select-Object TimeCreated, Id, ProviderName,
                @{n='Msg'; e={ ($_.Message -replace '\s+', ' ') }} |
            Format-Table -AutoSize -Wrap |
            Out-String -Width 240 |
            Out-File $OutFile -Append -Encoding utf8
    } catch {
        "ERROR: $($_.Exception.Message)" | Out-File $OutFile -Append -Encoding utf8
    }
}
