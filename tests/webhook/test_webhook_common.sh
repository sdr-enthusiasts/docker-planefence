#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/rootfs/usr/share/planefence/notifiers/webhook-common.sh"

fail=0
assert_eq() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" != "$want" ]]; then
    printf 'FAIL %s\n  got:  %q\n  want: %q\n' "$name" "$got" "$want" >&2
    fail=1
  else
    printf 'PASS %s\n' "$name"
  fi
}

# Record placeholder
out="$(webhook_expand_placeholders 'Hello ||icao||' $'icao\x1fABC123')"
assert_eq "record field" "$out" "Hello ABC123"

# Missing → empty
out="$(webhook_expand_placeholders 'X||tail||Y' $'icao\x1fABC123')"
assert_eq "missing empty" "$out" "XY"

# Composed (pass via composed map)
out="$(webhook_expand_placeholders '||title||' '' $'title\x1fPlane-Alert: N123')"
assert_eq "composed title" "$out" "Plane-Alert: N123"

# Same key: composed wins over record
out="$(webhook_expand_placeholders '||icao||' $'icao\x1fREC' $'icao\x1fCOMP')"
assert_eq "composed wins" "$out" "COMP"

# Ampersand in value must not be treated as matched-text (&) by bash ${//}
out="$(webhook_expand_placeholders '||x||' $'x\x1fA&B')"
assert_eq "ampersand value" "$out" "A&B"

out="$(webhook_expand_placeholders 'link=||u||' $'u\x1fhttps://x.com?a=1&b=2')"
assert_eq "url query ampersand" "$out" "link=https://x.com?a=1&b=2"

# Text blank-line collapse
# Sentinel avoids bash $(...) stripping trailing newlines from the capture.
out="$(webhook_collapse_blank_lines $'a\n\n\nb\n'; printf x)"
out="${out%x}"
assert_eq "collapse blanks" "$out" $'a\n\nb\n'

# Headers parse: skip comments/blank; keep Header: value
tmp="$(mktemp)"
printf '%s\n' '# comment' '' 'Title: Hi' 'Authorization: Bearer tok' >"$tmp"
mapfile -t hdrs < <(webhook_parse_headers_file "$tmp")
assert_eq "header count" "${#hdrs[@]}" "2"
assert_eq "header0" "${hdrs[0]}" "Title: Hi"
rm -f "$tmp"

# curl -H argv lines: alternating -H and header value
mapfile -t carg < <(webhook_build_curl_header_args $'Title: Hi\nAuthorization: Bearer tok')
assert_eq "curl -H count" "${#carg[@]}" "4"
assert_eq "curl -H0" "${carg[0]}" "-H"
assert_eq "curl title" "${carg[1]}" "Title: Hi"
assert_eq "curl -H2" "${carg[2]}" "-H"
assert_eq "curl auth" "${carg[3]}" "Authorization: Bearer tok"

# Content-Type default
assert_eq "ct text" "$(webhook_default_content_type text)" "text/plain; charset=utf-8"
assert_eq "ct json" "$(webhook_default_content_type json)" "application/json"

# Override detection
assert_eq "has ct" "$(webhook_headers_have_content_type $'Title: x\nContent-Type: text/html')" "yes"
assert_eq "no ct" "$(webhook_headers_have_content_type $'Title: x')" "no"

# Multiline composed values use \x1e as record separator (values may contain newlines)
out="$(webhook_expand_placeholders $'Links:\n||links||' '' $'links\x1fhttp://map\nhttp://fa\x1e')"
assert_eq "multiline composed links" "$out" $'Links:\nhttp://map\nhttp://fa'

# Multiple \x1e records; second is single-line
out="$(webhook_expand_placeholders '||title|| ||links||' '' $'title\x1fHi\x1elinks\x1fa\nb\x1e')"
assert_eq "x1e multi records" "$out" $'Hi a\nb'

# curl stderr sanitization: drop known URL and other http(s) URLs
err="$(webhook_sanitize_curl_stderr 'curl: (7) Failed to connect to https://user:secret@ntfy.example/topic' 'https://user:secret@ntfy.example/topic')"
assert_eq "sanitize known url" "$err" "curl: (7) Failed to connect to <url>"
err="$(webhook_sanitize_curl_stderr 'see https://evil.example/a?token=x and done' '')"
assert_eq "sanitize other url" "$err" "see <url> and done"

# Shared notifier helpers moved into webhook-common
assert_eq "pair text" "$(webhook_pair_value 'a"b' text)" 'a"b'
if command -v jq >/dev/null 2>&1; then
  assert_eq "pair json" "$(webhook_pair_value $'a"b\nc' json)" 'a\"b\nc'
else
  printf 'SKIP pair json (jq not installed)\n'
fi
assert_eq "flatten nl" "$(webhook_flatten_header_value $'a\nb')" "a b"
cr_in="$(printf 'x\ry')"
assert_eq "flatten cr" "$(webhook_flatten_header_value "$cr_in")" "x y"
mapfile -t shdr < <(webhook_sanitize_headers $'Title: ok\nbadline\nX-Y: z')
assert_eq "sanitize hdr count" "${#shdr[@]}" "2"
assert_eq "sanitize hdr0" "${shdr[0]}" "Title: ok"
assert_eq "sanitize hdr1" "${shdr[1]}" "X-Y: z"

exit "$fail"
