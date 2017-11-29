#!/bin/bash

if [[ ! -d "/var/log/kolla/tacker" ]]; then
    mkdir -p /var/log/kolla/tacker
fi
if [[ $(stat -c %a /var/log/kolla/tacker) != "755" ]]; then
    chmod 755 /var/log/kolla/tacker
fi

# Bootstrap and exit if KOLLA_BOOTSTRAP variable is set. This catches all cases
# of the KOLLA_BOOTSTRAP variable being set, including empty.
if [[ "${!KOLLA_BOOTSTRAP[@]}" ]]; then
    tacker-db-manage --config-file /etc/tacker/tacker.conf upgrade head
    exit 0
fi
