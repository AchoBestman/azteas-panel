#!/bin/bash
set -euo pipefail

# ============================================================
# Ajoute/retire le routage Traefik d'un domaine client vers son pod ou
# instance Incus, sur le nœud d'hébergement (voir how-to-use-this-on-new-VDS.md,
# partie 10). CE SCRIPT S'EXECUTE SUR LE VDS D'HEBERGEMENT.
#
# Remplace l'écriture manuelle du fichier YAML par domaine — même résultat,
# reproductible et sans risque de faute de frappe dans le YAML.
#
# Usage :
#   ./add-client-domain.sh add    <domaine> <port-http-interne> [FORCE=1]
#   ./add-client-domain.sh remove <domaine>
#
# Exemple :
#   ./add-client-domain.sh add client1.com 8001
#   FORCE=1 ./add-client-domain.sh add client1.com 8002   # écrase la route existante
#   ./add-client-domain.sh remove client1.com
# ============================================================

DYNAMIC_DIR="/opt/hosting-vds/traefik/dynamic"
ACTION="${1:-}"
DOMAIN="${2:-}"
PORT="${3:-}"

usage() {
    echo "Usage:"
    echo "  $0 add <domaine> <port-http-interne>"
    echo "  $0 remove <domaine>"
    exit 1
}

[ -z "$ACTION" ] && usage
[ -z "$DOMAIN" ] && usage

if [ ! -d "$DYNAMIC_DIR" ]; then
    echo "❌ $DYNAMIC_DIR introuvable — le Traefik de ce nœud est-il déjà déployé ?"
    echo "   Voir how-to-use-this-on-new-VDS.md, partie 5."
    exit 1
fi

# Nom de fichier sûr à partir du domaine (les points ne posent pas
# problème dans un nom de fichier, mais on les remplace pour éviter toute
# ambiguïté avec l'extension .yml).
SAFE_NAME=$(echo "$DOMAIN" | tr '.' '-')
FILE="$DYNAMIC_DIR/client-${SAFE_NAME}.yml"

case "$ACTION" in
  add)
    [ -z "$PORT" ] && usage
    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo "❌ Port invalide : '$PORT' (doit être un nombre)"
        exit 1
    fi

    # Garde-fou : ne pas écraser silencieusement une route existante (ex:
    # faute de frappe sur un domaine déjà attribué à un autre client) —
    # sauf si FORCE=1 est explicitement passé.
    if [ -f "$FILE" ] && [ "${FORCE:-}" != "1" ]; then
        echo "⚠️  Une route existe déjà pour ${DOMAIN} :"
        echo ""
        cat "$FILE"
        echo ""
        echo "Relancer avec FORCE=1 pour écraser volontairement :"
        echo "  FORCE=1 $0 add ${DOMAIN} ${PORT}"
        exit 1
    fi

    cat > "$FILE" <<EOF
# Généré par add-client-domain.sh le $(date -u +%Y-%m-%dT%H:%M:%SZ) — ne
# pas éditer à la main, relancer le script (avec FORCE=1) pour modifier.
http:
  routers:
    client-${SAFE_NAME}:
      rule: "Host(\`${DOMAIN}\`)"
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt-http
      service: client-${SAFE_NAME}-svc
  services:
    client-${SAFE_NAME}-svc:
      loadBalancer:
        servers:
          - url: "http://host.docker.internal:${PORT}"
EOF
    echo "✅ Route ajoutée : ${DOMAIN} -> host.docker.internal:${PORT}"
    echo "   Fichier : $FILE"
    echo "   Traefik surveille dynamic/ (watch: true) — pris en compte"
    echo "   automatiquement, aucun redémarrage nécessaire."
    echo "   Le certificat Let's Encrypt s'obtient à la première requête"
    echo "   HTTPS réelle — le DNS du client doit déjà pointer vers ce VDS,"
    echo "   sinon le challenge HTTP-01 échoue silencieusement en boucle."
    ;;

  remove)
    if [ -f "$FILE" ]; then
        rm -f "$FILE"
        echo "✅ Route retirée : ${DOMAIN}"
    else
        echo "⚠️  Aucune route trouvée pour ${DOMAIN} (fichier $FILE absent) — rien à faire."
    fi
    ;;

  *)
    usage
    ;;
esac
