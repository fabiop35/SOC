$out = 'D:\tmp\lab\hyperv\adapted\logs\ic-propiedades.txt'
Import-Module Hyper-V
Get-VMIntegrationService -VMName samba-dc1 | Format-List * | Out-String -Width 200 | Out-File $out -Encoding utf8
