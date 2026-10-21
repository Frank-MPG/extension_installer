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
#   MPG_EXT_BASE (défaut https://github.com/frank-mpg), MPG_EXT_DEST, MPG_EXT_NO_OPEN=1,
#   MPG_EXT_REPORT=<fichier.html> (écrit le résumé HTML sans l'afficher)
#
# Résumé : une page HTML affichée dans une fenêtre Coup d'œil (qlmanage), à défaut dans le
# navigateur ; le texte renvoyé au raccourci (« Afficher le résultat ») se réduit alors à une ligne.
set -u

BASE="${MPG_EXT_BASE:-https://github.com/frank-mpg}"
DEST="${MPG_EXT_DEST:-$HOME/Extensions MPG}"
NO_OPEN="${MPG_EXT_NO_OPEN:-}"
REPORT_ONLY="${MPG_EXT_REPORT:-}"

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

html_esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# Lignes du résumé HTML : <état new|up|same|err> <nom> <détail>
ROWS=""; n_new=0; n_up=0; n_same=0; n_err=0
add_row() {
  local label
  case "$1" in
    new)  label="Installée";   n_new=$((n_new + 1)) ;;
    up)   label="Mise à jour"; n_up=$((n_up + 1)) ;;
    same) label="À jour";      n_same=$((n_same + 1)) ;;
    *)    label="Problème";    n_err=$((n_err + 1)) ;;
  esac
  ROWS="$ROWS<li class=\"$1\"><span class=\"dot\"></span><span class=\"t\"><b>$(html_esc "$2")</b><small>$(html_esc "$3")</small></span><span class=\"tag\">$label</span></li>"
}

installed=""; updated=""; same=""; failed=""; renamed=""
while IFS='|' read -r key name prev; do
  [ -n "$key" ] || continue
  zip="$TMP/$key.zip"; src="$TMP/$key"; dst="$DEST/$name"

  if ! curl -fsL --retry 2 --connect-timeout 10 -o "$zip" \
      "$BASE/extension_$key/releases/latest/download/extension.zip"; then
    failed="$failed\n  - $name : téléchargement impossible (pas de connexion, ou pas encore publiée)"
    add_row err "$name" "Téléchargement impossible : pas de connexion, ou pas encore publiée"
    continue
  fi
  mkdir -p "$src"
  if ! unzip -qo "$zip" -d "$src" || [ ! -f "$src/manifest.json" ]; then
    failed="$failed\n  - $name : archive invalide"
    add_row err "$name" "Archive téléchargée invalide"
    continue
  fi

  new="$(version_of "$src/manifest.json")"
  old=""
  [ -f "$dst/manifest.json" ] && old="$(version_of "$dst/manifest.json")"
  if [ -n "$old" ] && [ "$old" = "$new" ]; then
    same="$same\n  - $name ($new)"
    add_row same "$name" "Version $new"
    continue
  fi

  mkdir -p "$dst"
  if ! sync_dir "$src" "$dst" || ! cp "$src/manifest.json" "$dst/manifest.json"; then
    failed="$failed\n  - $name : copie impossible dans $dst"
    add_row err "$name" "Copie impossible dans le dossier"
    continue
  fi
  if [ -z "$old" ]; then
    installed="$installed\n  - $name ($new)"
    add_row new "$name" "Version $new"
  else
    updated="$updated\n  - $name : $old -> $new"
    add_row up "$name" "$old → $new"
  fi
  if [ -n "$prev" ] && retire_old "$DEST/$prev" "$name"; then
    renamed="$renamed\n  - « $prev » est devenue « $name »"
    RENAMED_HTML="${RENAMED_HTML:-}<li>« $(html_esc "$prev") » s’appelle maintenant « $(html_esc "$name") »</li>"
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

# ---------- Première installation : dossier + pages Extensions ----------
opened=""; manual=""
if [ -n "$installed" ] && [ -z "$NO_OPEN" ] && [ -z "$REPORT_ONLY" ]; then
  printf '%s' "$DEST" | pbcopy 2>/dev/null
  open "$DEST" 2>/dev/null
  while IFS='|' read -r app url; do
    app_installed "$app" || continue
    if open_extensions_page "$app" "$url"; then opened="$opened, $app"; else manual="$manual\n  - $app : tapez $url dans la barre d’adresse"; fi
  done <<< "$BROWSERS"
fi
opened="${opened#, }"

