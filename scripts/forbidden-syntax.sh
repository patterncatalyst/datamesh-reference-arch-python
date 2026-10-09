#!/usr/bin/env bash
#
# forbidden-syntax.sh - fail on host-access tunnels and non-loopback port publishing.
#
# Policy: host access is minikube NodePorts published on 127.0.0.1 at profile
# creation (--ports=127.0.0.1:<hostPort>:<nodePort>). Tunnels break or
# disconnect, so these are forbidden in docs, examples, scripts, site pages and decks:
#   SSH tunnels (ssh -L), kubectl port-forward, minikube tunnel,
#   minikube service --url, any use of the word "tunnel" or the old helper
#   names, and bare --ports=a:b (binds 0.0.0.0; use a 127.0.0.1: prefix).
#
# Scans (relative to ROOT_DIR, which defaults to the repo root):
#   1. case-insensitive tunnel / port-forward patterns in text files
#   2. case-sensitive legacy helper names
#   3. --ports values lacking a 127.0.0.1: prefix (shell expansions are ignored,
#      they come from node_ports_arg)
#   4. the same patterns inside presentation/**/*.pptx slides and notes
#   5. container runtime scope: podman / rootless / CRI-O / crun /
#      MINIKUBE_ROOTLESS / the retired localhost:5000 registry name outside the
#      CRC appendix allowlist (the minikube path is Docker Engine + containerd,
#      DRA-019)
#
# A line that states the prohibition (or must mention a forbidden term) carries
# the marker `forbidden-ok`; so does a line that scopes podman to the CRC
# appendix, or records a historical lesson (the rootless-podman era) (HTML comment in Markdown, trailing comment in
# shell). Excluded: _plans/archive/, *.archive.md, node_modules, __pycache__,
# .venv, _site, .git, lock files, binary files, and this script.
# Exit 1 on any hit; otherwise print "forbidden-syntax: OK".

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$(cd "$HERE/.." && pwd)}"
cd "$ROOT_DIR"

targets=()
for t in _docs onboarding examples scripts _plans _includes _layouts \
         README.md PRD.md index.html setup.html demos.html; do
    [[ -e "$t" ]] && targets+=("$t")
done
for f in presentation/*/*.js presentation/*/README.md; do
    [[ -f "$f" ]] && targets+=("$f")
done

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
           --exclude-dir=_site --exclude-dir=.git --exclude=poetry.lock --exclude='*.lock'
           --exclude=package-lock.json --exclude=forbidden-syntax.sh)

# Patterns are built from fragments so the script never matches itself.
tn="tun""nel"
pf="port-?for""ward"
mk="minikube( +-p +[^ ]+)?"
re1="$tn|$pf|port for""ward|ssh .*-L |$mk +$tn|minikube .*service .*--url"
re2="ensure_$tn|${tn}_port_for|$tn-services|${tn}s\\.sh"

if (( ${#targets[@]} )); then
    hits="$( (grep -rnIiE "${GREP_EXCL[@]}" -e "$re1" "${targets[@]}" 2>/dev/null || true) | filter)"
    [[ -n "$hits" ]] && report 'tunnel / port-forward syntax (publish a NodePort at profile creation instead)' "$hits"

    hits="$( (grep -rnIE "${GREP_EXCL[@]}" -e "$re2" "${targets[@]}" 2>/dev/null || true) | filter)"
    [[ -n "$hits" ]] && report 'legacy tunnel helper names' "$hits"

    # Scan 3: --ports values must start with 127.0.0.1: (shell expansions ignored).
    raw="$( (grep -rnIE "${GREP_EXCL[@]}" --include='*.sh' --include='*.md' --include='*.html' \
        -e '--ports[= ]' "${targets[@]}" 2>/dev/null || true) | filter)"
    hits=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        bad=0
        # Check every --ports occurrence on the line, not only the first.
        rest="$line"
        while [[ "$rest" =~ --ports[=\ ](.*)$ ]]; do
            rest="${BASH_REMATCH[1]}"
            val="${rest#"${rest%%[![:space:]]*}"}"       # trim leading space
            val="${val#[\"\']}"                         # leading quote
            val="${val%%[[:space:]\"\']*}"              # up to whitespace or quote
            IFS=',' read -ra items <<<"$val"
            for it in "${items[@]}"; do
                [[ "$it" == *'$('* || "$it" == *'${'* || "$it" == '$'* ]] && continue
                [[ "$it" == '"$'* ]] && continue
                # only port-looking items: digits, or anything with a colon (prose ignored)
                [[ "$it" =~ ^[0-9]+$ || "$it" == *:* ]] || continue
                [[ "$it" != 127.0.0.1:* ]] && bad=1
            done
        done
        (( bad )) && hits+="$line"$'\n'
    done <<<"$raw"
    hits="${hits%$'\n'}"
    [[ -n "$hits" ]] && report '--ports value without 127.0.0.1: prefix (binds 0.0.0.0)' "$hits"
fi

# Scan 5: container runtime scope. Pattern is built from fragments so the script
# never matches itself.
pm="pod""man"
re5="$pm|rootless|cri-o|\\bcrun\\b|MINIKUBE_ROOTLESS|localhost:5000"
if (( ${#targets[@]} )); then
    hits="$( (grep -rnIiE "${GREP_EXCL[@]}" -e "$re5" "${targets[@]}" 2>/dev/null || true) | filter \
        | grep -v -e '^examples/lgtm-datamesh/openshift/' \
                  -e '^_docs/11-running-on-openshift-crc\.md:' \
                  -e '^_plans/decisions\.md:' \
                  -e '^_plans/reconciliation\.md:' \
                  -e '^_plans/openshift-crc-appendix-plan\.md:' \
                  -e '^_plans/docker-migration-plan\.md:' \
                  -e '^assets/diagrams/19-crc-image-delivery\.' || true)"
    [[ -n "$hits" ]] && report 'podman/rootless/CRI-O or the retired registry name outside the CRC appendix (the minikube path is Docker Engine + containerd, DRA-019)' "$hits"
fi

nl=$'\n'   # literal newline: portable sed replacement (no GNU-only \n)
# Scan 4: slides and speaker notes inside pptx files.
if [[ -d presentation ]]; then
    if command -v unzip >/dev/null 2>&1; then
        while IFS= read -r -d '' f; do
            # Strip XML tags per paragraph so text split across <a:t> runs is rejoined.
            m="$(unzip -p "$f" 'ppt/slides/*.xml' 'ppt/notesSlides/*.xml' 2>/dev/null \
                | sed -e "s#</a:p>#&\\${nl}#g" -e 's/<[^>]*>//g' \
                | grep -ioE ".{0,30}($re1).{0,30}" | sort | uniq -c | sed -E 's/^ +//' || true)"
            [[ -n "$m" ]] && report "pptx contains forbidden syntax: $f" "$m"
        done < <(find presentation -type f -name '*.pptx' -print0 | sort -z)
    else
        echo "forbidden-syntax: warning: unzip not found, skipping pptx scan" >&2
    fi
fi

if (( fail )); then
    echo "forbidden-syntax: FAILED ($total hit lines)"
    exit 1
fi
echo "forbidden-syntax: OK"
