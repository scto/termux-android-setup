#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
#  setup-termux-android.sh
#  Android-Entwicklungsumgebung für Termux (aarch64 und 32-bit-ARM)
#
#   1. Termux-Pakete (Java 17, Git, Git-LFS, Gradle, Kotlin, build-essential, pip …)
#   2. Git einrichten: Name, E-Mail, GitHub-Token (→ Credential Store)
#   3. Android-SDK  (scto/codeforge-tools, Tags android-sdk-<ver>)  – Versionsmenü, Default 37.0.0
#      + cmdline-tools/sdkmanager (nur mit --cmdline-tools, aus dem Mirror – nie von Google),
#        damit Build-Tools-Java-Teile + Platform (android.jar) via sdkmanager,
#        native Binaries (aapt2, aidl, zipalign …) werden durch ARM-Builds (aarch64 bzw. armv7a) ersetzt
#   4. Android-NDK  (scto/codeforge-tools, Tags android-ndk-<name>)  – Versionsmenü, Default r29d
#      CMake        (scto/codeforge-tools, Tags cmake-<ver>)         – Versionsmenü, Default 3.22.1
#   5. Antigravity CLI "agy" (wallentx/antigravity-cli-termux)
#   6. Termuxify (scto/Termuxify)
#   7. ~/.bashrc: JAVA_HOME, GRADLE_HOME, ANDROID_HOME, NDK, PATH, Aliases
#
#  Nutzung:
#    curl -fsSL https://raw.githubusercontent.com/scto/termux-android-setup/main/setup-termux-android.sh | bash
#    oder:  bash setup-termux-android.sh [Optionen]
#
#  Optionen:
#    --sdk VER          SDK-Version ohne Menü (z.B. 37.0.0)
#    --ndk VER          NDK-Version ohne Menü (z.B. r29d, r30b)
#    --cmake VER        CMake-Version ohne Menü (z.B. 3.22.1)
#    --platform N       Android-Platform API-Level ohne Menü (z.B. 36)
#    --cmdline-tools    cmdline-tools (sdkmanager) installieren aus dem Release cmdline-tools-19.0 von
#                       scto/codeforge-tools (kein Google-Download); nicht erreichbar → Fallback: temporär aus dem
#                       Archiv android-sdk-37.0.0 entpacken. Ohne diese Option wird ein vorhandener sdkmanager
#                       nur weiterverwendet.
#    -y | --yes         Keine Fragen, überall Standardwerte nehmen
#    --menu             Startmenü: Komponenten an-/abwählen (braucht eine Konsole)
#    --skip-pkg         Paketinstallation überspringen
#    --skip-sdk         SDK überspringen
#    --skip-ndk         NDK überspringen
#    --skip-cmake       CMake aus dem Mirror überspringen (Termux-CMake wird verlinkt)
#    --skip-agy         Antigravity CLI überspringen
#    --skip-termuxify   Termuxify-Abfrage überspringen
#    --skip-git         Git-Einrichtung (Name/E-Mail/Token) überspringen
#    --skip-bashrc      .bashrc nicht anfassen
#    --no-platform      Keine android.jar-Platform installieren
#    --force            SDK/NDK neu herunterladen, auch wenn vorhanden
#    -h | --help        Hilfe
#
#  ENV: GIT_NAME, GIT_EMAIL, GIT_TOKEN (Git ohne Rückfragen), GITHUB_TOKEN,
#       ANDROID_HOME, ASSET_VARIANT, TOOLS_REPO (Standard: scto/codeforge-tools),
#       INCLUDE_PRERELEASE=1 (beta/rc-Releases zulassen), CMDLINE_REV (cmdline-tools-Release, Standard 19.0, "latest" = neuestes),
#       CMDLINE_SDK_VER (SDK-Archiv für den Fallback, Standard 37.0.0)
#  Re-Run ist sicher (idempotent): .bashrc-Block wird ersetzt, nicht dupliziert.
# =============================================================================
set -Eeuo pipefail

# ── Konfiguration (per ENV überschreibbar) ───────────────────────────────────
# Alle Toolchains kommen aus dem eigenen Mirror (scto/codeforge-tools, Releases):
#   android-sdk-<ver> · android-ndk-<name> · cmake-<ver>
TOOLS_REPO="${TOOLS_REPO:-scto/codeforge-tools}"
SDK_PREFIX="${SDK_PREFIX:-android-sdk-}"
NDK_PREFIX="${NDK_PREFIX:-android-ndk-}"
CMAKE_PREFIX="${CMAKE_PREFIX:-cmake-}"
INCLUDE_PRERELEASE="${INCLUDE_PRERELEASE:-0}"
# Termux = Android/Bionic. Variante nach Gerätearchitektur (uname -m):
#   aarch64        → *-aarch64-linux-android
#   armv7l/armv8l  → *-armv7a-linux-androideabi   (32-bit-Userland, auch auf 64-bit-Hardware)
case "$(uname -m)" in
  aarch64|arm64)       CF_ARCH=aarch64 ;;
  armv7l|armv8l|arm*)  CF_ARCH=arm ;;
  *)                   CF_ARCH="" ;;
esac
if [[ "$CF_ARCH" == arm ]]; then ASSET_VARIANT="${ASSET_VARIANT:-armv7a-linux-androideabi}"
else ASSET_VARIANT="${ASSET_VARIANT:-aarch64-linux-android}"; fi
DEFAULT_SDK="${DEFAULT_SDK:-37.0.0}"
DEFAULT_NDK="${DEFAULT_NDK:-r29d}"
DEFAULT_CMAKE="${DEFAULT_CMAKE:-3.22.1}"
AGY_INSTALLER="${AGY_INSTALLER:-https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh}"
# cmdline-tools (reines Java → läuft auf jeder Architektur) kommen aus dem Mirror, nicht von Google:
#   https://github.com/scto/codeforge-tools/releases/tag/cmdline-tools-19.0  (Asset cmdline-tools-19.0.tar.xz)
#   Fehlt das Release, wird cmdline-tools/ temporär aus dem Archiv android-sdk-$CMDLINE_SDK_VER entpackt.
CMDLINE_PREFIX="${CMDLINE_PREFIX:-cmdline-tools-}"
CMDLINE_REV="${CMDLINE_REV:-19.0}"
# Fest hinterlegte SHA-256 für cmdline-tools-19.0.tar.xz (bei anderer Revision per CMDLINE_SHA256 setzen, sonst .sha256 des Releases)
if [[ "$CMDLINE_REV" == "19.0" ]]; then CMDLINE_SHA256="${CMDLINE_SHA256:-f9ab9233b8ced6f74fd682a8a3c68a52031bc761bc06425e8dc502adb93fca9e}"
else CMDLINE_SHA256="${CMDLINE_SHA256:-}"; fi
CMDLINE_SDK_VER="${CMDLINE_SDK_VER:-37.0.0}"

ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
DL_DIR="${DL_DIR:-$HOME/.cache/termux-android-setup}"

SDK_VER="" NDK_VER="" CMAKE_SEL="" CMAKE_PICK="" PLATFORM_API=""
GIT_NAME="${GIT_NAME:-}" GIT_EMAIL="${GIT_EMAIL:-}" GIT_TOKEN="${GIT_TOKEN:-}"
MENU=0 ASSUME_YES=0 SKIP_GIT=0 SKIP_PKG=0 SKIP_SDK=0 SKIP_NDK=0 SKIP_CMAKE=0 CMDLINE_TOOLS=0 SKIP_AGY=0 SKIP_TERMUXIFY=0 SKIP_BASHRC=0 NO_PLATFORM=0 FORCE=0

# ── Ausgabe ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  C_B="\033[1m" C_G="\033[32m" C_Y="\033[33m" C_R="\033[31m" C_C="\033[36m" C_D="\033[2m" C_0="\033[0m"
else
  C_B="" C_G="" C_Y="" C_R="" C_C="" C_D="" C_0=""