# ---------- Résumé texte (si la fenêtre ne peut pas s'afficher) ----------
print_text() {
  [ -n "$installed" ] && printf 'Installées :%b\n\n' "$installed"
  if [ -n "$updated" ]; then
    printf 'Mises à jour :%b\n' "$updated"
    printf 'Elles se rechargent toutes seules dans Chrome et Arc dans la minute. Rechargez ensuite vos onglets MPG.\n\n'
  fi
  [ -n "$same" ] && printf 'Déjà à jour :%b\n\n' "$same"
  [ -n "$failed" ] && printf 'Problèmes :%b\n\n' "$failed"
  if [ -n "$renamed" ]; then
    printf 'Extensions renommées :%b\n' "$renamed"
    printf 'Dans la page Extensions, supprimez celles marquées « À supprimer » (et leur ancien dossier), puis chargez les nouveaux dossiers. Leurs réglages et historiques repartent de zéro.\n\n'
  fi
  if [ -n "$installed" ]; then
    if [ -n "$opened" ]; then
      printf 'Étape suivante, dans %s (page Extensions ouverte) :\n' "$opened"
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
  return 0
}

# ---------- Résumé HTML ----------
plural() { if [ "$1" -gt 1 ]; then printf '%s %s' "$1" "$3"; else printf '%s %s' "$1" "$2"; fi; }
summary_line() {
  local parts=""
  [ "$n_new" -gt 0 ]  && parts="$parts · $(plural "$n_new" "installée" "installées")"
  [ "$n_up" -gt 0 ]   && parts="$parts · $(plural "$n_up" "mise à jour" "mises à jour")"
  [ "$n_same" -gt 0 ] && parts="$parts · $(plural "$n_same" "déjà à jour" "déjà à jour")"
  [ "$n_err" -gt 0 ]  && parts="$parts · $(plural "$n_err" "problème" "problèmes")"
  printf '%s' "${parts# · }"
}

