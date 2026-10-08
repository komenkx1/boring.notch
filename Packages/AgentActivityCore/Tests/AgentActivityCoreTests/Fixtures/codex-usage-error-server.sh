#!/bin/sh
IFS= read -r initialize_request || exit 1
printf '%s\n' '{"id":1,"error":{"code":-32600,"message":"private upstream detail"}}'
while IFS= read -r ignored_request; do :; done
