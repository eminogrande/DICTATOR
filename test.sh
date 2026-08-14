#!/usr/bin/env bash
set -euo pipefail

SECRET_ENV=()
while IFS='=' read -r name _; do
  case "$name" in
    *KEY*|*TOKEN*|*SECRET*|*PASSWORD*|*CREDENTIAL*) SECRET_ENV+=("-u" "$name") ;;
  esac
done < <(/usr/bin/env)

exec /usr/bin/env "${SECRET_ENV[@]}" swift test "$@"
