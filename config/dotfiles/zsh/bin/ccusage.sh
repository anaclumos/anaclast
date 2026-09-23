#!/bin/sh
set -eu

ingest_url=${USAGE_INGEST_URL:-https://cho.sh}/api/usage/ingest
secrets_file=$HOME/.ssh/.secrets.env

log() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die() { warn "$*"; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }

has curl || die 'curl is required'
has jq || die 'jq is required (https://jqlang.org/download/)'

run_ccusage() {
  if [ -n "${CCUSAGE:-}" ]; then
    set -f
    set -- $CCUSAGE "$@"
    "$@"
  elif has bun; then
    bun x --bun ccusage@latest "$@"
  elif has npx; then
    npx -y ccusage@latest "$@"
  elif has ccusage; then
    ccusage "$@"
  else
    die 'ccusage is required: install Bun (https://bun.sh) or Node.js, or set CCUSAGE to the command that runs it'
  fi
}

rows_program='def required_string($field):
  .[$field] | if type == "string" and length > 0 then . else error("invalid " + $field) end;
def nonnegative_integer($field):
  .[$field] | if type != "number" then error("invalid " + $field)
  elif . < 0 or floor != . then error("invalid " + $field) else . end;
def nonnegative_number($field):
  .[$field] | if type == "number" and . >= 0 then . else error("invalid " + $field) end;
if (.daily | type) != "array" then error("invalid ccusage daily report") else
  [.daily[]
   | . as $day
   | $day | required_string("period") as $date
   | if (.agents | type) != "array" or (.agents | length) == 0 then error("invalid ccusage agents") else . end
   | .agents[]
   | . as $agent_row
   | $agent_row | required_string("agent") as $agent
   | if (.modelBreakdowns | type) != "array" or (.modelBreakdowns | length) == 0 then error("invalid ccusage modelBreakdowns") else . end
   | .modelBreakdowns[]
   | {
       provider: (if $agent == "claude" then "claude-code" else $agent end),
       date: $date,
       model: required_string("modelName"),
       inputTokens: (nonnegative_integer("inputTokens") + nonnegative_integer("cacheReadTokens") + nonnegative_integer("cacheCreationTokens")),
       outputTokens: nonnegative_integer("outputTokens"),
       costUsd: nonnegative_number("cost")
     }]
  | group_by([.provider, .date, .model])
  | map({provider: .[0].provider, date: .[0].date, model: .[0].model,
         inputTokens: (map(.inputTokens) | add), outputTokens: (map(.outputTokens) | add),
         costUsd: (map(.costUsd) | add)})
end'

if ! report=$(run_ccusage daily --json --by-agent); then
  die 'ccusage daily report failed'
fi

if ! rows=$(printf '%s' "$report" | jq -ce "$rows_program"); then
  die 'ccusage daily report has an unsupported JSON shape'
fi
row_count=$(printf '%s' "$rows" | jq 'length')
log "computed local ccusage: $row_count (provider, date, model) rows"

if [ "$row_count" -eq 0 ]; then
  log 'no ccusage usage found on this host'
  exit 0
fi

tokens=$(printf '%s' "$rows" | jq 'map(.inputTokens + .outputTokens) | add')
provider_summary=$(printf '%s' "$rows" | jq -r 'group_by(.provider)
  | map("\(.[0].provider): \(length) rows, \(map(.inputTokens + .outputTokens) | add) tokens, $\(map(.costUsd) | add)")
  | join("; ")')
log "providers: $provider_summary"

if [ "${USAGE_DRY_RUN:-}" = 1 ]; then
  log "DRY RUN: $row_count merged (provider, date, model) rows; $tokens tokens; not posted"
  exit 0
fi

if [ -z "${CRON_SECRET:-}" ] && [ -f "$secrets_file" ]; then
  set -a
  . "$secrets_file"
  set +a
fi

[ -n "${CRON_SECRET:-}" ] || die "CRON_SECRET is required to authenticate the ingest push (export it or add a CRON_SECRET= line to $secrets_file)"

payload=$(mktemp)
response=$(mktemp)
trap 'rm "$payload" "$response"' EXIT

printf '%s' "$rows" | jq -c --arg host "$(uname -n)" '{host: $host, rows: .}' >"$payload"

request() {
  printf 'authorization: Bearer %s\n' "$CRON_SECRET" \
    | curl -sS -o "$response" -w '%{http_code}' -H @- "$@"
}

http_status=$(request -H 'content-type: application/json' --max-time 60 --data-binary @"$payload" "$ingest_url")
case $http_status in
  2??) ;;
  *) die "ingest POST failed with $http_status: $(cat "$response")" ;;
esac

accepted=$(jq -r '.accepted' "$response")
run_id=$(jq -r '.runId // empty' "$response")
log "pushed $row_count merged (provider, date, model) rows; $tokens tokens; server accepted $accepted rows (run ${run_id:-none})"
[ -n "$run_id" ] || exit 0

attempt=0
while [ "$attempt" -lt 30 ]; do
  attempt=$((attempt + 1))
  sleep 2
  http_status=$(request --max-time 30 "$ingest_url?runId=$run_id")
  case $http_status in
    202) ;;
    2??)
      log "ingest confirmed: $(cat "$response")"
      exit 0
      ;;
    *) die "ingest workflow failed: $http_status: $(cat "$response")" ;;
  esac
done
log "ingest run $run_id still in flight after 60s; it completes server-side"
