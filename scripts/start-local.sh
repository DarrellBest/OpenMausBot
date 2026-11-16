#!/bin/sh
# Start OpenMausBot from source with this machine's local setup:
# - Local VM desktops run in a dedicated Colima VM ("openmausbot", 150 GB disk cap),
#   selected through DOCKER_HOST so the global docker context is left alone.
# - Engines and the default model come from ~/.openmausbot/config.json.
#
# Usage: scripts/start-local.sh            # desktop app (Electron)
#        scripts/start-local.sh server     # server + built web UI, http://127.0.0.1:8799
set -eu
PROFILE=${OMB_COLIMA_PROFILE:-openmausbot}
cd "$(dirname "$0")/.."

if ! colima status "$PROFILE" >/dev/null 2>&1; then
  # colima start switches the global docker context; put back whatever was current before.
  previous=$(docker context show 2>/dev/null || true)
  colima start "$PROFILE" --cpu 4 --memory 8 --disk 150 --runtime docker
  [ -n "$previous" ] && docker context use "$previous" >/dev/null
fi
export DOCKER_HOST="unix://$HOME/.colima/$PROFILE/docker.sock"

case "${1:-desktop}" in
  # Run node directly (not through pnpm) so a stop signal reaches the server itself.
  # Serves the built web UI (pnpm exec vite build) at the server's own address when dist/ exists.
  server)
    [ -f dist/index.html ] && export OMB_STATIC_DIR="${OMB_STATIC_DIR:-$PWD/dist}"
    exec node --experimental-strip-types server/dev-server.ts ;;
  *) exec pnpm dev:desktop ;;
esac
