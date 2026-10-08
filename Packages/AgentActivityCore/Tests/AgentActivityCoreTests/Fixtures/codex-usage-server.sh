#!/bin/sh
IFS= read -r initialize_request || exit 1
case "$initialize_request" in
  *'"method":"initialize"'*) ;;
  *) exit 1 ;;
esac
printf '%s\n' '{"id":1,"result":{"userAgent":"fixture"}}'
IFS= read -r initialized_notification || exit 1
case "$initialized_notification" in
  *'"method":"initialized"'*) ;;
  *) exit 1 ;;
esac
IFS= read -r quota_request || exit 1
case "$quota_request" in
  *'"method":"account/rateLimits/read"'*) ;;
  *) exit 1 ;;
esac
printf '%s\n' '{"method":"account/updated","params":{"authMode":"chatgpt"}}'
printf '%s\n' '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000000000},"secondary":null}}}'
while IFS= read -r ignored_request; do :; done
