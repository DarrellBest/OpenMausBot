#!/bin/sh
# Open the web UI once the server answers (run at login by a LaunchAgent). Gives up after 10 minutes.
URL=${OMB_UI_URL:-http://127.0.0.1:8799}
i=0
while [ $i -lt 300 ]; do
  if curl -s -m 2 -o /dev/null "$URL/api/bots"; then
    exec open "$URL"
  fi
  i=$((i + 1))
  sleep 2
done
exit 1
