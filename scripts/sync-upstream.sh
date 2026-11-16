#!/bin/zsh
# Bring this fork up to date: fast-forward main to upstream/main, merge main into dev, push both, refresh the
# local install (deps, built web UI, running server), and write a report of what changed.
#
# Usage: scripts/sync-upstream.sh            # run by the daily LaunchAgent, or by hand
# Reports: ~/.openmausbot/sync-reports/YYYY-MM-DD.md (latest.md points at the newest)
#
# The whole script is one function so git changing this file mid-run can't change what runs.
sync_main() {
  set -u
  export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  local repo=${${(%):-%x}:A:h:h}
  cd "$repo" || return 1
  local reports="$HOME/.openmausbot/sync-reports"
  mkdir -p "$reports"
  local stamp=$(date "+%Y-%m-%d %H:%M")
  local report="$reports/$(date +%F).md"
  local d="gui/$(id -u)"

  notify() { osascript -e "display notification \"$1\" with title \"MausBot fork sync\"" >/dev/null 2>&1 }
  finish() {
    ln -sf "$report" "$reports/latest.md"
    notify "$1"
    [[ -n "${OMB_SYNC_QUIET:-}" ]] || open -e "$report"
  }
  fail() {
    print -- "\n**Sync stopped:** $1\n" >> "$report"
    finish "Sync stopped: $1"
    return 1
  }

  print -- "# Fork sync — $stamp\n" > "$report"

  [[ -z "$(git status --porcelain --untracked-files=no)" ]] || { fail "uncommitted changes in $repo; nothing was merged"; return 1 }
  local start_branch=$(git branch --show-current)
  git fetch -q upstream && git fetch -q origin || { fail "git fetch failed (offline?)"; return 1 }

  local old=$(git rev-parse main) new=$(git rev-parse upstream/main)
  local count=$(git rev-list --count main..upstream/main)

  git switch -q main || { fail "could not switch to main"; return 1 }
  git merge -q --ff-only upstream/main || { git switch -q "$start_branch"; fail "main has commits upstream doesn't; merge it by hand"; return 1 }
  git push -q origin main || { git switch -q "$start_branch"; fail "push of main failed"; return 1 }
  git switch -q dev || { fail "could not switch to dev"; return 1 }
  if ! git merge -q --no-edit main; then
    local conflicts=$(git diff --name-only --diff-filter=U)
    git merge --abort
    git switch -q "$start_branch"
    print -- "main was updated and pushed, but merging it into dev conflicts in:\n\n\`\`\`\n$conflicts\n\`\`\`" >> "$report"
    fail "merge conflict between main and dev"; return 1
  fi
  git push -q origin dev || { fail "push of dev failed"; return 1 }
  git switch -q "$start_branch"

  if [[ "$count" == 0 ]]; then
    print -- "No new upstream commits. main and dev are up to date with milind-soni/OpenMausBot." >> "$report"
    OMB_SYNC_QUIET=1 finish "No upstream changes today"
    return 0
  fi

  print -- "**$count new upstream commits** merged into \`main\` and \`dev\` (\`${old:0:9}\` → \`${new:0:9}\`), both pushed.\n" >> "$report"

  # Refresh the local install so the running app is the new code.
  local refresh=()
  if ! git diff --quiet "$old" "$new" -- pnpm-lock.yaml package.json; then
    pnpm install --frozen-lockfile >/dev/null 2>&1 && refresh+=("dependencies reinstalled") || refresh+=("**pnpm install failed**")
  fi
  pnpm exec vite build >/dev/null 2>&1 && refresh+=("web UI rebuilt") || refresh+=("**web UI build failed**")
  if launchctl print "$d/com.openmausbot.server" >/dev/null 2>&1; then
    launchctl kickstart -k "$d/com.openmausbot.server" && refresh+=("server restarted")
  else
    refresh+=("server is off; it runs the new code next time it's turned on")
  fi
  print -- "Local install: ${(j:, :)refresh}.\n" >> "$report"

  # Watch list: upstream changes to the parts this fork's setup relies on.
  local watched=$(git diff --name-only "$old" "$new" -- server/container-computer.ts server/local-vm-settings.ts \
    server/container-limits.ts server/drivers/openai-compat.ts server/drivers/ollama.ts server/drivers/claude.ts \
    server/config.ts server/instance-fleets.ts server/dev-server.ts server/static-files.ts)
  if [[ -n "$watched" ]]; then
    print -- "## Touches our setup\n\nThese files our local setup depends on changed (Local VM, engines, config, server start):\n" >> "$report"
    print -- "$watched" | sed 's/^/- `/; s/$/`/' >> "$report"
    print >> "$report"
  fi

  # Summary by Claude (the logged-in Claude Code CLI); the raw list below stands on its own if this fails.
  local log=$(git log --no-merges --format='- %h %s' "$old..$new")
  local stat=$(git diff --shortstat "$old" "$new")
  local summary=$(print -- "Upstream commits:\n$log\n\nDiff: $stat\n\nFiles our fork depends on that changed:\n${watched:-none}" |
    perl -e 'alarm 600; exec @ARGV' claude -p --model claude-sonnet-5-5 \
      "You are writing a daily change report for the owner of a fork of OpenMausBot (an open-source chat app of AI bots). Below are the upstream commits merged today. Write a concise Markdown summary (under 300 words): group changes by theme with short bullets in plain language, then a 'Worth a look' section for anything that could affect this fork's setup: a Local VM (Docker/Colima desktop) used as the bots' shared computer, OpenAI-compatible engines (a local mlx-serve and Ollama), the Claude engine on a subscription login, config.json, or how the server starts. If nothing does, say so. Start directly with the content, no preamble or title." 2>/dev/null)
  if [[ -n "$summary" ]]; then
    print -- "## Summary\n\n$summary\n" >> "$report"
  fi
  print -- "## Commits\n\n$log\n\n$stat" >> "$report"
  finish "$count upstream commits merged into main and dev"
}
sync_main "$@"
