#!/bin/bash
# Installe ou met à jour les extensions Chrome MPG (Google Chrome et Arc).
# Lancé par le raccourci macOS « Extensions MPG » :
#
#   curl -fsSL "https://raw.githubusercontent.com/frank-mpg/extension_installer/main/install.sh?t=$(date +%s)" | bash
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
#   MPG_EXT_REPORT=<fichier.html> (écrit le résumé HTML sans l'afficher),
#   MPG_EXT_DEBUG=1 (affiche l'erreur de la fenêtre de résumé ; journal : ~/Library/Caches/Extensions MPG/fenetre.log)
#
# Résumé : une page HTML affichée dans une petite fenêtre native (JXA + WKWebView, 460 px de
# large, hauteur ajustée au contenu, Échap pour fermer), à défaut dans le navigateur ; rien n'est
# alors écrit sur stdout (le raccourci n'a plus besoin de l'action « Afficher le résultat »).
set -u

BASE="${MPG_EXT_BASE:-https://github.com/frank-mpg}"
DEST="${MPG_EXT_DEST:-$HOME/Extensions MPG}"
NO_OPEN="${MPG_EXT_NO_OPEN:-}"
REPORT_ONLY="${MPG_EXT_REPORT:-}"
DEBUG="${MPG_EXT_DEBUG:-}"   # MPG_EXT_DEBUG=1 : affiche pourquoi la fenêtre de résumé ne s'ouvre pas

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

# Icônes du résumé (SVG en ligne, couleur = currentColor)
I_OK='<svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>'
I_UP='<svg viewBox="0 0 24 24"><path d="M12 3l1.9 5.6L19.5 10l-5.6 1.9L12 17.5l-1.9-5.6L4.5 10l5.6-1.4z"/><path d="M18.5 15.5l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z"/></svg>'
I_NEW='<svg viewBox="0 0 24 24"><path d="M12 4v11m0 0l-4.5-4.5M12 15l4.5-4.5M5 19.5h14"/></svg>'
I_ERR='<svg viewBox="0 0 24 24"><path d="M12 8v5.5M12 17h.01"/><path d="M10.3 3.9L2.6 17.5A2 2 0 0 0 4.3 20.5h15.4a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/></svg>'

# Lignes du résumé HTML : <état new|up|same|err> <nom> <version | ancienne version | message> [nouvelle version]
ROWS=""; n_new=0; n_up=0; n_same=0; n_err=0
add_row() {
  local label icon detail
  case "$1" in
    new)  label="Installée";   icon="$I_NEW"; n_new=$((n_new + 1)); detail="v$(html_esc "$3")" ;;
    up)   label="Mise à jour"; icon="$I_UP";  n_up=$((n_up + 1));   detail="<s>v$(html_esc "$3")</s><i>→</i><em>v$(html_esc "$4")</em>" ;;
    same) label="À jour";      icon="$I_OK";  n_same=$((n_same + 1)); detail="v$(html_esc "$3")" ;;
    *)    label="Problème";    icon="$I_ERR"; n_err=$((n_err + 1)); detail="$(html_esc "$3")" ;;
  esac
  ROWS="$ROWS<li class=\"$1\"><span class=\"ic\">$icon</span><span class=\"t\"><b>$(html_esc "$2")</b><small>$detail</small></span><span class=\"tag\">$label</span></li>"
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
    add_row same "$name" "$new"
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
    add_row new "$name" "$new"
  else
    updated="$updated\n  - $name : $old -> $new"
    add_row up "$name" "$old" "$new"
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

