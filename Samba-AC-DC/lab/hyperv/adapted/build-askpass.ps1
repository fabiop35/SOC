# Compila un askpass minimo para SSH no interactivo (laboratorio).
$src = @'
public class AskPass {
    public static void Main() {
        System.Console.WriteLine("sysadmin**");
    }
}
'@
$ErrorActionPreference = 'Stop'
if (Test-Path 'D:\tmp\lab\hyperv\adapted\askpass.exe') { Remove-Item 'D:\tmp\lab\hyperv\adapted\askpass.exe' -Force }
Add-Type -TypeDefinition $src -OutputAssembly 'D:\tmp\lab\hyperv\adapted\askpass.exe' `
         -OutputType ConsoleApplication
Write-Output 'askpass.exe compilado.'