build_html() {
  local title boxes="" where
  if [ "$n_new" -gt 0 ]; then title="Extensions téléchargées"
  elif [ "$n_up" -gt 0 ]; then title="Extensions mises à jour"
  elif [ "$n_same" -gt 0 ]; then title="Tout est à jour"
  else title="Quelque chose a coincé"; fi

  if [ "$n_new" -gt 0 ]; then
    if [ -n "$opened" ]; then where="dans $(html_esc "$opened") (page Extensions ouverte)"; else where="sur la page <code>chrome://extensions</code> ou <code>arc://extensions</code>"; fi
    boxes="$boxes<section class=\"box next\"><h2>Étape suivante, $where</h2><ol>
<li>Activez <b>Mode développeur</b>, en haut à droite.</li>
<li>Cliquez <b>Charger l’extension non empaquetée</b>.</li>
<li>Faites <kbd>⌘</kbd><kbd>⇧</kbd><kbd>G</kbd> puis <kbd>⌘</kbd><kbd>V</kbd> (le chemin est déjà copié) et <kbd>↩</kbd>.</li>
<li>Choisissez le dossier d’une extension, puis <b>Sélectionner</b>. Recommencez pour chacune.</li>
</ol><p>Chrome et Arc ? Faites-le dans les deux.</p></section>"
  fi
  if [ "$n_up" -gt 0 ]; then
    boxes="$boxes<section class=\"box ok\"><h2>Rien d’autre à faire</h2><p>Les extensions se rechargent toutes seules dans Chrome et Arc dans la minute. Rechargez ensuite vos onglets MPG.</p></section>"
  fi
  if [ -n "${RENAMED_HTML:-}" ]; then
    boxes="$boxes<section class=\"box warn\"><h2>Extensions renommées</h2><ul>$RENAMED_HTML</ul><p>Dans la page Extensions, supprimez celles marquées « À supprimer », puis chargez les nouveaux dossiers. Leurs réglages repartent de zéro.</p></section>"
  fi
  if [ "$n_err" -gt 0 ]; then
    boxes="$boxes<section class=\"box err\"><h2>En cas de problème</h2><p>Vérifiez la connexion internet et relancez le raccourci. Si ça persiste, prévenez Frank.</p></section>"
  fi

  cat <<HTML
<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><title>Extensions MPG</title>
<style>
:root{--bg:#f4f5f9;--card:#fff;--ink:#171b2c;--muted:#5d6379;--line:#e1e4ee;
--new:#2f6fed;--up:#16a34a;--same:#9aa0b4;--err:#dc2626;--warn:#d97706;--accent:#3446b8;color-scheme:light}
@media (prefers-color-scheme:dark){:root{--bg:#12141d;--card:#1b1e2b;--ink:#eceef6;--muted:#9aa0b8;--line:#2b2f42;
--new:#6b9bff;--up:#4ade80;--same:#6b7187;--err:#f87171;--warn:#fbbf24;--accent:#8e9cff;color-scheme:dark}}
*{box-sizing:border-box}
body{margin:0;padding:28px 30px 30px;background:var(--bg);color:var(--ink);font:14px/1.5 -apple-system,BlinkMacSystemFont,"SF Pro Text","Helvetica Neue",sans-serif;-webkit-font-smoothing:antialiased}
header{display:flex;align-items:center;gap:14px;margin-bottom:18px}
.logo{width:44px;height:44px;border-radius:11px;flex-shrink:0;background:linear-gradient(140deg,#4a5ee8,#8a4fe0);display:flex;align-items:center;justify-content:center;color:#fff;font:700 20px -apple-system,sans-serif}
h1{font:700 21px/1.2 -apple-system,"SF Pro Display",sans-serif;margin:0;letter-spacing:-.01em}
.sub{color:var(--muted);font-size:13px;margin-top:2px}
ul.list{list-style:none;margin:0;padding:0;background:var(--card);border:1px solid var(--line);border-radius:12px;overflow:hidden}
ul.list li{display:flex;align-items:center;gap:12px;padding:11px 14px;border-top:1px solid var(--line)}
ul.list li:first-child{border-top:0}
.dot{width:10px;height:10px;border-radius:50%;flex-shrink:0;background:var(--same)}
.t{flex:1;min-width:0;display:flex;flex-direction:column}
.t b{font-weight:600}
.t small{color:var(--muted);font-size:12.5px;font-variant-numeric:tabular-nums}
.tag{font-size:11.5px;font-weight:700;padding:3px 9px;border-radius:999px;white-space:nowrap;color:var(--same);border:1px solid currentColor}
li.new .dot{background:var(--new)} li.new .tag{color:var(--new)}
li.up .dot{background:var(--up)} li.up .tag{color:var(--up)}
li.err .dot{background:var(--err)} li.err .tag{color:var(--err)}
li.same{opacity:.8}
.box{margin-top:14px;padding:14px 16px;border-radius:12px;background:var(--card);border:1px solid var(--line);border-left:4px solid var(--accent)}
.box.ok{border-left-color:var(--up)} .box.warn{border-left-color:var(--warn)} .box.err{border-left-color:var(--err)} .box.next{border-left-color:var(--new)}
.box h2{font-size:14px;margin:0 0 6px}
.box p{margin:6px 0 0;color:var(--muted)}
.box ol,.box ul{margin:4px 0 0;padding-left:20px}
.box li{margin:3px 0}
kbd{font:600 11.5px -apple-system,sans-serif;padding:1px 6px;margin:0 1px;border:1px solid var(--line);border-bottom-width:2px;border-radius:5px;background:var(--bg)}
code{font:12px ui-monospace,Menlo,monospace;background:var(--bg);padding:1px 5px;border-radius:4px}
footer{margin-top:16px;color:var(--muted);font-size:12px}
</style></head>
<body>
<header><div class="logo">M</div><div><h1>$title</h1><div class="sub">$(html_esc "$(summary_line)") · $(date '+%d/%m à %H:%M')</div></div></header>
<ul class="list">$ROWS</ul>
$boxes
<footer>Dossier : <code>~/Extensions MPG</code> · Ne pas le déplacer ni le renommer.</footer>
</body></html>
HTML
}

# Affiche le résumé dans une fenêtre Coup d'œil ; à défaut, dans le navigateur par défaut.
show_report() {
  local dir="$HOME/Library/Caches/Extensions MPG" f
  f="$dir/Extensions MPG.html"
  mkdir -p "$dir" 2>/dev/null && build_html > "$f" 2>/dev/null || return 1
  if command -v qlmanage >/dev/null 2>&1; then
    pkill -x qlmanage >/dev/null 2>&1
    ( qlmanage -p "$f" >/dev/null 2>&1 & )
    sleep 1
    pgrep -x qlmanage >/dev/null 2>&1 && return 0
  fi
  open "$f" 2>/dev/null
}

if [ -n "$REPORT_ONLY" ]; then
  build_html > "$REPORT_ONLY"
  print_text
elif [ -z "$NO_OPEN" ] && show_report; then
  printf 'Extensions MPG : %s.\n' "$(summary_line)"
else
  print_text
fi
exit 0
