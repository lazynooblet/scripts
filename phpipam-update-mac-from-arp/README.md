# phpipam-update-mac-from-arp.sh

I spent some time this learning phpIPAM's REST API and writing a short bash script to update phpIPAM’s mac field.

- The script will need the username and password of a user that has write permission to the addresses you want to update.
- You will need to create an api app, as described in the documentation.
- The script gets info on a single interface and updates addresses in a single subnet.
- The script will check that the mac needs updating and only update if necessery.
- The script will ignore addresses tagged as (3) “reserved” or (4) “dhcp”.
- The script won’t add new addresses, only update existing ones.
- The script will check local interface ips as well (as these aren’t in ARP)
- The script requires “iproute2”, “curl” and “jq” (Command-line JSON processor).
