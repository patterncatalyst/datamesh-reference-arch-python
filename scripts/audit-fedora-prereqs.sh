#!/usr/bin/env bash
#
# audit-fedora-prereqs.sh — capture the Fedora 44 environment state
# this tutorial assumes. Run once before writing each new section;
# paste the output into the iteration thread so version pins in the
# reconciliation plan can be set from real data, not guesses.
#
# Safe to re-run any number of times. Modifies nothing; reads only.
#
# Usage:
#   ./scripts/audit-fedora-prereqs.sh                  # print to stdout
#   ./scripts/audit-fedora-prereqs.sh > /tmp/audit.txt # capture to file

section() { printf '\n=== %s ===\n' "$*"; }

# Run a command if its first argument is on PATH; otherwise report
# cleanly. Avoids bash's "command not found" stderr noise that the
# r03 version of this script let through.
maybe() {
    if command -v "$1" >/dev/null 2>&1; then
        "$@" 2>&1 || echo "  (command failed)"
    else
        echo "  ($1 not present)"
    fi
}

section "platform"
cat /etc/fedora-release 2>&1 || echo "(not a Fedora system?)"
uname -srm

section "hardware"
echo "CPUs: $(nproc)"
free -h
df -h ~ /

section "container engine: podman"
maybe podman --version
# Note: CgroupVersion field was removed from podman info template in
# podman 5.x; dropped to keep output clean.
maybe podman info --format \
  '{{.Host.OS}} {{.Host.Arch}} rootless={{.Host.Security.Rootless}}'

section "container engine: docker CLI (optional)"
maybe docker --version

section "currently installed tutorial tools (PATH)"
for tool in minikube kubectl helm istioctl stern kubectx kubens yq krew httpie hey gh; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf '  %-12s %s\n' "$tool" "$(command -v "$tool")"
    else
        printf '  %-12s (not installed)\n' "$tool"
    fi
done

section "current versions (where installed)"
maybe minikube version
maybe kubectl version --client=true
maybe helm version --short
maybe istioctl version --remote=false

section "what's in Fedora 44 dnf repos"
for pkg in minikube kubectl kubernetes-client helm stern kubectx httpie yq; do
    printf '\n--- dnf info %s ---\n' "$pkg"
    if dnf info "$pkg" >/dev/null 2>&1; then
        dnf info "$pkg" 2>&1 \
          | awk '/^Name|^Version|^Release|^Repository|^Summary/{print}' \
          | head -10
    else
        echo "(no package named $pkg in current repos)"
    fi
done

section "kernel limits (matters for §11 multi-cluster)"
INSTANCES=$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)
WATCHES=$(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo 0)
echo "  fs.inotify.max_user_instances = ${INSTANCES}"
echo "  fs.inotify.max_user_watches   = ${WATCHES}"
if [[ "${INSTANCES}" -ge 256 ]] && [[ "${WATCHES}" -ge 131072 ]]; then
    echo "  STATUS: ✓ OK for running a second minikube profile (§11)"
else
    echo "  STATUS: ⚠ defaults — fine for §3-§10 (one cluster) but"
    echo "          NOT for §11 (two clusters: minikube + istio)."
    echo "          Fix from §1 prereqs 'Kernel limits' subsection:"
    echo ""
    echo "          sudo tee /etc/sysctl.d/99-kubernetes.conf <<EOF"
    echo "          fs.inotify.max_user_instances = 512"
    echo "          fs.inotify.max_user_watches = 524288"
    echo "          EOF"
    echo "          sudo sysctl -p /etc/sysctl.d/99-kubernetes.conf"
fi

section "kernel modules (CNI portmap in a rootless node needs legacy iptables NAT)"
MISSING_MODS=""
for m in ip_tables iptable_nat ip6_tables; do
    if [[ -d "/sys/module/${m}" ]]; then
        printf '  %-12s loaded\n' "$m"
    else
        printf '  %-12s NOT LOADED\n' "$m"
        MISSING_MODS="${MISSING_MODS} ${m}"
    fi
done
if [[ -z "$MISSING_MODS" ]]; then
    echo "  STATUS: ✓ OK — hostPort pods (registry proxy) can start"
else
    echo "  STATUS: ⚠ the rootless minikube node cannot modprobe these itself;"
    echo "          hostPort pods will fail sandbox creation. Fix:"
    echo ""
    echo "          sudo sh -c 'printf \"ip_tables\\niptable_nat\\nip6_tables\\n\" > /etc/modules-load.d/99-kubernetes-iptables.conf'"
    echo "          sudo systemctl restart systemd-modules-load"
fi

section "podman pids_limit (capstone node runs ~2000+ tasks — CAP-040)"
PIDS_LIMIT=$(
    grep -hsE '^[[:space:]]*pids_limit[[:space:]]*=' \
        "${HOME}/.config/containers/containers.conf" \
        /etc/containers/containers.conf 2>/dev/null \
        | tail -1 | grep -oE '[0-9]+' | tail -1 || true
)
PIDS_LIMIT="${PIDS_LIMIT:-2048}"
echo "  effective pids_limit = ${PIDS_LIMIT} (0 = unlimited)"
if [[ "$PIDS_LIMIT" == "0" ]] || (( PIDS_LIMIT >= 8192 )); then
    echo "  STATUS: ✓ OK for the full meshed capstone"
else
    echo "  STATUS: ⚠ the node would cap TOTAL processes across all pods at ${PIDS_LIMIT}"
    echo "          and the last pods fail to fork (EAGAIN, runc exit 128). Fix"
    echo "          BEFORE creating the node:"
    echo ""
    echo "          mkdir -p ~/.config/containers"
    echo "          printf '[containers]\\npids_limit = 0\\n' >> ~/.config/containers/containers.conf"
fi

section "istio distribution (setup-kiali.sh needs samples/addons/kiali.yaml)"
ISTIO_CURRENT="${HOME}/.local/share/istio-current"
if [[ -f "${ISTIO_CURRENT}/samples/addons/kiali.yaml" ]]; then
    echo "  ${ISTIO_CURRENT} → $(readlink -f "$ISTIO_CURRENT" 2>/dev/null || echo "$ISTIO_CURRENT")"
    echo "  STATUS: ✓ full distribution present (istioctl alone is not enough)"
else
    echo "  STATUS: ⚠ ${ISTIO_CURRENT}/samples/addons/kiali.yaml not found —"
    echo "          bootstrap tier 9 (Kiali) will fail. Fix:"
    echo ""
    echo "          curl -fsSL https://github.com/istio/istio/releases/download/1.26.2/istio-1.26.2-linux-amd64.tar.gz | tar xz -C ~/.local/share"
    echo "          ln -sfn ~/.local/share/istio-1.26.2 ~/.local/share/istio-current"
fi

section "minikube minimum version (1.35's registry addon pins a dead image digest)"
if command -v minikube >/dev/null 2>&1; then
    MK_VERSION="$(minikube version --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo v0.0.0)"
    echo "  minikube ${MK_VERSION} at $(command -v minikube)"
    if [[ "$(printf '%s\n' "v1.36.0" "$MK_VERSION" | sort -V | head -1)" == "v1.36.0" ]]; then
        echo "  STATUS: ✓ OK (>= 1.36)"
    else
        echo "  STATUS: ⚠ too old — the registry addon can never come up on < 1.36."
        echo "          Install a current minikube (e.g. to ~/.local/bin, which"
        echo "          precedes /usr/local/bin on PATH)."
    fi
else
    echo "  (minikube not present)"
fi

section "done"
echo "Paste the entire output above (from === platform === down) into"
echo "the iteration thread so version pins can be set from real data."