fi
step() { printf '\n%b==> %s%b\n' "$C_B$C_C" "$*" "$C_0"; }
ok()   { printf '%b[OK]%b %s\n'   "$C_G" "$C_0" "$*"; }
warn() { printf '%b[!!]%b %s\n'   "$C_Y" "$C_0" "$*" >&2; }
die()  { printf '%b[ERR]%b %s\n'  "$C_R" "$C_0" "$*" >&2; exit 1; }
trap 'die "Abbruch in Zeile $LINENO: $BASH_COMMAND"' ERR

usage() {
  local self="${BASH_SOURCE[0]}"
  if [[ -f "$self" ]]; then sed -n '2,49p' "$self" | sed 's/^# \{0,1\}//'; else echo "Siehe Kopfkommentar im Script."; fi
  exit 0
}

# ── Argumente ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sdk)            SDK_VER="${2:?Version fehlt}"; shift ;;
    --ndk)            NDK_VER="${2:?Version fehlt}"; shift ;;
    --cmake)          CMAKE_SEL="${2:?Version fehlt}"; shift ;;
    --platform)       PLATFORM_API="${2:?API-Level fehlt}"; shift ;;
    --cmdline-tools)  CMDLINE_TOOLS=1 ;;
    -y|--yes)         ASSUME_YES=1 ;;
    --menu)           MENU=1 ;;
    --skip-pkg)       SKIP_PKG=1 ;;
    --skip-sdk)       SKIP_SDK=1 ;;
    --skip-ndk)       SKIP_NDK=1 ;;
    --skip-cmake)     SKIP_CMAKE=1 ;;
    --skip-agy)       SKIP_AGY=1 ;;
    --skip-termuxify) SKIP_TERMUXIFY=1 ;;
    --skip-bashrc)    SKIP_BASHRC=1 ;;
    --skip-git)       SKIP_GIT=1 ;;
    --no-platform)    NO_PLATFORM=1 ;;
    --force)          FORCE=1 ;;
    -h|--help)        usage ;;
    *) die "Unbekannte Option: $1 (siehe --help)" ;;
  esac
  shift
done

# ── Vorabprüfungen ───────────────────────────────────────────────────────────
[[ -n "${TERMUX_VERSION:-}" && -n "${PREFIX:-}" ]] || die "Dieses Script läuft nur in nativem Termux (nicht in proot)."
[[ -n "$CF_ARCH" ]] || die "Nur aarch64 und 32-bit-ARM werden unterstützt (gefunden: $(uname -m))."
# agy (Antigravity CLI) braucht glibc/aarch64 → auf 32-bit-ARM nicht verfügbar
if [[ "$CF_ARCH" == arm && $SKIP_AGY -eq 0 ]]; then
  warn "32-bit-ARM erkannt (Variante $ASSET_VARIANT): Antigravity CLI (agy) wird übersprungen."
  SKIP_AGY=1
fi
mkdir -p "$DL_DIR" "$ANDROID_HOME"

# Interaktiv? Auch bei "curl | bash" über /dev/tty fragen.
INTERACTIVE=0
if [[ $ASSUME_YES -eq 0 ]] && (: </dev/tty) 2>/dev/null; then exec 3</dev/tty; INTERACTIVE=1; fi
if [[ $INTERACTIVE -eq 0 && $ASSUME_YES -eq 0 ]]; then
  warn "Keine Konsole (/dev/tty) erkannt – es gibt keine Menüs und Fragen, Standardwerte werden verwendet. In der Termux-App direkt starten."
fi

