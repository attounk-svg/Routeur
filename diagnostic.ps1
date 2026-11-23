# Diagnostic de lenteur réseau / routeur (Windows)
# Usage (PowerShell) : powershell -ExecutionPolicy Bypass -File diagnostic.ps1 > rapport.txt
function Sec($t){ "`n===== $t =====" }
$GW = (Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Sort-Object RouteMetric | Select-Object -First 1).NextHop
"Passerelle (routeur) : $GW"

Sec "1. Latence vers le routeur (< 5 ms filaire, < 10 ms Wi-Fi)"
ping -n 20 $GW | Select-Object -Last 4
Sec "2. Latence vers Internet (1.1.1.1)"
ping -n 20 1.1.1.1 | Select-Object -Last 4

Sec "3. Ping sous charge (bufferbloat)"
$job = Start-Job { Invoke-WebRequest "https://speed.cloudflare.com/__down?bytes=200000000" -UseBasicParsing -OutFile $env:TEMP\dl.tmp }
Start-Sleep 2; ping -n 15 1.1.1.1 | Select-Object -Last 4
Stop-Job $job; Remove-Item $env:TEMP\dl.tmp -ErrorAction SilentlyContinue

Sec "4. Temps de résolution DNS"
foreach($d in "google.com","wikipedia.org","amazon.fr"){ "{0} : {1:N0} ms" -f $d,(Measure-Command{Resolve-DnsName $d -DnsOnly -NoHostsFile | Out-Null}).TotalMilliseconds }
Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses | Format-Table InterfaceAlias,ServerAddresses

Sec "5. Débit (100 Mo)"
$t = Measure-Command { Invoke-WebRequest "https://speed.cloudflare.com/__down?bytes=100000000" -UseBasicParsing -OutFile $env:TEMP\dl2.tmp }
"Débit : {0:N1} Mbit/s" -f (800 / $t.TotalSeconds); Remove-Item $env:TEMP\dl2.tmp

Sec "6. Wi-Fi : signal et canal"
netsh wlan show interfaces
Sec "7. Réseaux Wi-Fi voisins (encombrement des canaux)"
netsh wlan show networks mode=bssid | Select-String "SSID|Signal|Canal|Channel|Radio"

Sec "8. Appareils connectés (table ARP)"
Get-NetNeighbor -AddressFamily IPv4 | Where-Object { $_.State -ne "Unreachable" -and $_.IPAddress -like "192.168.*" -or $_.IPAddress -like "10.*" } | Format-Table IPAddress,LinkLayerAddress,State

Sec "9. Trace vers Internet"
tracert -d -h 12 -w 2000 1.1.1.1
Sec "10. Interface du routeur"
try { $r = Measure-Command { Invoke-WebRequest "http://$GW/" -UseBasicParsing -TimeoutSec 5 | Out-Null }; "Répond en {0:N0} ms" -f $r.TotalMilliseconds } catch { "Pas de réponse HTTP : $_" }
"`nTerminé. Envoie rapport.txt à Claude."
