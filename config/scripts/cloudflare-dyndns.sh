#!/usr/bin/env /bin/bash
#
# cloudflare-dyndns.sh for Unifi Security Gateway (USG)
# Github:  https://github.com/rtsundland/unifi
# Author:  Ray Sundland <raymond@sundland.com>
#
# NOTE NOTE NOTE NOTE
# Requires lib/getifaddr script (available here, too)

# Usage:
#  $0 [-6][-i <interface>] -n host-record.domain.com
#
#  Valid options:
#     -n <hostname>   Create record for <hostname>
#     -i <interface>   Use <interface>, defaults to eth0
#     -6              Retrieve inet6 address and update AAAA record, defaults to A
#
# Configuration parameters
#
# CLOUDFLARE_API -- probably doesn't need to be changed.
CLOUDFLARE_API="https://api.cloudflare.com/client/v4"

# LOCAL_KEY -- Cloudflare API key with permissions to edit your zone
LOCAL_KEY="ENTER-YOUR-CLOUDFLARE-API-KEY-HERE"


PATH="${PATH}:$(dirname $0)/lib"

record_name=""
if=eth0
type="A"

while getopts ":6i:n:" opt
do      case "${opt}" in
                6) type="AAAA";;
                i) if=$OPTARG;;
                n) record_name=$OPTARG;;
        esac
done
shift $(( $OPTIND - 1 ))

if [ "${record_name}" = "" ]
then    echo "Record name must be specified using -n <value> on command line"
        exit 2
fi

zone_name=$(echo ${record_name} | sed 's/^.\+\.\([a-z]\+\)\.\([a-z]\+\)$/\1.\2/g')

curl() {
        method=$1; shift
        path=$1; shift
        data=$1; shift

        test "${data}" != "" && data="-d ${data}"

        /usr/bin/curl -s -X ${method} \
                -H "Content-Type:application/json" \
                -H "Authorization: Bearer ${LOCAL_KEY}" \
                "${CLOUDFLARE_API}/${path}" \
                ${data}
}

jo() {
        local OPTIND

        quoteit=1

        while getopts ":k:nb" opt
        do      case ${opt} in
                        k) key=${OPTARG};;
                        b|n) quoteit=0;;
                esac
        done

        shift $(( $OPTIND - 1 ))

        values=($@)
        test -n "${key}" && echo -n "\"${key}\":"
        last=$(( ${#values[@]} - 1 ))
        if [ $last -gt 1 ]
        then    test -n "${key}" && echo -n '[' || echo -n '{'
                for i in $( seq 0 $last )
                do      test -n "${key}" && test ${quoteit} -eq 1 echo -n "\"${values[$i]}\"" || echo -n "${values[$i]}"
                        if [ $i -eq $last ]
                        then    test -n "${key}" && echo ']' || echo '}'
                        else    echo -n ','
                        fi
                done
        else
                test -n "${key}" && test ${quoteit} -eq 1 && echo -n "\"${values[0]}\"" || echo -n "${values[0]}"
        fi

}

create_record() {
        zone_id=$1; shift
        name=$1; shift
        content=$1; shift
        type=$1; shift

        data=$(jo $(jo -k type ${type}) $(jo -k name ${name}) $(jo -k content ${content}) $(jo -k ttl -n 180) $(jo -k proxied -b false))
        ret=$( curl POST "zones/${zone_id}/dns_records/" $data )

        if [ "$(echo ${ret} | jq -r '.success')" = "false" ]
        then    echo $ret
                return 1
        else    return 0
        fi
}

update_record() {
        zone_id=$1; shift
        id=$1; shift
        name=$1; shift
        content=$1; shift
        type=$1; shift

        data=$(jo $(jo -k type ${type}) $(jo -k name ${name}) $(jo -k content ${content}) $(jo -k ttl -n 180) $(jo -k proxied -b false))
        ret=$( curl PUT "zones/${zone_id}/dns_records/${id}" $data )

        if [ "$(echo ${ret} | jq -r '.success')" = "false" ]
        then    echo $ret
                return 1
        else    return 0
        fi

}

get_record_id() {
        zone_id=$1; shift
        record_name=$1; shift
        type=$1; shift
        curl GET "zones/${zone_id}/dns_records?name=${record_name}&type=${type}" | jq -r ".result[0].id"
}

get_zone_id() {
        zone_name=$1; shift
        curl GET "zones?name=${zone_name}" | jq -r '.result[0].id'
}


echo -n "Discovering current WAN IP address on interface ${if}: "
record_ip=""
case $type in
        A) record_ip=$(getifaddr $if);;
        AAAA) record_ip=$(getifaddr -6 $if);;
esac
if [ "${record_ip}" = "" ]
then    echo "failed."
        echo ".. Unable to find any existing IP addresses on interface ${if}"
        exit 2
fi
echo "success!"
echo ".. Found: ${record_ip}"

echo -n "Finding Cloudflare Zone ID for '${zone_name}': "
zone_id=$(get_zone_id ${zone_name})
if [ "${zone_id}" = "null" ]
then    echo "failed."
        exit 2
else    echo "success!"
        echo ".. Zone ID is: ${zone_id}"
fi

echo -n "Looking for existing ${type} record for '${record_name}' within domain: "
record_id=$(get_record_id ${zone_id} ${record_name} ${type})
rc=$?

#if [ $rc -ne 0 ]
#then   echo "error."
#       echo ".. [FAILURE] failed to make API call"
#       exit
#
if [ "${record_id}" = "null" ]
then    echo "not found."
        echo -n ".. Creating new ${type} record for '${record_name}' to '${record_ip}': "
        create_record ${zone_id} ${record_name} ${record_ip} ${type}
        test $? -eq 0 && echo "okay." || echo "failed."

else    echo "success!"
        echo ".. Record ID is: ${record_id}"

        echo -n "Modifying ${type} record for '${record_name}' to '${record_ip}': "
        update_record ${zone_id} ${record_id} ${record_name} ${record_ip} ${type}
        test $? -eq 0 && echo "okay." || echo "failed."
fi
