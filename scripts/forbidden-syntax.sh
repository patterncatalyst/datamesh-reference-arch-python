#!/usr/bin/env bash
#
# forbidden-syntax.sh - fail on host-access tunnels, non-loopback port publishing,
# container-runtime drift and other-OS mentions.
#
# Policy: host access is minikube NodePorts published on 127.0.0.1 at profile
# creation (--ports=127.0.0.1:<hostPort>:<nodePort>). Tunnels break or
# disconnect, so these are forbidden everywhere in the repo:
#   SSH tunnels (ssh -L), kubectl port-forward / proxy, socat, minikube tunnel,
#   minikube service --url, any use of the word "tunnel" or the old helper
#   names, and bare --ports=a:b (binds 0.0.0.0; use a 127.0.0.1: prefix).
# Host scope: supported hosts are Fedora or RHEL. No other operating system,
# distribution, WSL, or OS-specific tool is mentioned anywhere (scan 6). A line
# that is exactly `runs-on: ubuntu-latest` (a CI runner label) is exempt.
#
# The whole repo (.) is scanned, minus the excludes below. Scans (relative to
# ROOT_DIR, which defaults to the repo root):
#   1. tunnel / port-forward / ssh -L / kubectl proxy / socat patterns
#   2. case-sensitive legacy helper names
#   3. --ports values lacking a 127.0.0.1: prefix. Shell expansions are ignored,
#      except a ${X:-a:b} default, which must carry the prefix. Handles a space
#      after a comma and a `--ports \` continuation onto the next line.
#   4. scans 1, 3, 5 and 6 inside presentation/**/*.pptx slides, notes, layouts
#      and masters (fails if unzip is missing)
#   5. container runtime scope: podman / rootless / CRI-O / crio / crun /
#      MINIKUBE_ROOTLESS / the retired localhost:5000 registry name outside the
#      CRC appendix allowlist (the minikube path is Docker Engine + containerd,
#      DRA-019)
#   6. other-OS mentions (case-insensitive list plus case-sensitive Windows
#      etc.); strips the CSS tokens -moz-osx-font-smoothing, -apple-system and
#      Segoe UI first
#
# A line that states the prohibition (or must mention a forbidden term) carries
# the marker `forbidden-ok`; so does a line that scopes podman to the CRC
# appendix, or records a historical lesson (HTML comment in Markdown, trailing
# comment in shell). Excluded: .git, .claude (local tool settings), node_modules, _site, .jekyll-cache,
# _plans/archive/, *.archive.md, *.lock, package-lock.json, poetry.lock, binary
# files, __pycache__, .venv, and this script.
# Exit 1 on any hit; otherwise print "forbidden-syntax: OK".

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$(cd "$HERE/.." && pwd)}"
cd "$ROOT_DIR"

fail=0
total=0
report() { # <label> <hits>
    printf 'forbidden-syntax: %s\n' "$1"
    printf '%s\n' "$2" | sed 's/^/    /'
    fail=1
    total=$((total + $(printf '%s\n' "$2" | wc -l)))
}

# Common filter: drop archive paths and allow-marked lines.
filter() { grep -v -e '^scripts/forbidden-syntax\.sh:' -e '^_plans/archive/' -e '\.archive\.md:' -e 'forbidden-ok' || true; }

GREP_EXCL=(--exclude-dir=node_modules --exclude-dir=__pycache__ --exclude-dir=.venv
           --exclude-dir=_site --exclude-dir=.jekyll-cache --exclude-dir=.git --exclude-dir=.claude
           --exclude='*.archive.md' --exclude='*.lock' --exclude=poetry.lock
           --exclude=package-lock.json --exclude=forbidden-syntax.sh)

# gr <grep-flags> <regex> → "path:line:text" for the whole repo, ./ stripped.
gr() {
    { grep -rnI "${GREP_EXCL[@]}" "$1" -e "$2" . 2>/dev/null || true; } | sed 's#^\./##'
}

# Patterns are built from fragments so the script never matches itself.
tn="tun""nel"
pf="port-?for""ward"
mk="minikube( +-p +[^ ]+)?"
re1="$tn|$pf|port_for""ward|port for""ward|forward""Ports|kubectl +pro""xy|\\bso""cat\\b|ssh .*-L |$mk +$tn|minikube .*service .*--url"
# Case-sensitive variants (ssh -l is a login name, so these must not be -i).
re1cs="ssh +-[A-Za-z]*L|-L[0-9]"
re2="ensure_$tn|${tn}_port_for|$tn-services|${tn}s\\.sh"

