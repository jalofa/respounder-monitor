Das Tool nutzt Respounder um regelmäßig Abfragen im Netzwerk zu machen.
Sollte ein Responder gefunden werden, wird per API an Defender der Befehl zur Isolation geschickt.

Außerdem wird unabhängig der isolation eine E-Mail mit der IP-Adresse des Responders geschickt.


Folgende Pakete werden benötigt:
go, jq, msmtp, respounder -> sudo apt install -y git golang jq msmtp
