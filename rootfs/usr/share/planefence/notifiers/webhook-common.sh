#!/usr/bin/env bash
# Shared HTTP webhook helpers (placeholder expansion, headers, content-type).
# Free of Planefence globals so host unit tests can source this file.

# Escape a string for use as the replacement in ${var//pattern/repl}.
# Bash treats & as "matched text" and \ as the escape character in repl.
_webhook_escape_repl() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//&/\\&}"
  printf '%s' "$s"
}

# Apply one key$'\x1f'value record to text (value may contain newlines).
_webhook_apply_one_pair() {
  local text="$1"
  local line="$2"
  local key value repl
  [[ -z "$line" ]] && { printf '%s' "$text"; return; }
  key="${line%%$'\x1f'*}"
  value="${line#*$'\x1f'}"
  [[ -z "$key" || "$key" == "$line" ]] && { printf '%s' "$text"; return; }
  repl="$(_webhook_escape_repl "$value")"
  text="${text//||${key}||/${repl}}"
  printf '%s' "$text"
}

# Apply key/value pairs to replace ||key|| in text.
# Preferred: records separated by $'\x1e' so values may contain newlines
#   (key$'\x1f'value$'\x1e'…).
# Legacy: newline-separated single-line values (key$'\x1f'value\n…).
# Unknown tokens are left for a later pass to clear.
_webhook_apply_pairs() {
  local text="$1"
  local pairs="$2"
  local line
  if [[ "$pairs" == *$'\x1e'* ]]; then
    while IFS= read -r -d $'\x1e' line || [[ -n "$line" ]]; do
      text="$(_webhook_apply_one_pair "$text" "$line")"
    done <<<"$pairs"
  else
    while IFS= read -r line || [[ -n "$line" ]]; do
      text="$(_webhook_apply_one_pair "$text" "$line")"
    done <<<"$pairs"
  fi
  printf '%s' "$text"
}

# webhook_expand_placeholders <template> <record_pairs> [composed_pairs]
# Composed applied first (wins on same key), then record for remaining tokens.
# Any leftover ||...|| → empty.
webhook_expand_placeholders() {
  local template="${1-}"
  local record_pairs="${2-}"
  local composed_pairs="${3-}"
  local out
  out="$(_webhook_apply_pairs "$template" "$composed_pairs")"
  out="$(_webhook_apply_pairs "$out" "$record_pairs")"
  # Clear any remaining ||token|| placeholders
  while [[ "$out" =~ \|\|[^|]+\|\| ]]; do
    out="${out//${BASH_REMATCH[0]}/}"
  done
  printf '%s' "$out"
}

# Collapse 3+ consecutive newlines to a single blank line (\n\n),
# then trim trailing excess blank lines (keep at most one trailing newline).
webhook_collapse_blank_lines() {
  local text="${1-}"
  while [[ "$text" == *$'\n\n\n'* ]]; do
    text="${text//$'\n\n\n'/$'\n\n'}"
  done
  while [[ "$text" == *$'\n\n' ]]; do
    text="${text%$'\n'}"
  done
  printf '%s' "$text"
}

# Print Name: value lines; skip # comments and blank lines.
webhook_parse_headers_file() {
  local path="${1-}"
  local line
  [[ -f "$path" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    # trim trailing CR if present
    line="${line%$'\r'}"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    printf '%s\n' "$line"
  done <"$path"
}

webhook_default_content_type() {
  case "${1-}" in
    text) printf '%s' 'text/plain; charset=utf-8' ;;
    json) printf '%s' 'application/json' ;;
    *) printf '%s' 'text/plain; charset=utf-8' ;;
  esac
}

# yes/no if headers text already contains Content-Type: (case-insensitive)
webhook_headers_have_content_type() {
  local headers="${1-}"
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "${line,,}" == content-type:* ]]; then
      printf 'yes'
      return 0
    fi
  done <<<"$headers"
  printf 'no'
}

# Given newline-separated expanded header lines, print curl argv pairs:
#   -H
#   Name: value
# one pair per header (stdout lines; mapfile-friendly).
webhook_build_curl_header_args() {
  local headers="${1-}"
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" ]] && continue
    printf '%s\n' '-H'
    printf '%s\n' "$line"
  done <<<"$headers"
}

# Sanitize curl stderr for logs: replace known URL and any http(s)://… with <url>.
# Usage: webhook_sanitize_curl_stderr <stderr_text> [request_url]
webhook_sanitize_curl_stderr() {
  local err="${1-}"
  local url="${2-}"
  if [[ -n "$url" ]]; then
    err="${err//"$url"/<url>}"
  fi
  # Redact remaining absolute URLs (query tokens, basic-auth userinfo, etc.)
  err="$(sed -E 's#https?://[^[:space:]'\''\"<>]+#<url>#g' <<<"$err")"
  printf '%s' "$err"
}

# Escape for embedding inside a JSON string literal (no surrounding quotes).
webhook_json_string_escape() {
  jq -rn --arg s "${1-}" '$s|@json' | sed 's/^"//;s/"$//'
}

# Value for placeholder pairs: JSON-escape when format is json, else raw.
# Usage: webhook_pair_value <value> <text|json>
webhook_pair_value() {
  local value="${1-}"
  local format="${2:-text}"
  if [[ "$format" == "json" ]]; then
    webhook_json_string_escape "$value"
  else
    printf '%s' "$value"
  fi
}

# Flatten CR/LF in values used for HTTP header expansion.
webhook_flatten_header_value() {
  local s="${1-}"
  s="${s//$'\r'/ }"
  s="${s//$'\n'/ }"
  printf '%s' "$s"
}

_webhook_warn() {
  if declare -F log_print >/dev/null 2>&1; then
    log_print WARNING "$1"
  else
    printf 'WARNING: %s\n' "$1" >&2
  fi
}

# Strip CR; keep only single-line Name: value headers (skip malformed / injected lines).
webhook_sanitize_headers() {
  local raw="${1-}"
  local line
  raw="${raw//$'\r'/}"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    if [[ "$line" == *$'\n'* || "$line" == *$'\r'* ]]; then
      _webhook_warn "Skipping header line containing newline after expansion"
      continue
    fi
    if [[ "$line" != *:* ]]; then
      _webhook_warn "Skipping header line without Name: value form after expansion"
      continue
    fi
    printf '%s\n' "$line"
  done <<<"$raw"
}
