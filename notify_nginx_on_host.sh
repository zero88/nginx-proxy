#!/bin/sh

utc_now=$(cat /etc/os-release | grep -q "Alpine"  && date -u -Iseconds || date --utc --iso-8601=seconds)
echo "$utc_now $HOSTNAME $@" > /etc/nginx/reload/.signal 