# ports_val_bad <value-after---ports> → 0 if the value publishes without 127.0.0.1:
ports_val_bad() {
    local val="$1" it d
    local -a items defs
    val="${val//, /,}"                              # space after a comma
    val="${val#[\"\']}"
    # ${X:-a:b} defaults hold a pair that must be prefixed
    local tmp="$val"
    while [[ "$tmp" =~ :-([^}]*)\}(.*)$ ]]; do
        IFS=',' read -ra defs <<<"${BASH_REMATCH[1]}"
        tmp="${BASH_REMATCH[2]}"
        for d in "${defs[@]}"; do
            [[ "$d" =~ ^[0-9]+$ || "$d" == *:* ]] || continue
            [[ "$d" != 127.0.0.1:* ]] && return 0
        done
    done
    val="${val%%[[:space:]\"\']*}"                  # up to whitespace or quote
    IFS=',' read -ra items <<<"$val"
    for it in "${items[@]}"; do
        [[ "$it" == *'$('* || "$it" == *'${'* || "$it" == '$'* ]] && continue
        [[ "$it" == '"$'* ]] && continue
        # only port-looking items: digits, or anything with a colon (prose ignored)
        [[ "$it" =~ ^[0-9]+$ || "$it" == *:* ]] || continue
        [[ "$it" != 127.0.0.1:* ]] && return 0
    done
    return 1
}

