#!/bin/sh
# Start node_exporter in the background, listening on all IPv4 interfaces at port 9100
/usr/local/bin/node_exporter --web.listen-address="0.0.0.0:9100" &
sleep 1
# Start Trino using the command provided (default is "trino launcher run")
exec "$@"
