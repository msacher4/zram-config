# zram-config

Configuration zram + swap compressé utilisée sur ma machine (Linux Mint 22.3,
noyau 6.17, 23 Go de RAM). Ce dépôt contient les quatre fichiers qui font le
travail, plus un `install.sh` idempotent et un `uninstall.sh` qui remet le
système dans son état d'origine.

L'intérêt du setup n'est pas zram seul — c'est un paquet Debian et trois lignes
de config — mais le **service de reclaim** qui force en continu les pages
inactives à passer dans le swap compressé.

## Ce que ça donne

```
NAME       ALGORITHM DISKSIZE  DATA COMPR TOTAL STREAMS MOUNTPOINT
/dev/zram0 zstd         46,8G  5,6G  1,7G  1,8G         [SWAP]
```

46,8 Go de swap pour 23 Go de RAM (200 %), taux de compression réel ≈ 3,3:1 sous
charge de compilation et de LLM locaux. 5,6 Go de pages occupent 1,8 Go de RAM.

## Les fichiers

| Chemin | Rôle |
|---|---|
| `etc/default/zramswap` | paramètres lus par `zramswap.service` (paquet `zram-tools`) : `ALGO=zstd`, `PERCENT=200`, `PRIORITY=100` |
| `etc/sysctl.d/99-ml-zram.conf` | réglages noyau orientés « le swap est rapide, donc autant swapper » |
| `usr/local/bin/zram-reclaim.sh` | pousse `100M` dans `/sys/fs/cgroup/memory.reclaim` toutes les 3 s |
| `etc/systemd/system/zram-reclaim.service` | lance le script, `Requires=`/`After=` `zramswap.service` |

## Pourquoi ces réglages

**`PERCENT=200`** — le disque zram fait deux fois la RAM. Un disque zram ne
consomme que ce qu'il stocke, donc le surdimensionner ne coûte rien tant qu'il
n'est pas rempli. Ça évite de saturer le swap au pire moment.

**`ALGO=zstd`** — meilleur ratio disponible sans coût CPU excessif ; sur un
processeur moderne la compression/décompression reste plus rapide que la lecture
sur un SSD.

**`vm.swappiness = 100`** — le défaut (60) suppose un disque lent. Avec un swap
en RAM compressée, swapper agressivement libère de la mémoire physique pour le
cache de fichiers, ce qui est presque toujours gagnant.

**`vm.page-cluster = 0`** — pagination d'une seule page à la fois. Le readahead
par blocs de 2^n pages est contre-productif sur du swap compressé : décompresser
des pages voisines qui ne seront jamais lues coûte du CPU.

**`vm.watermark_boost_factor = 0`** — désactive la réserve supplémentaire que
le noyau gonfle en cas de pression mémoire. Avec un swap rapide, ce coussin
provoque plus de réclaim précoce qu'il n'évite de blocages.

**`vm.vfs_cache_pressure = 50`** — garde les dentries/inodes en cache plus
longtemps ; ils sont reconstructibles mais coûteux à recharger.

**`vm.min_free_kbytes = 24576`** — plancher de mémoire libre pour que les
allocations atomiques ne déclenchent pas de réclaim direct.

## Le reclaim en boucle (la partie qui compte)

zram seul a un défaut connu : les pages écrites une fois restent dans le disque
compressé. Une page qui n'est plus jamais lue occupe de la RAM sous forme
compressée **et** de la RAM sous forme de cache. Le noyau ne va pas spontanément
les évincer, parce qu'il n'a aucune raison de croire que le swap est rapide.

`memory.reclaim` (cgroup v2) permet de demander explicitement l'éviction d'un
volume de pages d'un cgroup. En écrivant `100M` toutes les 3 secondes dans la
racine, on obtient un flux lent et continu : les pages froides partent vers
zram, les chaudes restent. Pas de pic, pas de blocage — juste une pression
constante qui maintient la mémoire physique disponible.

```bash
echo 3 > /proc/sys/vm/drop_caches   # au démarrage seulement
while true; do
    echo "100M" > /sys/fs/cgroup/memory.reclaim
    sleep 3
done
```

Prérequis : cgroup v2 avec le contrôleur mémoire activé sur la racine
(`/sys/fs/cgroup/memory.reclaim` inscriptible en root). `install.sh` vérifie ce
point et avertit si le script ne pourra pas fonctionner.

## Installation

```bash
git clone https://github.com/msacher4/zram-config
cd zram-config
sudo ./install.sh
```

Le script installe `zram-tools` si nécessaire, sauvegarde
`/etc/default/zramswap` dans `/etc/default/zramswap.pre-zram-config`, copie les
fichiers avec les bons droits, applique les `sysctl`, puis active et redémarre
les deux services.

Vérification :

```bash
zramctl
swapon --show
systemctl status zramswap.service zram-reclaim.service
journalctl -t zram-reclaim -f
```

## Désinstallation

```bash
sudo ./uninstall.sh
```

Désactive les services, supprime les fichiers ajoutés, restaure
`/etc/default/zramswap` d'origine et remet les `sysctl` aux valeurs par défaut du
noyau. `zram-tools` reste installé — `sudo apt remove zram-tools` pour finir.

## Ajustements

- `PERCENT` : 200 convient jusqu'à ~16 Go de RAM. Au-delà, 100–150 suffit ; en
  dessous de 8 Go, monter à 250–300 est raisonnable.
- `RECLAIM_AMOUNT` / `INTERVAL` dans `zram-reclaim.sh` : `100M/3s` est un
  compromis pour 23 Go. Sur une machine plus petite, descendre à `50M/5s` évite
  de lutter en permanence contre le workload.
- `vm.min_free_kbytes` et `vm.watermark_boost_factor` sont sensibles à la taille
  de la RAM : à recalculer si la machine change.

## Limites connues

- L'hibernation nécessite un swap persistant sur disque ; zram seul ne suffit
  pas.
- Le swap zram n'est pas chiffré sur disque (il n'y a pas de disque) mais il
  reste lisible en RAM par le noyau.
- Le reclaim en boucle consomme un peu de CPU en continu ; c'est visible dans
  `top` mais négligeable face au gain sur les workloads qui débordent la RAM.
- `/etc/default/zramswap` appartient au paquet `zram-tools` : une mise à jour
  majeure du paquet peut proposer d'écraser le fichier. Répondre « garder ».
