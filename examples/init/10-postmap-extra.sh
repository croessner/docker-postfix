#!/bin/sh
set -eu

if [ -f /etc/postfix/maps/transport ]; then
  postmap -c /etc/postfix /etc/postfix/maps/transport
fi
