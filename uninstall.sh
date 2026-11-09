#!/usr/bin/env bash
#
# Retire le zram et le reclaim installés par install.sh, puis restaure les
# valeurs noyau par défaut de Debian/Ubuntu.
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "ERREUR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "à lancer en root : sudo ./uninstall.sh"

# ------------------------------------------------------------------ services
echo "==> Arrêt des services"
systemctl disable --now zram-reclaim.service 2>/dev/null || true
systemctl disable --now zramswap.service 2>/dev/null || true

# ------------------------------------------------------------------- fichiers
echo "==> Suppression des fichiers"
rm -f /etc/systemd/system/zram-reclaim.service
rm -f /usr/local/bin/zram-reclaim.sh
rm -f /etc/sysctl.d/99-ml-zram.conf
systemctl daemon-reload

# ------------------------------------------------ restauration du conffile
if [[ -f /etc/default/zramswap.pre-zram-config ]]; then
    echo "==> Restauration de /etc/default/zramswap d'origine"
    cp -a /etc/default/zramswap.pre-zram-config /etc/default/zramswap
    rm -f /etc/default/zramswap.pre-zram-config
else
    echo "==> Restauration du conffile livré par zram-tools"
    install -Dm 0644 "$SRC/etc/default/zramswap.debian-default" /etc/default/zramswap
fi

# ------------------------------------------------- valeurs noyau par défaut
# Les fichiers sysctl supprimés ne réinitialisent pas les valeurs déjà en
# mémoire : on remet explicitement les défauts du noyau.
echo "==> Retour aux réglages noyau par défaut"
sysctl -q -w vm.swappiness=60
sysctl -q -w vm.vfs_cache_pressure=100
sysctl -q -w vm.page_cluster=3
sysctl -q -w vm.watermark_boost_factor=15000

echo
echo "Terminé. zramswap.service est désactivé ; zram-tools reste installé."
echo "Pour le retirer complètement : sudo apt remove zram-tools"
