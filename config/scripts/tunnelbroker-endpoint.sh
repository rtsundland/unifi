#!/usr/bin/env /bin/bash
#
# tunnelbroker-endpoint.sh for Unifi Security Gateway (USG)
#
# This code uses the Hurricane Electric Tunnel Broker API to update
# an IPv6 tunnel IPv4 local endpoint URL to maintain the tunnel.
# This script is equivalent to logging into the URL and providing
# the IP directly, but allows it to be automated as a task within
# USG.
#
# Github:  https://github.com/rtsundland/unifi
# Author:  Ray Sundland <raymond@sundland.com>
#
# NOTE NOTE NOTE NOTE
# Requires lib/getifaddr script (available here, too)
#
# Usage:  $0 <ethernet-if> <tunnel-if>
# Example: $0 eth0 tun0
#
#
# Tunnelbroker Configuration
TB_API="https://ipv4.tunnelbroker.net/nic/update"
TB_USER="<YOUR-TB_USERNAME>"
TB_PASS="<YOUR-TB-PASSWORD>"
TB_TUNNELID="<TUNNEL-YOU-WANT-TO-MODIFY"

PATH="${PATH}:$(dirname $0)/lib"

cfg() {
        /opt/vyatta/sbin/vyatta-cfg-cmd-wrapper $*
}

if=$1; shift
tun=$1; shift

if [ -z "${if}" ] || [ -z "${tun}" ]
then    echo "Invalid options:  $0 <gateway-interface> <tunnel-interface>" 1>&2
        exit 2
fi

echo -n "Discovering current WAN IP address on interface ${if}: "
record_ip=$(getifaddr $if)
if [ "${record_ip}" = "" ]
then    echo "failed."
        echo ".. Unable to find any existing IP addresses on interface ${if}"
        exit 2
else    echo "success!"
        echo "... Found: ${record_ip}"
fi

echo "Updating Tunnel Broker IP Address: "
rt=$(/usr/bin/curl -s \
        --user ${TB_USER}:${TB_PASS} \
        "${TB_API}?hostname=${TB_TUNNELID}&myip=${record_ip}")


if [ "$(echo $rt | cut -f1 -d ' ')" = "nochg" ]
then    echo "... no change required."
elif [ "${rt}" = "good 127.0.0.1" ]
then    echo "... failed (no ping)"
        exit 1
elif [ "${rt}" = "result: badauth" ]
then    echo "... failed (bad auth)"
        exit 1
else    echo "... success."
fi


echo "Updating Local ${tun} interface: "

cfg begin
existing_local_ip=$( cfg show interfaces tunnel ${tun} local-ip | cut -f2 -d" ")

if [ "${existing_local_ip}" != "${record_ip}" ]
then    echo "... new ${record_ip}"
        cfg set interfaces tunnel ${tun} local-ip ${record_ip}
        cfg commit
else    echo "... no change required"
fi

cfg end