build_html() { # [native] : version pour la fenêtre (bouton Fermer, taille transmise)
  local title sub state icon boxes="" where cls="" total
  [ "${1:-}" = native ] && cls="native"
  total=$((n_new + n_up + n_same))
  # État global (bandeau du haut) : mise à jour > installation > à jour > problème
  if [ "$n_up" -gt 0 ]; then
    state="up"; icon="$I_UP"
    title="$(plural "$n_up" "extension mise à jour" "extensions mises à jour")"
    sub="Toutes fraîches, rechargées toutes seules dans la minute"
  elif [ "$n_new" -gt 0 ]; then
    state="new"; icon="$I_NEW"
    title="$(plural "$n_new" "extension téléchargée" "extensions téléchargées")"
    sub="Plus qu’à les charger dans le navigateur"
  elif [ "$n_same" -gt 0 ]; then
    state="ok"; icon="$I_OK"
    title="Tout est à jour"
    sub="$(plural "$n_same" "extension" "extensions") à la dernière version"
  else
    state="err"; icon="$I_ERR"
    title="Quelque chose a coincé"
    sub="Aucune extension n’a pu être récupérée"
  fi
  [ "$n_err" -gt 0 ] && [ "$total" -gt 0 ] && sub="$sub · $(plural "$n_err" "problème" "problèmes")"

  if [ "$n_new" -gt 0 ]; then
    if [ -n "$opened" ]; then where="dans $(html_esc "$opened")"; else where="sur <code>chrome://extensions</code> ou <code>arc://extensions</code>"; fi
    boxes="$boxes<section class=\"box next\"><h2>Étape suivante, $where</h2><ol>
<li>Activez <b>Mode développeur</b>, en haut à droite.</li>
<li>Cliquez <b>Charger l’extension non empaquetée</b>.</li>
<li><kbd>⌘</kbd><kbd>⇧</kbd><kbd>G</kbd> puis <kbd>⌘</kbd><kbd>V</kbd> (chemin déjà copié) et <kbd>↩</kbd>.</li>
<li>Choisissez le dossier d’une extension, puis <b>Sélectionner</b>. Recommencez pour chacune.</li>
</ol><p>Chrome et Arc ? Faites-le dans les deux.</p></section>"
  fi
  if [ "$n_up" -gt 0 ]; then
    boxes="$boxes<section class=\"box ok\"><h2>Rien d’autre à faire</h2><p>Rechargez simplement vos onglets MPG ouverts.</p></section>"
  fi
  if [ -n "${RENAMED_HTML:-}" ]; then
    boxes="$boxes<section class=\"box warn\"><h2>Extensions renommées</h2><ul>$RENAMED_HTML</ul><p>Dans la page Extensions, supprimez celles marquées « À supprimer », puis chargez les nouveaux dossiers. Leurs réglages repartent de zéro.</p></section>"
  fi
  if [ "$n_err" -gt 0 ]; then
    boxes="$boxes<section class=\"box err\"><h2>En cas de problème</h2><p>Vérifiez la connexion internet et relancez le raccourci. Si ça persiste, prévenez Frank.</p></section>"
  fi

  cat <<HTML
<!doctype html>
<html lang="fr" class="$cls"><head><meta charset="utf-8"><title>Extensions MPG</title>
<style>
:root{
  --bg:#f3f4f8;--card:#fff;--ink:#151a2b;--muted:#5f6680;--line:#e3e6ef;
  --ok:#14a35a;--ok-soft:rgba(20,163,90,.09);--new:#2f6fed;--new-soft:rgba(47,111,237,.09);
  --err:#dc3a3a;--err-soft:rgba(220,58,58,.09);--warn:#d98a06;
  --rainbow:linear-gradient(90deg,#ff4d6d,#ff9f1c,#ffd60a,#2ec27e,#2fa8ff,#7a5cff,#ff4dc4,#ff4d6d);
  color-scheme:light}
@media (prefers-color-scheme:dark){:root{
  --bg:#17191f;--card:#21242d;--ink:#eef0f6;--muted:#9aa1b6;--line:#30343f;
  --ok:#3ddc84;--ok-soft:rgba(61,220,132,.10);--new:#6f9dff;--new-soft:rgba(111,157,255,.11);
  --err:#ff6b6b;--err-soft:rgba(255,107,107,.11);--warn:#fbbf24;color-scheme:dark}}
*{box-sizing:border-box}
html{background:var(--bg)}
body{margin:0;padding:14px 16px 13px;background:var(--bg);color:var(--ink);font:13px/1.45 -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;-webkit-font-smoothing:antialiased;-webkit-user-select:none;cursor:default;overflow:hidden}
svg{width:100%;height:100%;fill:none;stroke:currentColor;stroke-width:2.2;stroke-linecap:round;stroke-linejoin:round}

/* ---- Bandeau d'état ---- */
.hero{position:relative;display:flex;align-items:center;gap:13px;padding:14px 15px;border-radius:14px;color:#fff;overflow:hidden;margin-bottom:11px}
.hero .big{width:42px;height:42px;flex-shrink:0;border-radius:50%;padding:9px;background:rgba(255,255,255,.22);box-shadow:inset 0 0 0 1.5px rgba(255,255,255,.45)}
.hero .big svg{stroke-width:2.6}
.hero h1{font:800 16.5px/1.2 -apple-system,"SF Pro Display",sans-serif;margin:0;letter-spacing:-.01em;text-shadow:0 1px 2px rgba(0,0,0,.18)}
.hero p{margin:2px 0 0;font-size:12px;opacity:.92}
.hero .when{position:absolute;top:9px;right:12px;font-size:10.5px;font-weight:600;opacity:.75;font-variant-numeric:tabular-nums}
.s-ok .hero{background:linear-gradient(135deg,#0fa968,#2ccf86 55%,#7ee0a6)}
.s-new .hero{background:linear-gradient(135deg,#2f5bea,#5b7cff 55%,#8f6bff)}
.s-err .hero{background:linear-gradient(135deg,#d93a3a,#ff6b5b)}
.s-up .hero{background:var(--rainbow);background-size:300% 100%;animation:slide 7s linear infinite}
.s-up .hero::after{content:"";position:absolute;inset:0;background:linear-gradient(105deg,transparent 30%,rgba(255,255,255,.35) 50%,transparent 70%);background-size:250% 100%;animation:shine 3.2s ease-in-out infinite}
.s-ok .hero .big{animation:pop .6s cubic-bezier(.2,1.6,.4,1) both}
.s-up .hero .big{animation:spin 3s ease-in-out infinite}

/* ---- Lignes ---- */
ul.list{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:5px}
ul.list li{position:relative;display:flex;align-items:center;gap:10px;padding:7px 10px 7px 8px;border-radius:10px;background:var(--card);border:1px solid var(--line);animation:rise .45s ease-out both}
ul.list li:nth-child(2){animation-delay:.05s} ul.list li:nth-child(3){animation-delay:.1s}
ul.list li:nth-child(4){animation-delay:.15s} ul.list li:nth-child(5){animation-delay:.2s} ul.list li:nth-child(6){animation-delay:.25s}
.ic{width:24px;height:24px;flex-shrink:0;border-radius:50%;padding:5px;color:#fff}
.t{flex:1;min-width:0;display:flex;align-items:baseline;gap:8px}
.t b{font-weight:650;white-space:nowrap}
.t small{color:var(--muted);font-size:11.5px;font-variant-numeric:tabular-nums;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.t small s{opacity:.65} .t small i{font-style:normal;margin:0 4px;opacity:.7}
.tag{font-size:10.5px;font-weight:750;letter-spacing:.02em;padding:2px 8px;border-radius:999px;white-space:nowrap}

li.same{background:linear-gradient(var(--ok-soft),var(--ok-soft)),var(--card);border-color:transparent}
li.same .ic{background:var(--ok)} li.same .tag{color:var(--ok);background:var(--ok-soft)}
li.new{background:linear-gradient(var(--new-soft),var(--new-soft)),var(--card);border-color:transparent}
li.new .ic{background:var(--new)} li.new .tag{color:var(--new);background:var(--new-soft)}
li.err{background:linear-gradient(var(--err-soft),var(--err-soft)),var(--card);border-color:transparent}
li.err .ic{background:var(--err)} li.err .tag{color:var(--err);background:var(--err-soft)}
li.err .t{flex-direction:column;gap:0} li.err .t small{white-space:normal}

/* Mise à jour : bordure, icône, version et badge arc-en-ciel */
li.up{border:2px solid transparent;padding:6px 9px 6px 7px;
  background:linear-gradient(var(--card),var(--card)) padding-box,var(--rainbow) border-box;
  background-size:100% 100%,300% 100%;animation:rise .45s ease-out both,border 4s linear infinite}
li.up .ic{background:var(--rainbow);background-size:300% 100%;animation:slide 4s linear infinite}
li.up .t small em{font-style:normal;font-weight:800;background:var(--rainbow);background-size:300% 100%;-webkit-background-clip:text;background-clip:text;color:transparent;animation:slide 4s linear infinite}
li.up .tag{color:#fff;background:var(--rainbow);background-size:300% 100%;animation:slide 4s linear infinite;box-shadow:0 1px 6px rgba(122,92,255,.35)}

/* ---- Encadrés ---- */
.box{margin-top:9px;padding:9px 12px;border-radius:11px;background:var(--card);border:1px solid var(--line);position:relative;overflow:hidden}
.box::before{content:"";position:absolute;left:0;top:0;bottom:0;width:4px;background:var(--new)}
.box.ok::before{background:var(--rainbow);background-size:100% 300%}
.box.warn::before{background:var(--warn)} .box.err::before{background:var(--err)}
.box h2{font-size:12.5px;margin:0 0 3px}
.box p{margin:3px 0 0;color:var(--muted);font-size:12px}
.box ol,.box ul{margin:2px 0 0;padding-left:18px;font-size:12px}
.box li{margin:1px 0}
kbd{font:650 10.5px -apple-system,sans-serif;padding:0 4px;margin:0 1px;border:1px solid var(--line);border-bottom-width:2px;border-radius:4px;background:var(--bg)}
code{font:11px ui-monospace,Menlo,monospace;background:var(--bg);padding:0 4px;border-radius:3px}

footer{margin-top:10px;display:flex;align-items:center;justify-content:space-between;gap:10px;color:var(--muted);font-size:11px}
#close{display:none;font:700 12px -apple-system,sans-serif;padding:5px 16px;border-radius:8px;border:0;color:#fff;cursor:pointer;background:var(--ok)}
.s-new #close{background:var(--new)} .s-err #close{background:var(--err)}
.s-up #close{background:var(--rainbow);background-size:300% 100%;animation:slide 4s linear infinite}
.native #close{display:inline-block}

/* ---- Confettis (mise à jour) ---- */
.cf{position:fixed;top:-12px;width:7px;height:11px;border-radius:2px;pointer-events:none;z-index:9;animation:fall var(--d,2.4s) cubic-bezier(.25,.6,.4,1) forwards}

@keyframes slide{to{background-position:300% 0}}
@keyframes border{to{background-position:0 0,300% 0}}
@keyframes shine{0%{background-position:150% 0}60%,100%{background-position:-100% 0}}
@keyframes rise{from{opacity:0;transform:translateY(5px)}}
@keyframes pop{from{transform:scale(.4);opacity:0}}
@keyframes spin{0%,70%{transform:rotate(0)}85%{transform:rotate(18deg) scale(1.08)}100%{transform:rotate(0)}}
@keyframes fall{to{transform:translate(var(--x,0),105vh) rotate(var(--r,540deg));opacity:.2}}
@media (prefers-reduced-motion:reduce){*{animation:none!important}.cf{display:none}}
</style></head>
<body class="s-$state">
<header class="hero"><div class="big">$icon</div><div><h1>$title</h1><p>$sub</p></div><span class="when">$(date '+%d/%m · %H:%M')</span></header>
<ul class="list">$ROWS</ul>
$boxes
<footer><span>Dossier <code>~/Extensions MPG</code>, à ne pas déplacer</span><button id="close" type="button">Fermer</button></footer>
<script>
(function () {
  // Confettis quand une extension vient d'être mise à jour
  if (document.body.className === 's-up' && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
    var colors = ['#ff4d6d', '#ff9f1c', '#ffd60a', '#2ec27e', '#2fa8ff', '#7a5cff', '#ff4dc4'];
    for (var i = 0; i < 46; i++) {
      var c = document.createElement('i');
      c.className = 'cf';
      c.style.left = (Math.random() * 100) + '%';
      c.style.background = colors[i % colors.length];
      c.style.animationDelay = (Math.random() * 0.6) + 's';
      c.style.setProperty('--d', (1.8 + Math.random() * 1.4) + 's');
      c.style.setProperty('--x', ((Math.random() - 0.5) * 120) + 'px');
      c.style.setProperty('--r', ((Math.random() - 0.5) * 1440) + 'deg');
      if (i % 3 === 0) c.style.borderRadius = '50%';
      document.body.appendChild(c);
    }
    setTimeout(function () { document.querySelectorAll('.cf').forEach(function (n) { n.remove(); }); }, 4200);
  }

  if (document.documentElement.className !== 'native') return;   // ouvert dans un navigateur
  // La fenêtre native lit document.title : « mpg:h:<hauteur> » pour s'ajuster, « mpg:close » pour se fermer.
  var size = function () { document.title = 'mpg:h:' + Math.ceil(document.body.getBoundingClientRect().height); };
  var close = function () { document.title = 'mpg:close'; };
  document.getElementById('close').onclick = close;
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape' || e.key === 'Enter') close(); });
  if (document.readyState === 'complete') size(); else addEventListener('load', size);
})();
</script>
</body></html>
HTML
}

# Petite fenêtre native (JXA : NSWindow + WKWebView), 460 px de large, hauteur ajustée au contenu
# (la page l'écrit dans son titre, lu en boucle : pas de WKScriptMessageHandler, protocole absent en JXA), fermée par Échap / Entrée / ⌘W / bouton « Fermer » / croix.
# Bloque jusqu'à la fermeture (10 min max). Code de sortie ≠ 0 si la fenêtre n'a pas pu s'ouvrir.
show_window() { # <fichier.html> <hauteur estimée> <journal>
  osascript -l JavaScript - "$1" "$2" >/dev/null 2>"$3" <<'JXA'
ObjC.import('Cocoa');
ObjC.import('WebKit');
var win = null, W = 460;
function run(argv) {
  var app = $.NSApplication.sharedApplication;
  app.setActivationPolicy(1);                                   // Accessory : pas d'icône dans le Dock
  app.finishLaunching;
  var vis = $.NSScreen.mainScreen.visibleFrame;
  var maxH = vis.size.height - 80;
  var H = Math.min(parseInt(argv[1], 10) || 420, maxH);

  var cfg = $.WKWebViewConfiguration.alloc.init;
  var rect = $.NSMakeRect(0, 0, W, H);
  var web = $.WKWebView.alloc.initWithFrameConfiguration(rect, cfg);
  try { web.setValueForKey(false, 'drawsBackground'); } catch (e) {}
  var url = $.NSURL.fileURLWithPath(argv[0]);
  web.loadFileURLAllowingReadAccessToURL(url, url.URLByDeletingLastPathComponent);

  win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(rect, 1 | 2, 2, false); // titrée + fermable
  win.title = 'Extensions MPG';
  win.releasedWhenClosed = false;
  win.contentView = web;
  win.level = 3;                                                // au-dessus des autres fenêtres
  win.center;
  win.makeKeyAndOrderFront(null);
  app.activateIgnoringOtherApps(true);
  if (!win.isVisible) throw new Error('fenêtre non affichée');

  var mask = (typeof $.NSEventMaskAny === 'number') ? $.NSEventMaskAny : 0xffffffff;
  var end = Date.now() + 10 * 60 * 1000, lastTitle = '';
  while (win.isVisible && Date.now() < end) {
    var ev = app.nextEventMatchingMaskUntilDateInModeDequeue(mask, $.NSDate.dateWithTimeIntervalSinceNow(0.25), $.NSDefaultRunLoopMode, true);
    // Messages de la page via son titre (cf. build_html)
    var t = ObjC.unwrap(web.title) || '';
    if (t === 'mpg:close') { win.close; break; }
    if (t.indexOf('mpg:h:') === 0 && t !== lastTitle) {
      var h = Math.min(Math.max(parseInt(t.slice(6), 10) || H, 160), maxH);
      win.setContentSize($.NSMakeSize(W, h));
      win.center;
    }
    lastTitle = t;
    if (ev.isNil()) continue;
    if (ev.type === 10) {                                       // touche : Échap, ⌘W
      var k = ev.keyCode, cmd = (ev.modifierFlags & (1 << 20)) !== 0;
      if (k === 53 || (cmd && k === 13)) { win.close; continue; }
    }
    app.sendEvent(ev);
  }
  if (win.isVisible) win.close;
}
JXA
}

# Affiche le résumé : fenêtre native, à défaut navigateur par défaut.
show_report() {
  local dir="$HOME/Library/Caches/Extensions MPG" f h
  f="$dir/Extensions MPG.html"
  mkdir -p "$dir" 2>/dev/null && build_html > "$f" 2>/dev/null && build_html native > "$dir/fenetre.html" 2>/dev/null || return 1
  # Hauteur estimée (corrigée ensuite par la page elle-même)
  h=$((92 + (n_new + n_up + n_same) * 33 + n_err * 46))
  [ "$n_new" -gt 0 ] && h=$((h + 150))
  [ "$n_up" -gt 0 ] && h=$((h + 72))
  [ -n "${RENAMED_HTML:-}" ] && h=$((h + 100))
  [ "$n_err" -gt 0 ] && h=$((h + 64))
  local code=0
  show_window "$dir/fenetre.html" "$h" "$dir/fenetre.log" || code=$?
  [ "$code" -eq 0 ] && return 0
  if [ -n "$DEBUG" ]; then
    printf 'Fenêtre de résumé impossible (code %s) :\n' "$code" >&2
    cat "$dir/fenetre.log" >&2
  fi
  open "$f" 2>/dev/null
}

if [ -n "$REPORT_ONLY" ]; then
  build_html > "$REPORT_ONLY"
  print_text
elif [ -z "$NO_OPEN" ] && show_report; then
  :   # résumé déjà affiché (fenêtre ou navigateur) : rien sur stdout, sinon le raccourci ouvre une 2e fenêtre « stdout »
else
  print_text
fi
exit 0
