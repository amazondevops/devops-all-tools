#!/bin/bash

# List of services to comment out (as a space-separated string)
#services="pkrb-blockedpair pkrb-captcha pkrb-connection pkrb-escrow pkrb-game pkrb-handhistory pkrb-jackpot pkrb-lobby pkrb-matchmaking pkrb-odds-calculator pkrb-table-recommendation pkrb-tournament-connection pkrb-tournament-gameserver pkrb-tournament-tablemanager pkrb-tournament-admin pkrb-tournament-alerts pkrb-tournament-bounty pkrb-tournament-escrow pkrb-tournament-fab-detector pkrb-tournament-leaderboard pkrb-tournament-match-making pkrb-tournament-orchestrator pkrb-tournament-poker-core pkrb-tournament-scheduler pkrb-web pkrb-tournament-settlement pkrb-tournament-ums pkrb-playerstats pkrb-playernotes pkrb-propass pkrb-propass-escrow pkrb-rumble-admin pkrb-rumble-escrow pkrb-rumble-evt-transformer pkrb-rumble-gateway pkrb-rumble-lobby pkrb-rumble-orchestrator pkrb-rumble-rule-engine pkrb-rumble-scoreboard pkrb-rumble-settlement pkrb-rumble-ums pkrb-apiservice pkrb-apiservice-ticketing pkrb-user-preferences pkrb-stats-aggregator pkrb-skillscore-service pkrb-template-manager pkrb-bankroll" #Add your service names here (space-separated)
services="pkrb-blockedpair pkrb-captcha pkrb-connection pkrb-escrow pkrb-game pkrb-handhistory pkrb-jackpot pkrb-lobby pkrb-matchmaking pkrb-odds-calculator pkrb-table-recommendation pkrb-tournament-connection pkrb-tournament-gameserver pkrb-tournament-tablemanager pkrb-tournament-admin pkrb-invoice-generator pkrb-tournament-alert pkrb-tournament-bounty pkrb-tournament-escrow pkrb-tournament-fab-detector pkrb-tournament-leaderboard pkrb-tournament-match-making pkrb-tournament-orchestrator pkrb-rng pkrb-tournament-core pkrb-tournament-scheduler pkrb-web pkrb-tournament-settlement pkrb-tournament-ums pkrb-playerstats pkrb-playernotes pkrb-propass pkrb-propass-escrow pkrb-rumble-admin pkrb-rumble-escrow pkrb-rumble-evt-transformer pkrb-rumble-gateway pkrb-rumble-lobby pkrb-rumble-orchestrator pkrb-rumble-rule-engine pkrb-rumble-scoreboard pkrb-rumble-settlement pkrb-rumble-ums pkrb-apiservice pkrb-apiservice-ticketing pkrb-user-preferences pkrb-stats-aggregator pkrb-skillscore-service pkrb-template-manager pkrb-bankroll" #Add your service names here (space-separated)
# List of files to process (as a space-separated string)
files="pkrb-qa-1.yaml pkrb-qa-2.yaml pkrb-qa-3.yaml pkrb-dev-1.yaml pkrb-dev-2.yaml"

# Loop over each service in the services string
for service in $services; do
  # Loop over each file
  for file in $files; do
    echo "Processing file: $file for service: $service"

    # Apply the sed command to comment out the service block in the file
    #sed -i "" "/- name: $service/,/configValueFile:/s/^/# /" "$file"  # For macOS
    sed -i "/- name: $service/,/configValueFile:/s/^/# /" "$file"  # For Linux
  done
done

echo "Service configurations commented out successfully!"

