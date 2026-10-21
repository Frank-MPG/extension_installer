#!/bin/bash
# Installe ou met à jour les extensions Chrome MPG (Google Chrome et Arc).
# Lancé par le raccourci macOS « Extensions MPG » :
#
#   curl -fsSL https://raw.githubusercontent.com/frank-mpg/extension_installer/main/install.sh | bash
#
# Pour chaque extension : télécharge la dernière release GitHub (fichier extension.zip de
# frank-mpg/extension_<nom>) et la place dans ~/Extensions MPG/<Nom lisible>/.
# - Première installation : ouvre le dossier dans le Finder et la page Extensions de chaque
#   navigateur installé (Google Chrome, Arc).
# - Mise à jour : remplace les fichiers (manifest.json en dernier) ; chaque extension se
#   recharge seule dans la minute, dans tous les navigateurs où elle est chargée
#   (Chrome, Arc… cf. autoreload.js).
#
# Compatible avec le bash 3.2 de macOS. Variables pour les tests :
#   MPG_EXT_BASE (défaut https://github.com/frank-mpg), MPG_EXT_DEST, MPG_EXT_NO_OPEN=1
set -u

BASE="${MPG_EXT_BASE:-https://github.com/frank-mpg}"
DEST="${MPG_EXT_DEST:-$HOME/Extensions MPG}"
NO_OPEN="${MPG_EXT_NO_OPEN:-}"

# dossier du dépôt (frank-mpg/extension_<clé>) | nom du dossier installé | ancien nom du dossier
# Renommer un dossier = l'extension change d'identité dans Chrome (nouvel ID, réglages remis à
# zéro) : garder l'ancien nom en 3e colonne pour que retire_old() neutralise l'ancienne copie.
EXTS="auto_leagues|Ligues de test|MPG Tools
api_url|Changer d'API|API URL
custom_user|Custom user|Outils (custom user)
mpp_points_calculator|Calcul des points pronos|MPP Prono Selector
ui_improvements|Thème et correctifs UI|Bannière dynamique"

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

# Ancien dossier d'une extension renommée : on le remplace par une extension vide (sans script)
# qui demande à être supprimée. La copie déjà chargée s'y recharge seule dans la minute
# (autoreload.js voit une nouvelle version), ce qui évite de l'avoir en double avec la nouvelle.
STUB_MARK="mpg-ancienne-extension"
retire_old() { # <ancien dossier> <nouveau nom> ; renvoie 0 si neutralisé à l'instant
  [ -f "$1/manifest.json" ] || return 1
  grep -q "$STUB_MARK" "$1/manifest.json" 2>/dev/null && return 1
  find "$1" -mindepth 1 -maxdepth 1 ! -name manifest.json -exec rm -rf {} +
  cat > "$1/manifest.json" <<JSON
{
  "manifest_version": 3,
  "name": "À supprimer – remplacée par « $2 »",
  "version": "99.0.0",
  "description": "Ancienne version ($STUB_MARK). Supprimez-la et chargez le dossier « $2 »."
}
JSON
}

installed=""; updated=""; same=""; failed=""; renamed=""
while IFS='|' read -r key name prev; do
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
  if [ -n "$prev" ] && retire_old "$DEST/$prev" "$name"; then
    renamed="$renamed\n  - « $prev » est devenue « $name »"
  fi
done <<< "$EXTS"

cat > "$DEST/LISEZMOI.txt" <<'TXT'
Extensions Chrome MPG

Ne déplacez pas, ne renommez pas et ne supprimez pas ce dossier :
Chrome et Arc chargent les extensions directement depuis ici.

Mettre à jour : lancer le raccourci « Extensions MPG ».
Ajouter une extension : chrome://extensions (Chrome) ou arc://extensions (Arc) >
Mode développeur > « Charger l'extension non empaquetée » > choisir son dossier.
TXT

# Navigateurs gérés : nom de l'app | page des extensions
BROWSERS="Google Chrome|chrome://extensions/
Arc|arc://extensions"

app_installed() { [ -d "/Applications/$1.app" ] || [ -d "$HOME/Applications/$1.app" ]; }

# Ouvre la page des extensions dans un nouvel onglet (macOS demande l'autorisation la 1re fois).
# Un script par navigateur : AppleScript doit connaître l'app à la compilation pour « tab » et « URL ».
open_extensions_page() { # <app> <url>
  case "$1" in
    "Google Chrome") osascript - "$2" >/dev/null 2>&1 <<'OSA'
on run argv
  tell application "Google Chrome"
    activate
    if (count of windows) is 0 then make new window
    tell front window to make new tab with properties {URL:(item 1 of argv)}
  end tell
end run
OSA
    ;;
    "Arc") osascript - "$2" >/dev/null 2>&1 <<'OSA'
on run argv
  tell application "Arc"
    activate
    if (count of windows) is 0 then make new window
    tell front window to make new tab with properties {URL:(item 1 of argv)}
  end tell
end run
OSA
    ;;
    *) return 1 ;;
  esac
}

# ---------- Résumé (affiché par le raccourci) ----------
if [ -n "$installed" ]; then
  printf 'Installées :%b\n\n' "$installed"
fi
if [ -n "$updated" ]; then
  printf 'Mises à jour :%b\n' "$updated"
  printf 'Elles se rechargent toutes seules dans Chrome et Arc dans la minute. Rechargez ensuite vos onglets MPG.\n\n'
fi
if [ -n "$same" ]; then
  printf 'Déjà à jour :%b\n\n' "$same"
fi
if [ -n "$failed" ]; then
  printf 'Problèmes :%b\n\n' "$failed"
fi
if [ -n "$renamed" ]; then
  printf 'Extensions renommées :%b\n' "$renamed"
  printf 'Dans la page Extensions, supprimez celles marquées « À supprimer » (et leur ancien dossier), puis chargez les nouveaux dossiers. Leurs réglages et historiques repartent de zéro.\n\n'
fi

if [ -n "$installed" ] && [ -z "$NO_OPEN" ]; then
  printf '%s' "$DEST" | pbcopy 2>/dev/null
  open "$DEST" 2>/dev/null
  opened=""; manual=""
  while IFS='|' read -r app url; do
    app_installed "$app" || continue
    if open_extensions_page "$app" "$url"; then opened="$opened, $app"; else manual="$manual\n  - $app : tapez $url dans la barre d’adresse"; fi
  done <<< "$BROWSERS"
  if [ -n "$opened" ]; then
    printf 'Étape suivante, dans %s (page Extensions ouverte) :\n' "${opened#, }"
  else
    printf 'Étape suivante : ouvrez la page Extensions de votre navigateur (chrome://extensions ou arc://extensions), puis :\n'
  fi
  [ -n "$manual" ] && printf 'Page à ouvrir à la main :%b\n' "$manual"
  printf '  1. Activez « Mode développeur » (en haut à droite).\n'
  printf '  2. Cliquez « Charger l’extension non empaquetée ».\n'
  printf '  3. Faites Cmd + Maj + G, puis Cmd + V (le chemin du dossier est déjà copié), Entrée.\n'
  printf '  4. Choisissez le dossier d’une extension, puis « Sélectionner ». Recommencez pour chacune.\n'
  printf 'Vous utilisez Chrome et Arc ? Faites ces étapes dans les deux.\n'
elif [ -z "$installed$updated$failed" ]; then
  printf 'Dossier des extensions : %s\n' "$DEST"
fi
exit 0
