#!/usr/bin/env bash
# Diagnostic de lenteur réseau / routeur (macOS & Linux)
# Usage : bash diagnostic.sh > rapport.txt 2>&1
set -u
OS=$(uname)
sec(){ printf '\n===== %s =====\n' "$1"; }

if [ "$OS" = "Darwin" ]; then
  GW=$(route -n get default 2>/dev/null | awk '/gateway/{print $2}')
  IFACE=$(route -n get default 2>/dev/null | awk '/interface/{print $2}')
else
  GW=$(ip route | awk '/^default/{print $3; exit}')
  IFACE=$(ip route | awk '/^default/{print $5; exit}')
fi
echo "Passerelle (routeur) : $GW  | Interface : $IFACE"

sec "1. Latence vers le routeur (doit être < 5 ms en filaire, < 10 ms en Wi-Fi)"
ping -c 20 "$GW" | tail -3

sec "2. Latence vers Internet (1.1.1.1)"
ping -c 20 1.1.1.1 | tail -3

sec "3. Comparaison -> si 1 est bon et 2 mauvais : problème côté FAI/ligne ; si 1 est mauvais : routeur ou Wi-Fi"

sec "4. Perte de paquets sous charge (bufferbloat)"
( curl -s -o /dev/null https://speed.cloudflare.com/__down?bytes=200000000 & ) 
sleep 2; ping -c 15 1.1.1.1 | tail -2
pkill -f "speed.cloudflare.com" 2>/dev/null

sec "5. Temps de résolution DNS"
for d in google.com wikipedia.org amazon.fr; do
  /usr/bin/time -p nslookup "$d" >/dev/null 2>/tmp/t.$$; awk '/real/{print "'"$d"' : " $2 " s"}' /tmp/t.$$
done; rm -f /tmp/t.$$
echo "Serveurs DNS utilisés :"; grep nameserver /etc/resolv.conf 2>/dev/null || scutil --dns | grep nameserver | sort -u

sec "6. Débit (téléchargement 100 Mo depuis Cloudflare)"
curl -s -o /dev/null -w "Débit : %{speed_download} octets/s\n" "https://speed.cloudflare.com/__down?bytes=100000000"

sec "7. Wi-Fi : signal, canal, réseaux voisins"
if [ "$OS" = "Darwin" ]; then
  system_profiler SPAirPortDataType 2>/dev/null | sed -n '/Current Network Information/,/Other Local/p' | head -25
  echo "--- Réseaux voisins ---"
  system_profiler SPAirPortDataType 2>/dev/null | sed -n '/Other Local Wi-Fi Networks/,$p' | grep -E 'Channel|^ {10}[^ ]' | head -60
else
  command -v iw >/dev/null && iw dev "$IFACE" link
  command -v nmcli >/dev/null && nmcli -f SSID,CHAN,SIGNAL,FREQ dev wifi list
fi

sec "8. Appareils connectés au réseau (table ARP)"
arp -a | grep -v incomplete
echo "Nombre d'appareils : $(arp -a | grep -vc incomplete)"

sec "9. Trace vers Internet (où ça ralentit)"
traceroute -n -m 12 -w 2 1.1.1.1 2>/dev/null || tracepath -n 1.1.1.1

sec "10. Interface du routeur accessible ?"
curl -s -o /dev/null -w "HTTP %{http_code} en %{time_total}s\n" --max-time 5 "http://$GW/"
echo; echo "Terminé. Envoie le fichier rapport.txt à Claude."
