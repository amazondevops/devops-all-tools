#!/bin/sh

# List of services to uncomment
#services="pkrb-blockedpair pkrb-captcha pkrb-connection pkrb-escrow pkrb-game pkrb-handhistory pkrb-jackpot pkrb-lobby pkrb-matchmaking pkrb-odds-calculator pkrb-table-recommendation pkrb-tournament-connection pkrb-tournament-gameserver pkrb-tournament-tablemanager tournament-admin tournament-alerts tournament-bounty tournament-escrow tournament-fab-detector tournament-leaderboard tournament-match-making tournament-orchestrator tournament-poker-core tournament-scheduler pkbr-web tournament-settlement tournament-ums pkrb-playerstats pkrb-playernotes pkrb-propass pkrb-propass-escrow pkrb-rumble-admin pkrb-rumble-escrow pkrb-rumble-evt-transformer pkrb-rumble-gateway pkrb-rumble-lobby pkrb-rumble-orchestrator pkrb-rumble-rule-engine pkrb-rumble-scoreboard pkrb-rumble-settlement pkrb-rumble-ums pkrb-apiservice pkrb-apiservice-ticketing pkrb-user-preferences pkrb-stats-aggregator pkrb-skillscore-service pkrb-template-manager pkrb-bankroll"
services="pkrb-blockedpair pkrb-captcha pkrb-connection pkrb-escrow pkrb-game pkrb-handhistory pkrb-jackpot pkrb-lobby pkrb-matchmaking pkrb-odds-calculator pkrb-table-recommendation pkrb-tournament-connection pkrb-tournament-gameserver pkrb-tournament-tablemanager pkrb-tournament-admin pkrb-invoice-generator pkrb-tournament-alert pkrb-tournament-bounty pkrb-tournament-escrow pkrb-tournament-fab-detector pkrb-tournament-leaderboard pkrb-tournament-match-making pkrb-tournament-orchestrator pkrb-rng pkrb-tournament-core pkrb-tournament-scheduler pkrb-web pkrb-tournament-settlement pkrb-tournament-ums pkrb-playerstats pkrb-playernotes pkrb-propass pkrb-propass-escrow pkrb-rumble-admin pkrb-rumble-escrow pkrb-rumble-evt-transformer pkrb-rumble-gateway pkrb-rumble-lobby pkrb-rumble-orchestrator pkrb-rumble-rule-engine pkrb-rumble-scoreboard pkrb-rumble-settlement pkrb-rumble-ums pkrb-apiservice pkrb-apiservice-ticketing pkrb-user-preferences pkrb-stats-aggregator pkrb-skillscore-service pkrb-template-manager pkrb-bankroll" #Add your service names here (space-separated)
# List of files to process (adjust paths as needed)
files="pkrb-qa-1.yaml pkrb-qa-2.yaml pkrb-qa-3.yaml pkrb-dev-1.yaml pkrb-dev-2.yaml"

# Loop over each service in the list
for service in $services; do
  # Loop over each file
  for file in $files; do
    echo "Processing file: $file for service: $service"
    #sed -i "" "/- name: $service/,/configValueFile:/s/^# //g" "$file"  # For macOS
    sed -i "/- name: $service/,/configValueFile:/s/^# //g" "$file"  # For Linux, uncomment this line if you're on Linux
  done
done

echo "Service configurations uncommented successfully!"

