#!/usr/bin/env bash
#
# Installe la configuration zram + reclaim agressif sur un système Debian/Ubuntu-like.
# Idempotent : peut être relancé sans casser l'existant.
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "ERREUR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "à lancer en root : sudo ./install.sh"
command -v apt-get >/dev/null || die "ce script cible une distribution Debian/Ubuntu (apt-get introuvable)"

# ---------------------------------------------------------------- dépendance
echo "==> Dépendance : zram-tools"
if dpkg -s zram-tools >/dev/null 2>&1; then
    echo "    déjà installé"
else
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y zram-tools
fi

# ------------------------------------------------------- sauvegarde du conffile
# /etc/default/zramswap appartient au paquet zram-tools : on garde l'original
# une fois, pour que uninstall.sh puisse le restaurer à l'identique.
if [[ -f /etc/default/zramswap && ! -f /etc/default/zramswap.pre-zram-config ]]; then
    cp -a /etc/default/zramswap /etc/default/zramswap.pre-zram-config
    echo "    original sauvegardé dans /etc/default/zramswap.pre-zram-config"
fi

# -------------------------------------------------------------- copie fichiers
echo "==> Copie des fichiers"
install -Dm 0644 "$SRC/etc/default/zramswap"                    /etc/default/zramswap
install -Dm 0644 "$SRC/etc/sysctl.d/99-ml-zram.conf"            /etc/sysctl.d/99-ml-zram.conf
install -Dm 0644 "$SRC/etc/systemd/system/zram-reclaim.service" /etc/systemd/system/zram-reclaim.service
install -Dm 0755 "$SRC/usr/local/bin/zram-reclaim.sh"           /usr/local/bin/zram-reclaim.sh

# ------------------------------------------------------------------- sysctl
echo "==> Application des paramètres noyau"
sysctl --system >/dev/null

# ---------------------------------------------------- contrôle des prérequis
if [[ "$(stat -fc %T /sys/fs/cgroup)" != "cgroup2fs" ]] || [[ ! -e /sys/fs/cgroup/memory.reclaim ]]; then
    echo "AVERTISSEMENT: cgroup v2 avec memory.reclaim introuvable."
    echo "               zram-reclaim.service ne fonctionnera pas (boucle de redémarrage)."
    echo "               zram seul reste opérationnel."
fi

# ------------------------------------------------------------------ services
echo "==> Activation des services"
systemctl daemon-reload
systemctl enable zramswap.service
systemctl restart zramswap.service
systemctl enable --now zram-reclaim.service

# --------------------------------------------------------------- vérification
echo
echo "==> État"
zramctl
echo
swapon --show
echo
systemctl --no-pager --lines=0 status zramswap.service zram-reclaim.service | sed 's/^/    /'
echo
echo "Terminé. Journal du reclaim : journalctl -t zram-reclaim -f"
