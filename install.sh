#!/bin/bash
# Installe ou met à jour les extensions Chrome MPG.
# Lancé par le raccourci macOS « Extensions MPG » :
#
#   curl -fsSL https://raw.githubusercontent.com/frank-mpg/extension_installer/main/install.sh | bash
#
# Pour chaque extension : télécharge la dernière release GitHub (fichier extension.zip de
# frank-mpg/extension_<nom>) et la place dans ~/Extensions MPG/<Nom lisible>/.
# - Première installation : ouvre le dossier dans le Finder et la page chrome://extensions.
# - Mise à jour : remplace les fichiers (manifest.json en dernier) ; chaque extension se
#   recharge seule dans Chrome dans la minute (cf. autoreload.js).
#
# Compatible avec le bash 3.2 de macOS. Variables pour les tests :
#   MPG_EXT_BASE (défaut https://github.com/frank-mpg), MPG_EXT_DEST, MPG_EXT_NO_OPEN=1
set -u

BASE="${MPG_EXT_BASE:-https://github.com/frank-mpg}"
DEST="${MPG_EXT_DEST:-$HOME/Extensions MPG}"
NO_OPEN="${MPG_EXT_NO_OPEN:-}"

# dossier du dépôt (frank-mpg/extension_<clé>) | nom du dossier installé
EXTS="auto_leagues|MPG Tools
api_url|API URL
custom_user|Outils (custom user)
mpp_points_calculator|MPP Prono Selector
ui_improvements|Bannière dynamique"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! mkdir -p "$DEST"; then
  echo "Impossible de créer le dossier $DEST"
  exit 0
fi

version_of() {
  sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -n 1
}

# Copie tout sauf manifest.json (copié à part, en dernier)
sync_dir() {
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude manifest.json "$1/" "$2/"
  else
    find "$2" -mindepth 1 -maxdepth 1 ! -name manifest.json -exec rm -rf {} +
    cp -R "$1/." "$2/"
  fi
}

installed=""; updated=""; same=""; failed=""
while IFS='|' read -r key name; do
  [ -n "$key" ] || continue
  zip="$TMP/$key.zip"; src="$TMP/$key"; dst="$DEST/$name"

  if ! curl -fsL --retry 2 --connect-timeout 10 -o "$zip" \
      "$BASE/extension_$key/releases/latest/download/extension.zip"; then
    failed="$failed\n  - $name : téléchargement impossible (pas de connexion, ou pas encore publiée)"
    continue
  fi
  mkdir -p "$src"
  if ! unzip -qo "$zip" -d "$src" || [ ! -f "$src/manifest.json" ]; then
    failed="$failed\n  - $name : archive invalide"
    continue
  fi

  new="$(version_of "$src/manifest.json")"
  old=""
  [ -f "$dst/manifest.json" ] && old="$(version_of "$dst/manifest.json")"
  if [ -n "$old" ] && [ "$old" = "$new" ]; then
    same="$same\n  - $name ($new)"
    continue
  fi

  mkdir -p "$dst"
  if ! sync_dir "$src" "$dst" || ! cp "$src/manifest.json" "$dst/manifest.json"; then
    failed="$failed\n  - $name : copie impossible dans $dst"
    continue
  fi
  if [ -z "$old" ]; then
    installed="$installed\n  - $name ($new)"
  else
    updated="$updated\n  - $name : $old -> $new"
  fi
done <<< "$EXTS"

cat > "$DEST/LISEZMOI.txt" <<'TXT'
Extensions Chrome MPG

Ne déplacez pas, ne renommez pas et ne supprimez pas ce dossier :
Chrome charge les extensions directement depuis ici.

Mettre à jour : lancer le raccourci « Extensions MPG ».
Ajouter une extension dans Chrome : chrome://extensions > Mode développeur >
« Charger l'extension non empaquetée » > choisir son dossier.
TXT

open_chrome_extensions() {
  osascript >/dev/null 2>&1 <<'OSA'
tell application "Google Chrome"
  activate
  if (count of windows) is 0 then make new window
  tell front window to make new tab with properties {URL:"chrome://extensions/"}
end tell
OSA
}

# ---------- Résumé (affiché par le raccourci) ----------
if [ -n "$installed" ]; then
  printf 'Installées :%b\n\n' "$installed"
fi
if [ -n "$updated" ]; then
  printf 'Mises à jour :%b\n' "$updated"
  printf 'Chrome les recharge tout seul dans la minute. Rechargez ensuite vos onglets MPG.\n\n'
fi
if [ -n "$same" ]; then
  printf 'Déjà à jour :%b\n\n' "$same"
fi
if [ -n "$failed" ]; then
  printf 'Problèmes :%b\n\n' "$failed"
fi

if [ -n "$installed" ] && [ -z "$NO_OPEN" ]; then
  printf '%s' "$DEST" | pbcopy 2>/dev/null
  open "$DEST" 2>/dev/null
  if open_chrome_extensions; then
    printf 'Étape suivante, dans Chrome (onglet Extensions ouvert) :\n'
  else
    printf 'Étape suivante : ouvrez Chrome et tapez chrome://extensions dans la barre d’adresse, puis :\n'
  fi
  printf '  1. Activez « Mode développeur » (en haut à droite).\n'
  printf '  2. Cliquez « Charger l’extension non empaquetée ».\n'
  printf '  3. Faites Cmd + Maj + G, puis Cmd + V (le chemin du dossier est déjà copié), Entrée.\n'
  printf '  4. Choisissez le dossier d’une extension, puis « Sélectionner ». Recommencez pour chacune.\n'
elif [ -z "$installed$updated$failed" ]; then
  printf 'Dossier des extensions : %s\n' "$DEST"
fi
exit 0
