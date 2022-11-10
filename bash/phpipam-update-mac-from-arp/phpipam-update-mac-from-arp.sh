#!/bin/bash

URL='https://phpipam/api'
APP='myapp'
USER='myuser'
PASS='mypass'
SUBNET='192.168.1.0/24'
INTERFACE='eth0'
INVALIDTAGS=("3" "4")

echo "[INFO] Fetching token"
TOKEN=$(curl -X POST --user ${USER}:${PASS} ${URL}/${APP}/user/ -s | jq --raw-output .data.token)
if [ "$?" != "0" ]; then
    echo "[FAIL] Error fetching token from PHPIPAM" 1>&2
    exit 1
fi
if [ -z "${TOKEN}" ]; then
    echo "[FAIL] Didn't receive valid token from PHPIPAM" 1>&2
    exit 1
fi

echo "[INFO] Fetching token expiry (token test)"
EXPIRES=$(curl -X GET --header "token: ${TOKEN}" ${URL}/${APP}/user/ -s | jq --raw-output .data.expires)
if [ "$?" != "0" ]; then
    echo "[FAIL] Error fetching token expiry from PHPIPAM" 1>&2
    exit 1
fi
if [ -z "${EXPIRES}" ]; then
    echo "[FAIL] Didn't receive valid token expiry from PHPIPAM" 1>&2
    exit 1
fi

echo "[INFO] Fetching subnet id"
SUBNETID=$(curl -X GET --header "token: ${TOKEN}" ${URL}/${APP}/subnets/search/${SUBNET} -s | jq --raw-output .data[0].id)
if [ "$?" != "0" ]; then
    echo "[FAIL] Error fetching subnet id from PHPIPAM" 1>&2
    exit 1
fi
if [ -z "${SUBNETID}" ]; then
    echo "[FAIL] Didn't receive valid subnet id from PHPIPAM" 1>&2
    exit 1
fi

_update() {
    ip=${1}
    mac=${2}

    IPID=$(curl -X GET --header "token: ${TOKEN}" ${URL}/${APP}/addresses/${ip}/${SUBNETID} -s | jq --raw-output .data.id)
    if [ "$?" != "0" ]; then
        echo "[FAIL] Error fetching ip id from PHPIPAM" 1>&2
        exit 1
    fi
    if [ -z "${IPID}" ] || [ "${IPID}" = "null" ]; then
        echo "[INFO] address not in phpipam database: ${ip}"
        return
    fi

    NOUPDATE=0
    JSON=$(curl -X GET --header "token: ${TOKEN}" ${URL}/${APP}/addresses/${IPID}/ -s)
    if [ "$?" != "0" ]; then
        echo "[FAIL] Error fetching ip data from PHPIPAM" 1>&2
        exit 1
    fi
    IPTAG=$(echo ${JSON} | jq --raw-output .data.tag)
    for tag in ${INVALIDTAGS[@]}; do
        if [ "${IPTAG}" = "${tag}" ]; then 
            echo "[INFO] refusing to update ip with tag: ${IPTAG}"
            NOUPDATE=1
        fi
    done
    if [ ${NOUPDATE} -eq 1 ]; then return; fi
    
    IPMAC=$(echo ${JSON} | jq --raw-output .data.mac)
    if [ -z "${IPMAC}" ]; then
        echo "[INFO] No mac set for ip"
    fi
    if [ "${IPMAC}" = "${mac}" ]; then 
        echo "[INFO] no update required for mac"
        return
    fi

    JSON=$(curl -X PATCH --header "token: ${TOKEN}" ${URL}/${APP}/addresses/${IPID}/ -s --data "mac=${mac}")
    if [ "$?" != "0" ]; then
        echo "[FAIL] Error updating ip mac on PHPIPAM" 1>&2
        exit 1
    fi
    RESULT=$(echo ${JSON} | jq --raw-output .success)
    if [ "${RESULT}" != "true" ]; then
        echo "[FAIL] API returned error updating ip on PHPIPAM: ${JSON}"
        exit 1
    fi

    echo "[INFO] Updated id:${IPID} ip:${ip} mac:${mac}"
}

while read a b c d e; do
    # ? (192.168.1.10) at a1:b2:c3:d4:e5:f6 [ether] on eth0
    line="${a} ${b} ${c} ${d} ${e}"
    ip=$(echo ${b} | sed 's/[^0-9\.]//g')
    mac=${d}

    if [ "${mac}" = "<incomplete>" ]; then
        # we silently skip these
        continue
    fi

    if ! [[ ${mac} =~ ^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$ ]]; then
        echo "[INFO] Invalid mac: ${mac}"
        continue
    fi

    echo "[INFO] Found ip:${ip} mac:${mac}"
    if [ -z "${ip}" ]; then
        echo "[WARN] Unable to parse ip from '${b}': ${line}" 1>&2
    fi
    if [ -z "${mac}" ]; then
        echo "[WARN] Unable to parse mac from '${d}': ${line}" 1>&2
    fi

    _update ${ip} ${mac}

done < <(arp -an -i ${INTERFACE})
if [ "$?" != "0" ]; then
    echo "[FAIL] Error running arp" 1>&2
    exit 1
fi

# get json output from ip for local interfaces
IPJSON=$(ip -j a show ${INTERFACE})
if [ "$?" != "0" ]; then
    echo "[FAIL] Error running ip a show" 1>&2
    exit 1
fi
localmac=$(echo ${IPJSON} | jq --raw-output '.[0].address')

if [[ ${localmac} =~ ^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$ ]]; then
    LENGTH=$(echo ${IPJSON} | jq --raw-output '.[0].addr_info | length')
    for (( i=0; i<${LENGTH}; i++)); do
        localip=$(echo ${IPJSON} | jq --raw-output .[0].addr_info[${i}].local)
        if [ -z "${localip}" ]; then
            echo "[WARN] Unable to parse ip [${i}] from '${IPJSON}'" 1>&2
            continue
        fi
        echo "[INFO] Found interface:${INTERFACE} ip:${localip} mac:${localmac} index:$((${i} +1))/${LENGTH}"
        _update ${localip} ${localmac}
    done
else
    echo "[INFO] Invalid mac from interface: ${localmac}"
fi



JSON=$(curl -X DELETE --header "token: ${TOKEN}" ${URL}/${APP}/user/ -s)
if [ "$?" != "0" ]; then
    echo "[FAIL] Error removing token" 1>&2
    exit 1
fi
RESULT=$(echo ${JSON} | jq --raw-output .success)
if [ "${RESULT}" != "true" ]; then
    echo "[FAIL] API returned error when attempting to remove token: ${JSON}"
    exit 1
fi
echo "[INFO] Removed token"