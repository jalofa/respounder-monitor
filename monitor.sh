#!/bin/bash
set -e

CONFIG="/opt/respounder-monitor/config.conf"
LOGFILE="/opt/respounder-monitor/logs/monitor.log"
ISOLATED_LIST="/opt/respounder-monitor/isolated.list"
MSMTP="/usr/bin/msmtp"
MSMTP_CONF="/opt/respounder-monitor/msmtp.conf"

# Load config
source "$CONFIG"

# Ensure isolated list exists
touch "$ISOLATED_LIST"

# Function to send mail
send_mail() {
SUBJECT="$1"
BODY="$2"
echo -e "Subject:$SUBJECT\n\n$BODY" | $MSMTP --file="$MSMTP_CONF" "$MAIL_TO"
}

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$TIMESTAMP Running Respounder scan..." >> $LOGFILE

    RESULT=$(sudo respounder -json 2>/dev/null)

    if [[ -n "$RESULT" && "$RESULT" != "[]" ]]; then
        IP=$(echo "$RESULT" | jq -r '.[].responderIP' | head -n1)

        if [[ -z "$IP" || "$IP" == "null" ]]; then
            echo "$TIMESTAMP Respounder returned no valid IP." >> $LOGFILE
            sleep "$INTERVAL"
            continue
        fi

        echo "$TIMESTAMP Responder detected at $IP" >> $LOGFILE

        # Check if already isolated
        if grep -q "^$IP$" "$ISOLATED_LIST"; then
            echo "$TIMESTAMP $IP already isolated - skipping" >> $LOGFILE
            sleep "$INTERVAL"
            continue
        fi

        # Get Azure token
        TOKEN=$(curl -s -X POST \
          "https://login.microsoftonline.com/$TENANT_ID/oauth2/token" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          -d "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&resource=https://api.securitycenter.microsoft.com&grant_type=client_credentials" \
          | jq -r '.access_token')

        # Get Machine ID from Defender
        MACHINE_ID=$(curl -s -X GET \
          "https://api.securitycenter.microsoft.com/api/machines?\$filter=ipAddresses/any(ip: ip/address eq '$IP')" \
          -H "Authorization: Bearer $TOKEN" \
          | jq -r '.value[0].id')

        if [[ -n "$MACHINE_ID" && "$MACHINE_ID" != "null" ]]; then
            # Isolate device
            curl -s -X POST \
              "https://api.securitycenter.microsoft.com/api/machines/$MACHINE_ID/isolate" \
              -H "Authorization: Bearer $TOKEN" \
              -H "Content-Type: application/json" \
              -d '{"Comment":"Respounder detected","IsolationType":"Full"}'

            echo "$TIMESTAMP Isolation triggered for $IP" >> $LOGFILE

            # Mark IP as isolated
            echo "$IP" >> "$ISOLATED_LIST"

            # Send mail
            send_mail "ALERT: Responder detected and isolated" \
            "Responder detected on $IP
Device was isolated automatically.
Time: $TIMESTAMP"

        else
            echo "$TIMESTAMP Device with IP $IP not found in Defender" >> $LOGFILE

            # Send warning mail
            send_mail "WARNING: Responder detected - device not in Defender" \
            "Responder detected on $IP
Device NOT found in Defender.
Manual investigation required.
Time: $TIMESTAMP"
        fi

    else
        echo "$TIMESTAMP No responder detected." >> $LOGFILE
    fi

    sleep "$INTERVAL"
done
