hn() {
  emulate -L zsh
  local limit=${1:-30}
  local cutoff=$(($(date +%s) - 86400))
  local ids item_json time_val url title opened=0
  local opener=${commands[open]:-${commands[xdg-open]:-}}

  if [[ -z "$opener" ]]; then
    print -u2 "hn: no URL opener found (open or xdg-open)"
    return 1
  fi

  ids=$(curl -s "https://hacker-news.firebaseio.com/v0/topstories.json") || {
    print -u2 "hn: failed to fetch top stories"
    return 1
  }

  for id in $(print "$ids" | tr -d '[]' | tr ',' '\n' | head -n 200); do
    item_json=$(curl -s "https://hacker-news.firebaseio.com/v0/item/${id}.json") || continue
    time_val=$(print "$item_json" | sed -n 's/.*"time":\([0-9]*\).*/\1/p')
    [[ -z "$time_val" || "$time_val" -lt "$cutoff" ]] && continue

    url=$(print "$item_json" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
    [[ -z "$url" ]] && url="https://news.ycombinator.com/item?id=${id}"

    title=$(print "$item_json" | sed -n 's/.*"title":"\([^"]*\)".*/\1/p')
    print "${title:-untitled}: $url"
    "$opener" "$url"
    opened=$((opened + 1))
    [[ "$opened" -ge "$limit" ]] && break
  done

  print "hn: opened $opened stories"
}

_build_run_step() {
  emulate -L zsh

  local dry_run=$1
  local label=$2
  shift 2

  print "=== $label ==="

  if (( dry_run )); then
    local arg
    printf 'Dry running:'
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
    return 0
  fi

  "$@"
}

_build_pull_dev_repos() {
  emulate -L zsh

  local dry_run=$1
  local dev_dir="${HOME}/Developer"
  local repo
  local exit_code=0

  [[ ! -d "$dev_dir" ]] && return 0

  for repo in "$dev_dir"/*(N/); do
    [[ ! -e "${repo}/.git" ]] && continue
    git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1 || continue
    _build_run_step "$dry_run" "git pull: ${repo:t}" git -C "$repo" pull --ff-only || exit_code=1
  done

  return $exit_code
}

_build_anaclast_dir() {
  emulate -L zsh
  local dir="${ANACLAST_DIR:-${HOME}/Developer/anaclast}"
  if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || [[ ! -f "${dir}/Makefile" ]]; then
    print -u2 "build: Anaclast checkout missing at ${dir} (set ANACLAST_DIR)"
    return 1
  fi
  print -r -- "$dir"
}

build() {
  emulate -L zsh
  setopt pipefail

  local arg
  local dry_run=0
  local exit_code=0
  local repo_dir
  local bin_dir="${ZSH_CONFIG_HOME:-${HOME}/.config/zsh}/bin"
  local anaclast_bin="/Applications/Anaclast.app/Contents/MacOS/Anaclast"

  for arg in "$@"; do
    case "$arg" in
      -h|--help)
        cat <<'EOF'
Usage: build [options]

Upgrade this machine: pull every ~/Developer repo that tracks an upstream,
push usage, rebuild and reinstall Anaclast from its checkout, then run
Anaclast apply, which converges Homebrew packages, downloads, preferences
and dotfiles to config/machine.json.

Options:
  -n, --dry-run  Print what would run.
  -h, --help     Show this help.

Repo: $ANACLAST_DIR (default ~/Developer/anaclast)
ccusage.sh: runs during build to push local usage for this computer.
Cursor usage push: skipped when ANACLAST_CURSOR_USAGE_PUSH=0.
EOF
        return 0
        ;;
      -n|--dry-run)
        dry_run=1
        ;;
      *)
        print -u2 "build: unknown option: $arg (see --help)"
        return 1
        ;;
    esac
  done

  repo_dir="$(_build_anaclast_dir)" || return 1

  _build_pull_dev_repos "$dry_run" || exit_code=1

  _build_run_step "$dry_run" "ccusage usage push" "${bin_dir}/ccusage.sh" || \
    print -u2 "build: ccusage usage push failed; continuing to Anaclast install"

  if [[ "${ANACLAST_CURSOR_USAGE_PUSH:-1}" != "0" ]]; then
    local cursor_push="${bin_dir}/cursor-usage-push.ts"
    local cursor_export="${bin_dir}/cursor-usage-export.py"
    if [[ -f "$cursor_push" ]] && [[ -f "$cursor_export" ]] && command -v bun >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
      _build_run_step "$dry_run" "cho.sh cursor usage push" \
        zsh -c "cd ${cursor_push:h} && bun install --frozen-lockfile && bun run ${cursor_push:t}" || \
        print -u2 "build: cho.sh cursor usage push failed; continuing to Anaclast install"
    fi
  fi

  if _build_run_step "$dry_run" "make install (Anaclast)" make -C "$repo_dir" install; then
    _build_run_step "$dry_run" "anaclast apply" "$anaclast_bin" apply || exit_code=1
  else
    print -u2 "build: skipping anaclast apply because make install failed"
    exit_code=1
  fi

  return $exit_code
}

emptyfolder() {
  find . -type d -empty -delete
}