# =============================================================================
# Menü-Helfer
# =============================================================================
# menu <Titel> <Default-Index> <Einträge…>  →  gewählter Index (0-basiert) auf stdout
menu() {
  local title="$1" def="$2"; shift 2
  local items=("$@") i ans
  if [[ $INTERACTIVE -eq 0 ]]; then echo "$def"; return; fi
  {
    printf '\n%b%s%b\n' "$C_B" "$title" "$C_0"
    for i in "${!items[@]}"; do
      if [[ $i -eq $def ]]; then
        printf '  %b%2d) %s  ← Standard%b\n' "$C_G" "$((i+1))" "${items[$i]}" "$C_0"
      else
        printf '  %2d) %s\n' "$((i+1))" "${items[$i]}"
      fi
    done
  } >&2
  while true; do
    printf '%bAuswahl [Enter = %d]: %b' "$C_C" "$((def+1))" "$C_0" >&2
    IFS= read -r ans <&3 || ans=""
    [[ -z "$ans" ]] && { echo "$def"; return; }
    if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= ${#items[@]} )); then
      echo "$((ans-1))"; return
    fi
    printf '%bUngültig.%b\n' "$C_R" "$C_0" >&2
  done
}

# ask <Frage> <Default> → Antwort auf stdout (nicht-interaktiv: Default)
ask() {
  local q="$1" def="${2:-}" ans
  if [[ $INTERACTIVE -eq 0 ]]; then echo "$def"; return; fi
  printf '%b%s%b%s: ' "$C_C" "$q" "$C_0" "${def:+ [$def]}" >&2
  IFS= read -r ans <&3 || ans=""
  echo "${ans:-$def}"
}

# ask_secret <Frage> → Eingabe ohne Echo (für Tokens)
ask_secret() {
  local q="$1" ans
  [[ $INTERACTIVE -eq 0 ]] && { echo ""; return; }
  printf '%b%s%b: ' "$C_C" "$q" "$C_0" >&2
  IFS= read -rs ans <&3 || ans=""
  printf '\n' >&2
  echo "$ans"
}

# component_menu: Komponenten an-/abwählen (setzt die SKIP_*-Variablen). Nur interaktiv.
#   Eingabe: Nummern (auch mehrere, durch Leerzeichen/Komma) schalten um · a = alle · n = keine · Enter = weiter · q = Abbruch
component_menu() {
  if [[ $INTERACTIVE -eq 0 ]]; then warn "--menu braucht eine Konsole – ignoriert."; return 0; fi
  # Name | Variable | on-Wert (Variable == on-Wert ⇒ ausgewählt)
  local -a labels=(
    "Termux-Pakete (Java, Gradle, Kotlin, Git, Clang …)"
    "Git einrichten (Name, E-Mail, Token)"
    "Android-SDK (build-tools, platform-tools)"
    "Android-Platform (android.jar)"
    "Android-NDK"
    "CMake aus dem Mirror"
    "cmdline-tools (sdkmanager)"
    "Antigravity CLI (agy)"
    "Termuxify"
    "~/.bashrc-Block (Variablen, Aliase)"
  )
  local -a vars=(SKIP_PKG SKIP_GIT SKIP_SDK NO_PLATFORM SKIP_NDK SKIP_CMAKE CMDLINE_TOOLS SKIP_AGY SKIP_TERMUXIFY SKIP_BASHRC)
  local -a on=(0 0 0 0 0 0 1 0 0 0)
  local arm_note=""
  [[ $CF_ARCH == arm ]] && arm_note="  (auf 32-bit-ARM nicht verfügbar)"
  local i ans tok v mark
  while true; do
    printf '\n%bKomponenten wählen%b\n' "$C_B" "$C_0" >&2
    for i in "${!labels[@]}"; do
      local -n ref="${vars[$i]}"
      if [[ "$ref" == "${on[$i]}" ]]; then mark="[x]"; else mark="[ ]"; fi
      unset -n ref
      printf '  %2d) %s %s%s\n' "$((i+1))" "$mark" "${labels[$i]}" "$([[ ${vars[$i]} == SKIP_AGY ]] && echo "$arm_note")" >&2
    done
    printf '%bNummern umschalten, a = alle, n = keine, Enter = weiter, q = Abbruch: %b' "$C_C" "$C_0" >&2
    IFS= read -r ans <&3 || ans=""
    [[ -z "$ans" ]] && break
    case "$ans" in
      q|Q) die "Abbruch durch Benutzer." ;;
      a|A) for i in "${!vars[@]}"; do v="${vars[$i]}"; printf -v "$v" '%s' "${on[$i]}"; done ;;
      n|N) for i in "${!vars[@]}"; do v="${vars[$i]}"; printf -v "$v" '%s' "$((1-${on[$i]}))"; done ;;
      *)
        for tok in ${ans//,/ }; do
          if [[ "$tok" =~ ^[0-9]+$ ]] && (( tok >= 1 && tok <= ${#vars[@]} )); then
            i=$((tok-1)); v="${vars[$i]}"
            if [[ "${!v}" == "${on[$i]}" ]]; then printf -v "$v" '%s' "$((1-${on[$i]}))"; else printf -v "$v" '%s' "${on[$i]}"; fi
          else
            printf '%bUngültig: %s%b\n' "$C_R" "$tok" "$C_0" >&2
          fi
        done ;;
    esac
  done
  # agy läuft nur auf aarch64
  if [[ $CF_ARCH == arm && $SKIP_AGY -eq 0 ]]; then warn "agy gibt es nicht für 32-bit-ARM – wird übersprungen."; SKIP_AGY=1; fi
  return 0
}

# Versionen vergleichbar machen: "r29d" ≈ "r29", "r30b" ≈ "r30-beta2"
norm_ver() { sed -E 's/-?beta([0-9]+)/b/; s/^(r[0-9]+)[a-z]$/\1/' <<<"$1"; }

# =============================================================================
# GitHub-Releases
# =============================================================================
gh_api() {
  curl -fsSL -H 'Accept: application/vnd.github+json' \
       ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} "$1" \
    || die "GitHub-API nicht erreichbar ($1). Rate-Limit? -> export GITHUB_TOKEN=..."
}

# Alle Releases des Mirrors einmal laden (bis zu 5 Seiten à 100) und zwischenspeichern.
RELEASES_JSON=""
fetch_releases() {
  [[ -n "$RELEASES_JSON" && -s "$RELEASES_JSON" ]] && return 0
  RELEASES_JSON="$DL_DIR/releases-${TOOLS_REPO//\//_}.json"
  local page=1 out="$DL_DIR/.rel-page.json" acc="$DL_DIR/.rel-acc.json"
  echo '[]' > "$acc"
  while (( page <= 5 )); do
    gh_api "https://api.github.com/repos/$TOOLS_REPO/releases?per_page=100&page=$page" > "$out"
    [[ "$(jq 'length' "$out")" -gt 0 ]] || break
    jq -s 'add' "$acc" "$out" > "$acc.new" && mv "$acc.new" "$acc"
    (( page++ ))
  done
  mv "$acc" "$RELEASES_JSON"; rm -f "$out"
  [[ "$(jq 'length' "$RELEASES_JSON")" -gt 0 ]] \
    || die "Keine Releases in $TOOLS_REPO. Repo öffentlich? Mirror-Workflow schon gelaufen?"
}

# releases_tsv <tag-prefix> → Zeilen: "<version>\t<asset-name>\t<url>\t<sha256>" (neueste Version zuerst)
# version = Tag ohne Präfix. Nur Releases mit passendem Termux-Asset (ASSET_VARIANT).
# beta/rc-Releases werden ausgeblendet (INCLUDE_PRERELEASE=1 zeigt sie).
releases_tsv() {
  fetch_releases
  jq -r --arg p "$1" --arg v "$ASSET_VARIANT" --arg pre "$INCLUDE_PRERELEASE" '
    .[] | select((.draft | not) and (.tag_name | startswith($p))) | . as $r
    | select($pre == "1" or ((($r.tag_name + " " + ($r.name // "")) | ascii_downcase | test("(^|[^a-z])(beta|rc)([^a-z]|$)")) | not))
    | ($r.assets[] | select(.name | test("-" + $v + "\\.(tar\\.xz|tar\\.gz|zip|7z)$"))) as $a
    | [ ($r.tag_name | .[($p | length):]), $a.name, $a.browser_download_url,
        (($a.digest // "") | sub("^sha256:"; "")) ] | @tsv' "$RELEASES_JSON" | sort -t$'\t' -k1,1 -Vr
}

# choose_release <tag-prefix> <Titel> <Default> <Vorgabe> [soft]
#   → setzt REL_NAME / REL_ASSET / REL_URL / REL_SHA; "soft": Rückgabe 1 statt Abbruch, wenn nichts gefunden
choose_release() {
  local prefix="$1" title="$2" def_ver="$3" want="$4" soft="${5:-}" tsv
  tsv="$(releases_tsv "$prefix")"
  if [[ -z "$tsv" ]]; then
    [[ -n "$soft" ]] && return 1
    die "Keine Releases '${prefix}*' mit Asset *-$ASSET_VARIANT in $TOOLS_REPO gefunden (Mirror-Workflow gelaufen?)."
  fi
  local -a names assets urls shas
  while IFS=$'\t' read -r n a u h; do names+=("$n"); assets+=("$a"); urls+=("$u"); shas+=("$h"); done <<<"$tsv"

  # Index für eine Version suchen (exakt, sonst normalisiert: r29d ≈ r29)
  find_idx() {
    local v="$1" i nv; nv="$(norm_ver "$v")"
    for i in "${!names[@]}"; do [[ "${names[$i]}" == "$v" ]] && { echo "$i"; return; }; done
    for i in "${!names[@]}"; do [[ "$(norm_ver "${names[$i]}")" == "$nv" ]] && { echo "$i"; return; }; done
    echo -1
  }

  local idx
  if [[ -n "$want" ]]; then
    idx="$(find_idx "$want")"
    if [[ $idx -lt 0 ]]; then
      [[ -n "$soft" ]] && { warn "Version '$want' nicht im Mirror. Verfügbar: ${names[*]}"; return 1; }
      die "Version '$want' nicht gefunden. Verfügbar: ${names[*]}"
    fi
  else
    local d; d="$(find_idx "$def_ver")"; [[ $d -ge 0 ]] || d=0
    local -a labels; local i
    for i in "${!names[@]}"; do labels+=("$(printf '%-22s %s' "${names[$i]}" "${assets[$i]}")"); done
    idx="$(menu "$title" "$d" "${labels[@]}")"
  fi
  REL_NAME="${names[$idx]}"; REL_ASSET="${assets[$idx]}"; REL_URL="${urls[$idx]}"; REL_SHA="${shas[$idx]}"
}

# verify_sha <datei> <url> <sha-aus-api>: SHA-256 gegen GitHub-digest bzw. <asset>.sha256 des Mirrors prüfen
verify_sha() {
  local f="$1" url="$2" want="${3:-}" got
  if [[ -z "$want" ]]; then
    want="$(curl -fsSL --retry 2 "$url.sha256" 2>/dev/null | awk 'NR==1{print $1}' || true)"
  fi
  if [[ ! "$want" =~ ^[0-9a-f]{64}$ ]]; then
    warn "Keine Prüfsumme für $(basename "$f") verfügbar – Download ist nicht verifiziert."
    return 0
  fi
  got="$(sha256sum "$f" | awk '{print $1}')"
  if [[ "$got" != "$want" ]]; then
    rm -f "$f"
    die "SHA-256 stimmt nicht für $(basename "$f") (erwartet $want, erhalten $got). Datei gelöscht – Script erneut starten."
  fi
  ok "SHA-256 geprüft: $(basename "$f")"
}

download() {
  local url="$1" out="$2"
  if [[ -s "$out" && $FORCE -eq 0 ]]; then ok "Bereits heruntergeladen: $(basename "$out")"; return; fi
  echo "Lade: $url"
  curl -fL --retry 3 --progress-bar -o "$out.part" "$url"
  mv "$out.part" "$out"
}

extract() {
  local f="$1" dest="$2"
  rm -rf "$dest"; mkdir -p "$dest"
  case "$f" in
    *.zip)          unzip -q "$f" -d "$dest" ;;
    *.7z)           7z x -y -o"$dest" "$f" >/dev/null ;;
    *.tar.xz|*.txz) tar -xJf "$f" -C "$dest" ;;
    *.tar.gz|*.tgz) tar -xzf "$f" -C "$dest" ;;
    *) die "Unbekanntes Archivformat: $f" ;;
  esac
}

# Eine Ebene hinabsteigen, wenn das Archiv nur einen Ordner enthält
content_root() {
  local d="$1" entries
  entries=("$d"/*)
  if [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]]; then echo "${entries[0]}"; else echo "$d"; fi
}

# =============================================================================
# 0. Versionen abfragen (alles vorab, damit danach unbeaufsichtigt läuft)
# =============================================================================
select_versions() {
  step "Versionen wählen  (Quelle: github.com/$TOOLS_REPO)"
  fetch_releases   # einmal im Hauptprozess laden (Cache für alle drei Menüs)
  if [[ $SKIP_SDK -eq 0 ]]; then
    choose_release "$SDK_PREFIX" "Android-SDK (build-tools / platform-tools, $CF_ARCH):" "$DEFAULT_SDK" "$SDK_VER"
    SDK_VER="$REL_NAME" SDK_ASSET="$REL_ASSET" SDK_URL="$REL_URL" SDK_SHA="$REL_SHA"
    ok "SDK: $SDK_VER  ($SDK_ASSET)"
  fi
  if [[ $SKIP_NDK -eq 0 ]]; then
    choose_release "$NDK_PREFIX" "Android-NDK ($CF_ARCH):" "$DEFAULT_NDK" "$NDK_VER"
    NDK_VER="$REL_NAME" NDK_ASSET="$REL_ASSET" NDK_URL="$REL_URL" NDK_SHA="$REL_SHA"
    ok "NDK: $NDK_VER  ($NDK_ASSET)"
  fi
  if [[ $SKIP_CMAKE -eq 0 ]]; then
    if choose_release "$CMAKE_PREFIX" "CMake ($CF_ARCH):" "$DEFAULT_CMAKE" "$CMAKE_SEL" soft; then
      CMAKE_PICK="$REL_NAME" CMAKE_ASSET="$REL_ASSET" CMAKE_URL="$REL_URL" CMAKE_SHA="$REL_SHA"
      ok "CMake: $CMAKE_PICK  ($CMAKE_ASSET)"
    else
      warn "Kein CMake im Mirror – Termux-CMake wird verlinkt."
      CMAKE_PICK=""
    fi
  fi
}

# =============================================================================
# 1. Termux-Pakete
# =============================================================================
install_packages() {
  step "1/7  Termux-Pakete installieren"
  export DEBIAN_FRONTEND=noninteractive
  yes | pkg update -y || true
  pkg upgrade -y -o Dpkg::Options::="--force-confnew" || true

  local pkgs=(
    openjdk-17 gradle kotlin git git-lfs                 # Build-Kern
    build-essential clang cmake ninja make binutils      # Native / NDK
    pkg-config protobuf python-pip
    curl wget unzip zip tar xz-utils p7zip gzip bzip2    # Netz & Archive
    jq python nano vim which file tree openssh rsync     # Tools
    termux-tools termux-api ripgrep fd bat lsof procps
    ca-certificates resolv-conf proot                    # für agy
  )
  pkg install -y "${pkgs[@]}"

  if [[ $SKIP_AGY -eq 0 ]]; then
    pkg install -y glibc-repo
    pkg update -y || true
    pkg install -y glibc
  fi

  [[ -d "$HOME/storage" ]] || termux-setup-storage || true
  ok "Pakete installiert ($(java -version 2>&1 | head -n1))"
}

# =============================================================================
# 2. Git einrichten
#    Fragen werden vorab gestellt (ask_git), angewendet in setup_git.
# =============================================================================
# GitHub-Login zum Token ermitteln (prüft gleichzeitig, ob das Token gültig ist)
github_login() {
  curl -fsS -H "Authorization: Bearer $1" -H 'Accept: application/vnd.github+json' \
       https://api.github.com/user 2>/dev/null | jq -r '.login // empty' 2>/dev/null || true
}

ask_git() {
  step "Git einrichten"
  GIT_NAME="${GIT_NAME:-$(git config --global user.name 2>/dev/null || true)}"
  GIT_EMAIL="${GIT_EMAIL:-$(git config --global user.email 2>/dev/null || true)}"

  GIT_NAME="$(ask "Git user.name" "$GIT_NAME")"
  while true; do
    GIT_EMAIL="$(ask "Git user.email" "$GIT_EMAIL")"
    [[ -z "$GIT_EMAIL" || "$GIT_EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] && break
    warn "Ungültige E-Mail-Adresse."
    [[ $INTERACTIVE -eq 0 ]] && { GIT_EMAIL=""; break; }
  done

  GIT_LOGIN=""
  if [[ -z "$GIT_TOKEN" && $INTERACTIVE -eq 1 ]]; then
    printf '%bGitHub Personal Access Token (Scope: repo, workflow). Enter = überspringen.%b\n' "$C_D" "$C_0" >&2
  fi
  while true; do
    [[ -n "$GIT_TOKEN" ]] || GIT_TOKEN="$(ask_secret "GitHub-Token")"
    [[ -z "$GIT_TOKEN" ]] && break
    GIT_LOGIN="$(github_login "$GIT_TOKEN")"
    if [[ -n "$GIT_LOGIN" ]]; then ok "Token gültig – GitHub-Benutzer: $GIT_LOGIN"; break; fi
    warn "Token ungültig oder GitHub nicht erreichbar."
    if [[ $INTERACTIVE -eq 0 ]]; then GIT_TOKEN=""; break; fi
    if [[ "$(ask "Nochmal eingeben? (j/n)" "j")" =~ ^[jJyY] ]]; then GIT_TOKEN=""; else
      GIT_LOGIN="$(ask "GitHub-Benutzername (Token trotzdem speichern)" "")"
      [[ -n "$GIT_LOGIN" ]] || GIT_TOKEN=""
      break
    fi
  done
  # Gültiges Token auch für die GitHub-API in diesem Lauf nutzen (kein Rate-Limit)
  [[ -n "$GIT_TOKEN" && -z "${GITHUB_TOKEN:-}" ]] && GITHUB_TOKEN="$GIT_TOKEN"
  return 0
}

setup_git() {
  step "2/7  Git konfigurieren"
  [[ -n "$GIT_NAME"  ]] && git config --global user.name  "$GIT_NAME"
  [[ -n "$GIT_EMAIL" ]] && git config --global user.email "$GIT_EMAIL"

  git config --global init.defaultBranch >/dev/null 2>&1 || git config --global init.defaultBranch main
  git config --global pull.rebase        >/dev/null 2>&1 || git config --global pull.rebase true
  git config --global core.autocrlf      >/dev/null 2>&1 || git config --global core.autocrlf input
  git config --global core.editor        >/dev/null 2>&1 || git config --global core.editor nano
  git config --global push.autoSetupRemote true
  git config --global fetch.prune true
  git config --global color.ui auto

  # Git LFS
  if command -v git-lfs >/dev/null; then
    git lfs install --skip-repo >/dev/null && ok "Git LFS aktiviert"
  fi

  # Token im Credential Store (~/.git-credentials, nur für den Benutzer lesbar)
  if [[ -n "$GIT_TOKEN" && -n "$GIT_LOGIN" ]]; then
    git config --global credential.helper store
    git config --global credential.https://github.com.username "$GIT_LOGIN"
    touch "$HOME/.git-credentials"; chmod 600 "$HOME/.git-credentials"
    printf 'protocol=https\nhost=github.com\nusername=%s\n\n' "$GIT_LOGIN" | git credential reject 2>/dev/null || true
    printf 'protocol=https\nhost=github.com\nusername=%s\npassword=%s\n\n' "$GIT_LOGIN" "$GIT_TOKEN" | git credential approve
    ok "GitHub-Token für $GIT_LOGIN im Credential Store gespeichert (~/.git-credentials)"
  fi
  unset GIT_TOKEN

  ok "Git: ${GIT_NAME:-?} <${GIT_EMAIL:-?}>"
}

# =============================================================================
# 3. Android-SDK
#    a) cmdline-tools (Mirror, nur mit --cmdline-tools) → sdkmanager (Java)
#    b) build-tools;<ver> + platforms;android-N  (offiziell: package.xml, *.jar)
#    c) native x86-Binaries in build-tools/platform-tools durch ARM-Builds ersetzen
# =============================================================================
# Revision der installierten cmdline-tools (aus source.properties)
cmdline_rev() { sed -n 's/^Pkg\.Revision *= *//p' "$ANDROID_HOME/cmdline-tools/latest/source.properties" 2>/dev/null | head -n1 | tr -d '\r ' || true; }

# Neuestes Release-Asset cmdline-tools-<rev> im Mirror → "<rev>\t<asset>\t<url>\t<sha256>" (leer, wenn keins da ist)
find_cmdline_asset() {
  fetch_releases
  jq -r --arg p "$CMDLINE_PREFIX" '
    .[] | select((.draft | not) and (.tag_name | startswith($p))) | . as $r
    | ($r.assets[] | select(.name | test("^cmdline-tools-.*\\.(tar\\.xz|tar\\.gz|zip)$"))) as $a
    | [ ($r.tag_name | .[($p | length):]), $a.name, $a.browser_download_url,
        (($a.digest // "") | sub("^sha256:"; "")) ] | @tsv' "$RELEASES_JSON" | sort -t$'\t' -k1,1 -Vr | head -n1
}

# Verzeichnis mit bin/sdkmanager in <tmp> suchen und nach cmdline-tools/latest verschieben
cmdline_install_from_dir() {
  local tmp="$1" sm root
  sm="$(find "$tmp" -type f -path '*/bin/sdkmanager' | head -n1 || true)"
  [[ -n "$sm" ]] || return 1
  root="$(dirname "$(dirname "$sm")")"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  rm -rf "$ANDROID_HOME/cmdline-tools/latest"
  mv "$root" "$ANDROID_HOME/cmdline-tools/latest"
  chmod +x "$ANDROID_HOME"/cmdline-tools/latest/bin/* 2>/dev/null || true
  [[ -x "$SDKMANAGER" ]]
}

# Fallback: cmdline-tools/ temporär aus dem SDK-Archiv android-sdk-$CMDLINE_SDK_VER entpacken
install_cmdline_from_sdk_archive() {
  local ver="$CMDLINE_SDK_VER" row asset url sha file tmp="$DL_DIR/clt-extract"
  row="$(releases_tsv "$SDK_PREFIX" | awk -F'\t' -v v="$ver" '$1 == v { print; exit }')"
  if [[ -z "$row" ]]; then
    warn "${SDK_PREFIX}${ver} mit Asset *-$ASSET_VARIANT nicht im Mirror ($TOOLS_REPO) – cmdline-tools nicht installiert."
    return 1
  fi
  IFS=$'\t' read -r _ asset url sha <<<"$row"
  file="$DL_DIR/sdk-$ver-$asset"            # gleicher Pfad wie in install_sdk → wird dort nicht ein zweites Mal geladen
  download "$url" "$file" || { warn "Download von $asset fehlgeschlagen."; return 1; }
  verify_sha "$file" "$url" "$sha"
  echo "Entpacke cmdline-tools temporär aus $asset …"
  rm -rf "$tmp"; mkdir -p "$tmp"
  case "$file" in
    *.tar.xz|*.txz) tar -xJf "$file" -C "$tmp" --wildcards '*cmdline-tools/*' 2>/dev/null || true ;;
    *)              extract "$file" "$tmp" ;;
  esac
  if cmdline_install_from_dir "$tmp"; then
    rm -rf "$tmp"
    ok "cmdline-tools $(cmdline_rev) aus ${SDK_PREFIX}${ver} entpackt und installiert"
  else
    rm -rf "$tmp"
    warn "Kein cmdline-tools/bin/sdkmanager im Archiv $asset."
    return 1
  fi
}

# cmdline-tools installieren (nur mit --cmdline-tools):
#   1. Release cmdline-tools-$CMDLINE_REV von $TOOLS_REPO (direkter Download, SHA-256 geprüft; "latest" fragt die API)
#   2. Fallback: temporär aus dem SDK-Archiv android-sdk-$CMDLINE_SDK_VER entpacken. Kein Google-Download.
install_cmdline_tools() {
  SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
  if [[ -x "$SDKMANAGER" && $FORCE -eq 0 ]]; then ok "cmdline-tools $(cmdline_rev) bereits vorhanden"; return 0; fi
  local rev="$CMDLINE_REV" asset url sha="$CMDLINE_SHA256" file tmp="$DL_DIR/clt-extract" row
  if [[ "$rev" == latest ]]; then
    row="$(find_cmdline_asset || true)"
    if [[ -n "$row" ]]; then IFS=$'\t' read -r rev asset url sha <<<"$row"; else rev=""; fi
  else
    asset="cmdline-tools-$rev.tar.xz"
    url="https://github.com/$TOOLS_REPO/releases/download/${CMDLINE_PREFIX}${rev}/$asset"
  fi
  if [[ -n "$rev" ]]; then
    file="$DL_DIR/$asset"
    echo "cmdline-tools $rev aus Release ${CMDLINE_PREFIX}${rev} ($TOOLS_REPO)"
    if download "$url" "$file"; then
      verify_sha "$file" "$url" "$sha"
      extract "$file" "$tmp"
      if cmdline_install_from_dir "$tmp"; then
        rm -rf "$tmp"; ok "cmdline-tools $(cmdline_rev) installiert (Release ${CMDLINE_PREFIX}${rev})"; return 0
      fi
      rm -rf "$tmp"
      warn "Release-Asset $asset enthält kein bin/sdkmanager – Fallback auf das SDK-Archiv."
    else
      warn "Download von $url fehlgeschlagen – Fallback auf das SDK-Archiv."
    fi
  else
    warn "Kein Release ${CMDLINE_PREFIX}* in $TOOLS_REPO gefunden – Fallback auf das SDK-Archiv."
  fi
  install_cmdline_from_sdk_archive
}

sdkm() { "$SDKMANAGER" --sdk_root="$ANDROID_HOME" "$@"; }

accept_licenses() {
  mkdir -p "$ANDROID_HOME/licenses"
  printf '\n24333f8a63b6825ea9c5514f83c2829b004d1fee\nd56f5187479451eabf01fb78af6dfcb131a6481e\n' \
    > "$ANDROID_HOME/licenses/android-sdk-license"
  printf '\n84831b9409646a918e30573bab4c9c91346d8abd\n' \
    > "$ANDROID_HOME/licenses/android-sdk-preview-license"
  # if statt "[[ ]] && …": als letzter Befehl würde ein Fehlschlag die Funktion mit 1 beenden (set -e / ERR-Trap)
  if [[ -x "${SDKMANAGER:-}" ]]; then yes | sdkm --licenses >/dev/null 2>&1 || true; fi
  return 0
}

choose_platform() {
  [[ $NO_PLATFORM -eq 1 || -n "$PLATFORM_API" ]] && return
  local list; list="$(sdkm --list 2>/dev/null | grep -oE 'platforms;android-[0-9]+' | sed 's/.*android-//' | sort -un | tail -n 6 || true)"
  [[ -n "$list" ]] || { PLATFORM_API="36"; return; }
  local -a apis; mapfile -t apis < <(sort -rn <<<"$list")
  local -a labels; local a; for a in "${apis[@]}"; do labels+=("android-$a (API $a)"); done
  PLATFORM_API="${apis[$(menu "Android-Platform (android.jar / compileSdk):" 0 "${labels[@]}")]}"
}

# overlay_natives <quellordner> <zielordner>: ersetzt alle gleichnamigen Dateien
# im Ziel + kopiert fehlende hinzu (ELF-Binaries & .so vom ARM-Build)
overlay_natives() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  cp -a "$src"/. "$dst"/
  find "$dst" -maxdepth 2 -type f ! -name '*.jar' ! -name '*.xml' ! -name '*.properties' \
       -exec chmod +x {} + 2>/dev/null || true
}

install_sdk() {
  step "3/7  Android-SDK $SDK_VER ($CF_ARCH) → $ANDROID_HOME"
  local bt_dir="$ANDROID_HOME/build-tools/$SDK_VER"

  # a) sdkmanager: bereits installiert oder (mit --cmdline-tools) schon in main installiert
  if [[ -z "$SDKMANAGER" && -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]]; then
    SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"; accept_licenses
  fi
  if [[ -z "$SDKMANAGER" ]]; then
    warn "Kein sdkmanager – Java-Teile der build-tools und platforms/android.jar werden übersprungen (Option --cmdline-tools installiert ihn)."
  fi

  # b) Offizielle build-tools (Java-Teile, package.xml, damit AGP sie erkennt)
  if [[ -n "$SDKMANAGER" && ( ! -f "$bt_dir/source.properties" || $FORCE -eq 1 ) ]]; then
    if sdkm "build-tools;$SDK_VER"; then
      ok "Offizielle build-tools;$SDK_VER (Java-Teile) installiert"
    else
      warn "build-tools;$SDK_VER bei Google nicht verfügbar – nur die $CF_ARCH-Binaries werden genutzt."
    fi
  fi

  # Platform (android.jar)
  if [[ $NO_PLATFORM -eq 0 && -n "$SDKMANAGER" ]]; then
    choose_platform
    if [[ -d "$ANDROID_HOME/platforms/android-$PLATFORM_API" ]]; then
      ok "platforms;android-$PLATFORM_API vorhanden"
    elif sdkm "platforms;android-$PLATFORM_API"; then
      ok "platforms;android-$PLATFORM_API installiert"
    else
      warn "Platform android-$PLATFORM_API fehlgeschlagen – später: sdkmanager \"platforms;android-$PLATFORM_API\""
    fi
  fi

  # c) Custom ARM-SDK herunterladen & native Binaries einspielen
  local file="$DL_DIR/sdk-$SDK_VER-$SDK_ASSET" tmp="$DL_DIR/sdk-extract" root aapt2 adb
  download "$SDK_URL" "$file"
  verify_sha "$file" "$SDK_URL" "${SDK_SHA:-}"
  echo "Entpacke $SDK_ASSET …"
  extract "$file" "$tmp"
  root="$(content_root "$tmp")"

  aapt2="$(find "$root" -type f -name aapt2 | head -n1 || true)"
  adb="$(find "$root" -type f -name adb | head -n1 || true)"
  [[ -n "$aapt2" ]] || die "aapt2 im SDK-Archiv nicht gefunden – Layout unbekannt ($root)."

  overlay_natives "$(dirname "$aapt2")" "$bt_dir"
  ok "build-tools/$SDK_VER: $CF_ARCH-Binaries eingespielt"
  if [[ -n "$adb" ]]; then
    overlay_natives "$(dirname "$adb")" "$ANDROID_HOME/platform-tools"
    ok "platform-tools: $CF_ARCH-Binaries eingespielt"
  fi
  rm -rf "$tmp"

  # Minimal-Metadaten, falls Google die Version nicht hatte (AGP liest Pkg.Revision)
  [[ -f "$bt_dir/source.properties" ]] || printf 'Pkg.Desc = Android SDK Build-Tools %s (%s)\nPkg.Revision = %s\n' "$SDK_VER" "$CF_ARCH" "$SDK_VER" > "$bt_dir/source.properties"

  # Sanity-Check
  if "$bt_dir/aapt2" version >/dev/null 2>&1; then
    ok "aapt2: $("$bt_dir/aapt2" version 2>&1 | head -n1)"
  else
    warn "aapt2 startet nicht – Asset-Variante prüfen (ASSET_VARIANT=$ASSET_VARIANT)."
  fi
}

# Termux-CMake für AGP registrieren: $ANDROID_HOME/cmake/<ver>/bin/{cmake,ninja}
link_cmake() {
  command -v cmake >/dev/null || return 0
  local v; v="$(cmake --version | head -n1 | awk '{print $3}')"
  local d="$ANDROID_HOME/cmake/$v/bin"
  mkdir -p "$d"
  ln -sf "$(command -v cmake)" "$d/cmake"
  command -v ninja >/dev/null && ln -sf "$(command -v ninja)" "$d/ninja"
  printf 'Pkg.Revision = %s\nPkg.Path = cmake;%s\n' "$v" "$v" > "$ANDROID_HOME/cmake/$v/source.properties"
  CMAKE_VER="$v"
  ok "CMake $v für Gradle verlinkt"
}

# CMake aus dem Mirror nach $ANDROID_HOME/cmake/<ver> (AGP: externalNativeBuild.cmake.version)
install_cmake() {
  step "3b/7  CMake $CMAKE_PICK ($CF_ARCH) → $ANDROID_HOME/cmake/$CMAKE_PICK"
  local cdir="$ANDROID_HOME/cmake/$CMAKE_PICK" file tmp="$DL_DIR/cmake-extract" root cmbin
  if [[ -x "$cdir/bin/cmake" && ! -L "$cdir/bin/cmake" && $FORCE -eq 0 ]]; then
    ok "CMake $CMAKE_PICK bereits vorhanden"; CMAKE_VER="$CMAKE_PICK"; return 0
  fi
  file="$DL_DIR/$CMAKE_ASSET"
  download "$CMAKE_URL" "$file"
  verify_sha "$file" "$CMAKE_URL" "${CMAKE_SHA:-}"
  extract "$file" "$tmp"
  root="$(content_root "$tmp")"
  cmbin="$(find "$tmp" -type f -path '*/bin/cmake' | head -n1 || true)"
  [[ -n "$cmbin" ]] || { rm -rf "$tmp"; warn "bin/cmake im Archiv nicht gefunden – Termux-CMake wird verlinkt."; return 1; }
  root="$(dirname "$(dirname "$cmbin")")"
  mkdir -p "$ANDROID_HOME/cmake"; rm -rf "$cdir"
  mv "$root" "$cdir"; rm -rf "$tmp"
  chmod +x "$cdir"/bin/* 2>/dev/null || true
  if [[ ! -x "$cdir/bin/ninja" ]]; then
    command -v ninja >/dev/null || pkg install -y ninja >/dev/null 2>&1 || true
    command -v ninja >/dev/null && ln -sf "$(command -v ninja)" "$cdir/bin/ninja" || warn "ninja fehlt (pkg install ninja)"
  fi
  printf 'Pkg.Revision = %s\nPkg.Path = cmake;%s\n' "$CMAKE_PICK" "$CMAKE_PICK" > "$cdir/source.properties"
  if "$cdir/bin/cmake" --version >/dev/null 2>&1; then
    ok "CMake: $("$cdir/bin/cmake" --version | head -n1)"
  else
    warn "cmake startet nicht – Asset-Variante prüfen (ASSET_VARIANT=$ASSET_VARIANT)."
  fi
  CMAKE_VER="$CMAKE_PICK"
}

# =============================================================================
# 4. Android-NDK
# =============================================================================
install_ndk() {
  step "4/7  Android-NDK $NDK_VER ($CF_ARCH)"
  mkdir -p "$ANDROID_HOME/ndk"

  local file="$DL_DIR/$NDK_ASSET" tmp="$DL_DIR/ndk-extract" root ver
  download "$NDK_URL" "$file"
  verify_sha "$file" "$NDK_URL" "${NDK_SHA:-}"
  echo "Entpacke NDK (dauert, mehrere GB) …"
  extract "$file" "$tmp"
  root="$(content_root "$tmp")"
  [[ -f "$root/source.properties" ]] || die "source.properties im NDK nicht gefunden."

  # AGP findet NDKs über ndk/<Pkg.Revision>, z.B. ndk/29.0.14206865
  ver="$(grep -E '^Pkg.Revision' "$root/source.properties" | cut -d= -f2 | tr -d ' \r')"
  if [[ -d "$ANDROID_HOME/ndk/$ver" && $FORCE -eq 0 ]]; then
    ok "NDK $ver bereits vorhanden"
    rm -rf "$tmp"
  else
    rm -rf "$ANDROID_HOME/ndk/$ver"
    mv "$root" "$ANDROID_HOME/ndk/$ver"
    rm -rf "$tmp"
    ok "NDK $NDK_VER → ndk/$ver"
  fi
  NDK_REV="$ver"

  ln -sfn "$ANDROID_HOME/ndk/$ver" "$ANDROID_HOME/ndk-bundle"
  find "$ANDROID_HOME/ndk/$ver/toolchains" -path '*/bin/*' -type f -exec chmod +x {} + 2>/dev/null || true

  local clang; clang="$(find "$ANDROID_HOME/ndk/$ver/toolchains/llvm/prebuilt" -path '*/bin/clang' | head -n1 || true)"
  if [[ -n "$clang" ]] && "$clang" --version >/dev/null 2>&1; then
    ok "NDK-clang: $("$clang" --version | head -n1)"
  else
    warn "NDK-clang startet nicht – Asset-Variante prüfen (ASSET_VARIANT=$ASSET_VARIANT)."
  fi
}

# =============================================================================
# Gradle-Konfiguration
# =============================================================================
configure_gradle() {
  local aapt2="$ANDROID_HOME/build-tools/$SDK_VER/aapt2"
  local gp="$HOME/.gradle/gradle.properties"
  mkdir -p "$HOME/.gradle"; touch "$gp"
  sed -i '/# >>> termux-android-setup >>>/,/# <<< termux-android-setup <<</d' "$gp"
  {
    echo "# >>> termux-android-setup >>>"
    # AGP lädt sonst ein x86_64-aapt2 von Maven → Build bricht ab
    [[ -x "$aapt2" ]] && echo "android.aapt2FromMavenOverride=$aapt2"
    echo "org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8"
    echo "org.gradle.daemon=true"
    echo "org.gradle.parallel=true"
    echo "org.gradle.caching=true"
    echo "# <<< termux-android-setup <<<"
  } >> "$gp"
  ok "~/.gradle/gradle.properties aktualisiert (aapt2-Override)"
}

# =============================================================================
# 5. Antigravity CLI (agy)
# =============================================================================
install_agy() {
  step "5/7  Antigravity CLI (agy) installieren"
  if ! grep -q atomics /proc/cpuinfo && ! command -v qemu-aarch64 >/dev/null; then
    warn "CPU ohne LSE-Atomics → installiere qemu-user-aarch64"
    pkg install -y qemu-user-aarch64 || warn "qemu-user-aarch64 nicht installierbar"
  fi
  if AGY_INSTALL_SKIP_LAUNCH=1 bash <(curl -fsSL "$AGY_INSTALLER"); then
    ok "agy installiert ($(agy --version 2>/dev/null || echo 'Version unbekannt'))"
  else
    warn "agy-Installation fehlgeschlagen – später: agy-update"
  fi
}

# =============================================================================
# 6. Termuxify
# =============================================================================
install_termuxify() {
  step "6/7  Termuxify (scto/Termuxify) herunterladen & ausführen"
  local ans_dl ans_run
  local target_dir="$HOME/Termuxify"

  ans_dl="$(ask "Möchtest du das Termuxify-Repository (scto/Termuxify) herunterladen? (j/n)" "n")"
  if [[ "$ans_dl" =~ ^[jJyY] ]]; then
    if [[ -d "$target_dir" ]]; then
      warn "Verzeichnis $target_dir existiert bereits."
    else
      echo "Klone https://github.com/scto/Termuxify nach $target_dir ..."
      git clone https://github.com/scto/Termuxify "$target_dir"
      ok "Termuxify heruntergeladen."
    fi

    ans_run="$(ask "Soll Termuxify im Anschluss ausgeführt werden? (j/n)" "n")"
    if [[ "$ans_run" =~ ^[jJyY] ]]; then
      echo "Prüfe Startskripte in $target_dir ..."
      cd "$target_dir" || return
      
      # Versuche gängige Startskripte zu finden
      if [[ -x "./install.sh" || -f "./install.sh" ]]; then
        bash "./install.sh"
      elif [[ -x "./setup.sh" || -f "./setup.sh" ]]; then
        bash "./setup.sh"
      elif [[ -x "./termuxify.sh" || -f "./termuxify.sh" ]]; then
        bash "./termuxify.sh"
      else
        warn "Kein Standard-Startskript (install.sh, setup.sh, termuxify.sh) gefunden."
        echo "Bitte überprüfe den Ordner $target_dir und starte es manuell."
      fi
      
      # Zurück ins vorherige Verzeichnis
      cd - >/dev/null || true
    fi
  else
    echo "Termuxify wird übersprungen."
  fi
}

# =============================================================================
# 7. .bashrc
# =============================================================================
configure_bashrc() {
  step "7/7  ~/.bashrc konfigurieren"
  local rc="$HOME/.bashrc"
  touch "$rc"
  cp "$rc" "$rc.bak.$(date +%Y%m%d%H%M%S)"
  sed -i '/# >>> termux-android-setup >>>/,/# <<< termux-android-setup <<</d' "$rc"

  cat >> "$rc" <<'BASHRC'
# >>> termux-android-setup >>>
# ── Java ────────────────────────────────────────────────────────────────────
if [[ -d "$PREFIX/lib/jvm/java-17-openjdk" ]]; then
  export JAVA_HOME="$PREFIX/lib/jvm/java-17-openjdk"
elif command -v javac >/dev/null; then
  export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
fi

# ── Android SDK / NDK ───────────────────────────────────────────────────────
export ANDROID_HOME="__ANDROID_HOME__"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk-bundle"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
export NDK="$ANDROID_NDK_HOME"
_bt="$(ls -d "$ANDROID_HOME"/build-tools/* 2>/dev/null | sort -V | tail -n1)"
export ANDROID_BUILD_TOOLS="$_bt"
for _p in "${JAVA_HOME:+$JAVA_HOME/bin}" "$ANDROID_HOME/cmdline-tools/latest/bin" "$_bt" \
          "$ANDROID_HOME/platform-tools" "$HOME/.local/bin"; do
  [[ -n "$_p" && -d "$_p" && ":$PATH:" != *":$_p:"* ]] && PATH="$_p:$PATH"
done
export PATH; unset _p _bt

# ── Gradle ──────────────────────────────────────────────────────────────────
# GRADLE_HOME     = Installation der Termux-Gradle-Distribution
# GRADLE_USER_HOME = Caches, Wrapper-Distributionen, gradle.properties
if command -v gradle >/dev/null; then
  _g="$(dirname "$(dirname "$(readlink -f "$(command -v gradle)")")")"
  [[ -d "$_g/lib" ]] && export GRADLE_HOME="$_g"
  unset _g
fi
export GRADLE_USER_HOME="$HOME/.gradle"

# ── Allgemein ───────────────────────────────────────────────────────────────
export EDITOR=nano
export HISTSIZE=10000 HISTFILESIZE=20000 HISTCONTROL=ignoreboth:erasedups
shopt -s histappend checkwinsize cdspell 2>/dev/null

# ── Git-Aliases ─────────────────────────────────────────────────────────────
alias g='git'
alias gs='git status -sb'
alias ga='git add'
alias gaa='git add -A'
alias gc='git commit -m'
alias gca='git commit --amend --no-edit'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gpl='git pull --rebase'
alias gf='git fetch --all --prune'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gsw='git switch'
alias gb='git branch -vv'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline --graph --decorate -20'
alias gla='git log --oneline --graph --decorate --all'
alias gst='git stash'
alias gsp='git stash pop'
alias grs='git restore'
alias gcl='git clone --depth=1'
alias glfs='git lfs'
alias gwho='git config --global user.name; git config --global user.email'

# ── Gradle / Android ────────────────────────────────────────────────────────
alias gw='./gradlew'
alias gwb='./gradlew assembleDebug'
alias gwr='./gradlew assembleRelease'
alias gwc='./gradlew clean'
alias gwt='./gradlew test'
alias gwl='./gradlew lint'
alias gwd='./gradlew dependencies'
alias gws='./gradlew --stop'
alias gwo='./gradlew --offline assembleDebug'
_lastapk() { find . -path '*/build/outputs/apk/*' -name '*.apk' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2-; }
# Neueste APK nach /sdcard/Download kopieren
apkcp() { local a; a="$(_lastapk)"; [[ -n "$a" ]] && cp -v "$a" "$HOME/storage/downloads/" || echo "Keine APK gefunden."; }
# APK mit dem Android-Installer öffnen (Termux:API / termux-open)
apkinstall() { local a; a="$(_lastapk)"; [[ -n "$a" ]] && cp "$a" "$HOME/storage/downloads/" && termux-open "$HOME/storage/downloads/$(basename "$a")"; }
alias ndkver='grep Pkg.Revision "$ANDROID_NDK_HOME/source.properties"'
alias sdkinfo='echo "JAVA: $JAVA_HOME"; echo "GRDL: ${GRADLE_HOME:--} (user: $GRADLE_USER_HOME)"; echo "SDK : $ANDROID_HOME"; echo "NDK : $(readlink -f "$ANDROID_NDK_HOME")"; echo "BT  : $ANDROID_BUILD_TOOLS"; ls "$ANDROID_HOME/platforms" 2>/dev/null | sed "s/^/PLT : /"; java -version 2>&1 | head -1'

# ── Komfort ─────────────────────────────────────────────────────────────────
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias c='clear'
alias h='history | tail -50'
alias md='mkdir -p'
alias rcedit='nano ~/.bashrc'
alias rcload='source ~/.bashrc'
alias update='pkg update -y && pkg upgrade -y'
alias pkgs='pkg list-installed'
alias ports='lsof -i -P -n'
alias myip='curl -s https://ifconfig.me; echo'
alias sd='cd ~/storage/shared'
alias dl='cd ~/storage/downloads'
alias proj='mkdir -p ~/projects && cd ~/projects'
alias wakeon='termux-wake-lock'
alias wakeoff='termux-wake-unlock'
command -v bat >/dev/null && alias cat='bat --paging=never --style=plain'
mkcd() { mkdir -p "$1" && cd "$1"; }
extract() {
  case "$1" in
    *.tar.gz|*.tgz) tar xzf "$1" ;; *.tar.xz) tar xJf "$1" ;; *.tar.bz2) tar xjf "$1" ;;
    *.zip) unzip "$1" ;; *.7z) 7z x "$1" ;; *.gz) gunzip "$1" ;; *) echo "Unbekannt: $1" ;;
  esac
}

# ── Antigravity CLI ─────────────────────────────────────────────────────────
alias ag='agy'
alias agy-update='curl -fsSL https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh | AGY_INSTALL_SKIP_LAUNCH=1 bash'

# ── Prompt mit Git-Branch ───────────────────────────────────────────────────
_git_branch() { git branch --show-current 2>/dev/null | sed 's/.*/ (&)/'; }
PS1='\[\e[1;32m\]\w\[\e[0;33m\]$(_git_branch)\[\e[0m\] \$ '
# <<< termux-android-setup <<<
BASHRC

  sed -i "s|__ANDROID_HOME__|$ANDROID_HOME|" "$rc"

  ok ".bashrc aktualisiert (Backup: $rc.bak.*)"
}

# =============================================================================
# Ablauf
# =============================================================================
printf '%bTermux Android Dev Setup%b  –  SDK: %s\n' "$C_B" "$C_0" "$ANDROID_HOME"

if [[ $SKIP_PKG -eq 1 ]]; then
  for t in jq:jq 7z:p7zip curl:curl java:openjdk-17 git:git; do
    command -v "${t%%:*}" >/dev/null || pkg install -y "${t#*:}"
  done
fi

# Erst Pakete (jq/curl/git nötig), dann alle Fragen (Git, Versionen), dann der Rest
if [[ $MENU -eq 1 ]]; then component_menu; fi
[[ $SKIP_PKG -eq 1 ]] || install_packages
GIT_LOGIN=""
[[ $SKIP_GIT -eq 1 ]] || ask_git
select_versions
[[ $SKIP_GIT -eq 1 ]] || setup_git
SDKMANAGER="" CMAKE_VER="" NDK_REV=""
if [[ $CMDLINE_TOOLS -eq 1 ]]; then
  step "3a/7  cmdline-tools (sdkmanager) aus dem Mirror"
  if install_cmdline_tools; then accept_licenses; else SDKMANAGER=""; warn "cmdline-tools nicht installiert."; fi
fi
[[ $SKIP_SDK       -eq 1 ]] || { install_sdk; configure_gradle; }
if [[ $SKIP_CMAKE -eq 1 || -z "$CMAKE_PICK" ]] || ! install_cmake; then
  [[ $SKIP_SDK -eq 1 ]] || link_cmake      # Fallback: Termux-CMake für AGP verlinken
fi
[[ $SKIP_NDK       -eq 1 ]] || install_ndk
[[ $SKIP_AGY       -eq 1 ]] || install_agy
[[ $SKIP_TERMUXIFY -eq 1 ]] || install_termuxify
[[ $SKIP_BASHRC    -eq 1 ]] || configure_bashrc

step "Fertig 🎉"
cat <<EOF
  SDK        : $ANDROID_HOME
  cmdline-tools: $([[ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]] && cmdline_rev || echo -)
  build-tools: ${SDK_VER:--}
  platform   : ${PLATFORM_API:+android-$PLATFORM_API}
  NDK        : ${NDK_VER:--} ${NDK_REV:+(ndk/$NDK_REV)}
  CMake      : ${CMAKE_VER:--}

  Jetzt:  source ~/.bashrc   (oder Termux neu starten)
  Test :  sdkinfo  |  aapt2 version  |  agy --version

  Projekt-Einstellungen (app/build.gradle.kts):
    android {
        compileSdk = ${PLATFORM_API:-36}
        buildToolsVersion = "${SDK_VER:-37.0.0}"
        ndkVersion = "${NDK_REV:-<ndk-version>}"
        // externalNativeBuild { cmake { version = "${CMAKE_VER:-<cmake>}" } }
    }
  local.properties:  sdk.dir=$ANDROID_HOME
EOF