# line_ports_bad <text> [<next-line>] → 0 if any --ports occurrence is bad.
line_ports_bad() {
    local rest="$1" next="${2:-}" val
    while [[ "$rest" =~ --ports([=\ ]|$)(.*)$ ]]; do
        rest="${BASH_REMATCH[2]}"
        val="${rest#"${rest%%[![:space:]]*}"}"       # trim leading space
        if [[ -z "$val" || "$val" == '\' ]]; then    # continuation onto the next line
            val="${next#"${next%%[![:space:]]*}"}"
            next=""
        fi
        ports_val_bad "$val" && return 0
    done
    return 1
}

# Scan 5 / 6 patterns. Fragments keep the script from matching itself.
pm="pod""man"
re5="$pm|rootless|cri-o|\\bcrio\\b|\\bcrun\\b|MINIKUBE_ROOTLESS|localhost:5000"
o1="mac ?""os|os ?""x|os""x|dar""win|w""sl2?|ubu""ntu|deb""ian|alp""ine|cent""os|open""suse|su""se|linux ""mint"
o2="col""ima|rancher"" desktop|orb""stack|home""brew|choco""latey|win""get|power""shell|hyper""-v"
o3="rocky ?""linux|alma""linux|free""bsd|pac""man|zyp""per"
re6i="\\b($o1|$o2|$o3)\\b|\\.w""slconfig|%user""profile%|%app""data%|\\bbrew +(install|tap|upgrade)|\\bapt(-get)? +(install|update|upgrade)"
re6cs="\\bWin""dows\\b|\\bWIN""DOWS\\b|\\bMac""Book\\b|Apple"" Silicon|\\bWin1[01]\\b"
msg6='other-OS mention (supported hosts are Fedora or RHEL, bare metal or VM)'
css_tokens=("-moz-os""x-font-smoothing" "-apple""-system" "'Segoe"" UI'" "\"Segoe"" UI\"")

# strip_css <text> → text without the allowed CSS tokens and container image tags
strip_css() {
    local t="$1" k
    for k in "${css_tokens[@]}"; do t="${t//"$k"/}"; done
    # Container image tags (e.g. postgres:16-alp''ine) name an image, not a host OS.
    t="$(sed -E 's#[A-Za-z0-9./_-]+:[A-Za-z0-9._-]*-alp''ine[A-Za-z0-9._-]*##g' <<<"$t")"
    printf '%s' "$t"
}

# os_hits → reads "path:line:text" on stdin; prints lines that still match scan 6
# after dropping `runs-on: ubuntu-latest` lines and the allowed CSS tokens.
os_hits() {
    local line text
    local exempt_re='^[[:space:]]*(-[[:space:]]+)?runs-on:[[:space:]]*ubu''ntu-latest[[:space:]]*$'
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        text="${line#*:*:}"
        [[ "$text" =~ $exempt_re ]] && continue
        text="$(strip_css "$text")"
        if grep -qiE -e "$re6i" <<<"$text" || grep -qE -e "$re6cs" <<<"$text"; then
            printf '%s\n' "$line"
        fi
    done
}

# Scan 1
hits="$( { gr -iE "$re1"; gr -E "$re1cs"; } | filter | sort -u)"
[[ -n "$hits" ]] && report 'tunnel / port-forward syntax (publish a NodePort at profile creation instead)' "$hits"

# Scan 2
hits="$(gr -E "$re2" | filter)"
[[ -n "$hits" ]] && report 'legacy tunnel helper names' "$hits"

# Scan 3: --ports values must start with 127.0.0.1: (shell expansions ignored).
raw="$( { grep -rnI "${GREP_EXCL[@]}" --include='*.sh' --include='*.md' --include='*.html' \
    -E -e '--ports([= ]|$)' . 2>/dev/null || true; } | sed 's#^\./##' | filter)"
hits=""
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    file="${line%%:*}"; rem="${line#*:}"; n="${rem%%:*}"; text="${rem#*:}"
    next="$(sed -n "$((n + 1))p" "$file" 2>/dev/null || true)"
    line_ports_bad "$text" "$next" && hits+="$line"$'\n'
done <<<"$raw"
hits="${hits%$'\n'}"
[[ -n "$hits" ]] && report '--ports value without 127.0.0.1: prefix (binds 0.0.0.0)' "$hits"

# Scan 5: container runtime scope. The allowlist is the CRC appendix.
hits="$(gr -iE "$re5" | filter \
    | grep -v -e '^examples/lgtm-datamesh/openshift/' \
              -e '^_docs/11-running-on-openshift-crc\.md:' \
              -e '^_plans/decisions\.md:' \
              -e '^_plans/reconciliation\.md:' \
              -e '^_plans/openshift-crc-appendix-plan\.md:' \
              -e '^_plans/docker-migration-plan\.md:' \
              -e '^assets/diagrams/19-crc-image-delivery\.' || true)"
[[ -n "$hits" ]] && report 'podman/rootless/CRI-O or the retired registry name outside the CRC appendix (the minikube path is Docker Engine + containerd, DRA-019)' "$hits"

# Scan 6: other-OS mentions.
hits="$( { gr -iE "$re6i"; gr -E "$re6cs"; } | filter | sort -u | os_hits)"
[[ -n "$hits" ]] && report "$msg6" "$hits"

nl=$'\n'   # literal newline: portable sed replacement (no GNU-only \n)
# Scan 4: slides, notes, layouts and masters inside pptx files.
pptx=()
while IFS= read -r -d '' f; do pptx+=("$f"); done < <(find . \( -name .git -o -name node_modules \) -prune -o -type f -name '*.pptx' -print0 | sort -z)
if (( ${#pptx[@]} )); then
    if ! command -v unzip >/dev/null 2>&1; then
        report 'pptx scan impossible: unzip not found (install unzip; the gate must read the decks)' "${#pptx[@]} pptx file(s) not scanned"
    else
        for f in "${pptx[@]}"; do
            f="${f#./}"
            # Strip XML tags per paragraph so text split across <a:t> runs is rejoined.
            txt="$(unzip -p "$f" 'ppt/slides/*.xml' 'ppt/notesSlides/*.xml' \
                    'ppt/slideLayouts/*.xml' 'ppt/slideMasters/*.xml' 2>/dev/null \
                | sed -e "s#</a:p>#&\\${nl}#g" -e 's/<[^>]*>//g' || true)"
            for k in "${css_tokens[@]}"; do txt="${txt//"$k"/}"; done
            m="$( { printf '%s\n' "$txt" | grep -ioE ".{0,30}($re1|$re5|$re6i).{0,30}" || true
                    printf '%s\n' "$txt" | grep -oE ".{0,30}($re1cs|$re6cs).{0,30}" || true; } \
                | sort | uniq -c | sed -E 's/^ +//' || true)"
            pbad=""
            while IFS= read -r tl; do
                [[ "$tl" == *--ports* ]] || continue
                line_ports_bad "$tl" && pbad+="--ports without 127.0.0.1: prefix: $tl"$'\n'
            done <<<"$txt"
            [[ -n "$pbad" ]] && m+="${m:+$'\n'}${pbad%$'\n'}"
            [[ -n "$m" ]] && report "pptx contains forbidden syntax: $f" "$m"
        done
    fi
fi

if (( fail )); then
    echo "forbidden-syntax: FAILED ($total hit lines)"
    exit 1
fi
echo "forbidden-syntax: OK"
