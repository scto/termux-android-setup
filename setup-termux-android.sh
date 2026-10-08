#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
#  setup-termux-android.sh
#  Android-Entwicklungsumgebung für Termux (aarch64)
#
#   1. Termux-Pakete (Java 17, Git, Git-LFS, Gradle, Kotlin, build-essential, pip …)
#   2. Git einrichten: Name, E-Mail, GitHub-Token (→ Credential Store)
#   3. Android-SDK  (HomuHomu833/android-sdk-custom)  – Versionsmenü, Default 37.0.0
#      + Build-Tools / Platform (android.jar) via Google cmdline-tools,
#        native Binaries (aapt2, aidl, zipalign …) werden durch aarch64 ersetzt
#   4. Android-NDK  (HomuHomu833/android-ndk-custom)  – Versionsmenü, Default r29d
#   5. Antigravity CLI "agy" (wallentx/antigravity-cli-termux)
#   6. ~/.bashrc: JAVA_HOME, GRADLE_HOME, ANDROID_HOME, NDK, PATH, Aliases
#
#  Nutzung:
#    curl -fsSL https://raw.githubusercontent.com/scto/termux-android-setup/main/setup-termux-android.sh | bash
#    oder:  bash setup-termux-android.sh [Optionen]
#
#  Optionen:
#    --sdk VER          SDK-Version ohne Menü (z.B. 37.0.0)
#    --ndk VER          NDK-Version ohne Menü (z.B. r29d, r30b)
#    --platform N       Android-Platform API-Level ohne Menü (z.B. 36)
#    -y | --yes         Keine Fragen, überall Standardwerte nehmen
#    --skip-pkg         Paketinstallation überspringen
#    --skip-sdk         SDK überspringen
#    --skip-ndk         NDK überspringen
#    --skip-agy         Antigravity CLI überspringen
#    --skip-git         Git-Einrichtung (Name/E-Mail/Token) überspringen
#    --skip-bashrc      .bashrc nicht anfassen
#    --no-platform      Keine android.jar-Platform installieren
#    --force            SDK/NDK neu herunterladen, auch wenn vorhanden
#    -h | --help        Hilfe
#
#  ENV: GIT_NAME, GIT_EMAIL, GIT_TOKEN (Git ohne Rückfragen), GITHUB_TOKEN,
#       ANDROID_HOME, ASSET_VARIANT
#  Re-Run ist sicher (idempotent): .bashrc-Block wird ersetzt, nicht dupliziert.
# =============================================================================
set -Eeuo pipefail

# ── Konfiguration (per ENV überschreibbar) ───────────────────────────────────
SDK_REPO="${SDK_REPO:-HomuHomu833/android-sdk-custom}"
NDK_REPO="${NDK_REPO:-HomuHomu833/android-ndk-custom}"
# Termux = Android/Bionic → "aarch64-linux-android"
ASSET_VARIANT="${ASSET_VARIANT:-aarch64-linux-android}"
DEFAULT_SDK="${DEFAULT_SDK:-37.0.0}"
DEFAULT_NDK="${DEFAULT_NDK:-r29d}"
AGY_INSTALLER="${AGY_INSTALLER:-https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh}"
# Google cmdline-tools (reines Java → läuft auf aarch64); nur für Java-Teile + android.jar
CMDLINE_TOOLS_URL="${CMDLINE_TOOLS_URL:-https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip}"

ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
DL_DIR="${DL_DIR:-$HOME/.cache/termux-android-setup}"

SDK_VER="" NDK_VER="" PLATFORM_API=""
GIT_NAME="${GIT_NAME:-}" GIT_EMAIL="${GIT_EMAIL:-}" GIT_TOKEN="${GIT_TOKEN:-}"
ASSUME_YES=0 SKIP_GIT=0 SKIP_PKG=0 SKIP_SDK=0 SKIP_NDK=0 SKIP_AGY=0 SKIP_BASHRC=0 NO_PLATFORM=0 FORCE=0

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
  if [[ -f "$self" ]]; then sed -n '2,37p' "$self" | sed 's/^# \{0,1\}//'; else echo "Siehe Kopfkommentar im Script."; fi
  exit 0
}

# ── Argumente ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sdk)         SDK_VER="${2:?Version fehlt}"; shift ;;
    --ndk)         NDK_VER="${2:?Version fehlt}"; shift ;;
    --platform)    PLATFORM_API="${2:?API-Level fehlt}"; shift ;;
    -y|--yes)      ASSUME_YES=1 ;;
    --skip-pkg)    SKIP_PKG=1 ;;
    --skip-sdk)    SKIP_SDK=1 ;;
    --skip-ndk)    SKIP_NDK=1 ;;
    --skip-agy)    SKIP_AGY=1 ;;
    --skip-bashrc) SKIP_BASHRC=1 ;;
    --skip-git)    SKIP_GIT=1 ;;
    --no-platform) NO_PLATFORM=1 ;;
    --force)       FORCE=1 ;;
    -h|--help)     usage ;;
    *) die "Unbekannte Option: $1 (siehe --help)" ;;
  esac
  shift
done

# ── Vorabprüfungen ───────────────────────────────────────────────────────────
[[ -n "${TERMUX_VERSION:-}" && -n "${PREFIX:-}" ]] || die "Dieses Script läuft nur in nativem Termux (nicht in proot)."
[[ "$(uname -m)" == "aarch64" ]] || die "Nur aarch64 wird unterstützt (gefunden: $(uname -m))."
mkdir -p "$DL_DIR" "$ANDROID_HOME"

# Interaktiv? Auch bei "curl | bash" über /dev/tty fragen.
INTERACTIVE=0
if [[ $ASSUME_YES -eq 0 ]] && (: </dev/tty) 2>/dev/null; then exec 3</dev/tty; INTERACTIVE=1; fi

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

# releases_tsv <repo> → Zeilen: "<anzeige>\t<asset-name>\t<url>"  (neueste zuerst)
# Nur Releases mit passendem Termux-Asset (ASSET_VARIANT).
releases_tsv() {
  gh_api "https://api.github.com/repos/$1/releases?per_page=100" | jq -r --arg v "$ASSET_VARIANT" '
    .[] | . as $r
    | ($r.assets[] | select(.name | test("-" + $v + "\\.(tar\\.xz|tar\\.gz|zip|7z)$"))) as $a
    | [ (if ($r.name // "") != "" then $r.name else $r.tag_name end)
        + (if $r.prerelease then " (pre-release)" else "" end),
        $a.name, $a.browser_download_url ] | @tsv'
}

# choose_release <repo> <Titel> <Default> <Vorgabe> → setzt REL_NAME / REL_ASSET / REL_URL
choose_release() {
  local repo="$1" title="$2" def_ver="$3" want="$4" tsv
  tsv="$(releases_tsv "$repo")"
  [[ -n "$tsv" ]] || die "Keine Releases mit Asset *-$ASSET_VARIANT in $repo gefunden."
  local -a names assets urls
  while IFS=$'\t' read -r n a u; do names+=("$n"); assets+=("$a"); urls+=("$u"); done <<<"$tsv"

  # Index für eine Version suchen (exakt in Name/Asset, sonst normalisiert)
  find_idx() {
    local v="$1" i nv; nv="$(norm_ver "$v")"
    for i in "${!names[@]}"; do [[ "${names[$i]%% *}" == "$v" || "${assets[$i]}" == *"-$v-"* ]] && { echo "$i"; return; }; done
    for i in "${!names[@]}"; do [[ "$(norm_ver "${names[$i]%% *}")" == "$nv" ]] && { echo "$i"; return; }; done
    echo -1
  }

  local idx
  if [[ -n "$want" ]]; then
    idx="$(find_idx "$want")"
    [[ $idx -ge 0 ]] || die "Version '$want' nicht gefunden. Verfügbar: ${names[*]}"
  else
    local d; d="$(find_idx "$def_ver")"; [[ $d -ge 0 ]] || d=0
    local -a labels; local i
    for i in "${!names[@]}"; do labels+=("$(printf '%-22s %s' "${names[$i]}" "${assets[$i]}")"); done
    idx="$(menu "$title" "$d" "${labels[@]}")"
  fi
  REL_NAME="${names[$idx]%% *}"; REL_ASSET="${assets[$idx]}"; REL_URL="${urls[$idx]}"
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
  step "Versionen wählen"
  if [[ $SKIP_SDK -eq 0 ]]; then
    choose_release "$SDK_REPO" "Android-SDK (build-tools / platform-tools, aarch64):" "$DEFAULT_SDK" "$SDK_VER"
    SDK_VER="$REL_NAME" SDK_ASSET="$REL_ASSET" SDK_URL="$REL_URL"
    ok "SDK: $SDK_VER  ($SDK_ASSET)"
  fi
  if [[ $SKIP_NDK -eq 0 ]]; then
    choose_release "$NDK_REPO" "Android-NDK (aarch64):" "$DEFAULT_NDK" "$NDK_VER"
    NDK_VER="$REL_NAME" NDK_ASSET="$REL_ASSET" NDK_URL="$REL_URL"
    ok "NDK: $NDK_VER  ($NDK_ASSET)"
  fi
}

# =============================================================================
# 1. Termux-Pakete
# =============================================================================
install_packages() {
  step "1/6  Termux-Pakete installieren"
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
  step "2/6  Git konfigurieren"
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
#    a) Google cmdline-tools  → sdkmanager (Java)
#    b) build-tools;<ver> + platforms;android-N  (offiziell: package.xml, *.jar)
#    c) native x86-Binaries in build-tools/platform-tools durch aarch64 ersetzen
# =============================================================================
install_cmdline_tools() {
  SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
  [[ -x "$SDKMANAGER" && $FORCE -eq 0 ]] && return 0
  local file="$DL_DIR/$(basename "$CMDLINE_TOOLS_URL")" tmp="$DL_DIR/clt-extract"
  download "$CMDLINE_TOOLS_URL" "$file" || { warn "cmdline-tools Download fehlgeschlagen."; return 1; }
  extract "$file" "$tmp"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  rm -rf "$ANDROID_HOME/cmdline-tools/latest"
  mv "$(content_root "$tmp")" "$ANDROID_HOME/cmdline-tools/latest"
  rm -rf "$tmp"
  ok "cmdline-tools installiert"
}

sdkm() { "$SDKMANAGER" --sdk_root="$ANDROID_HOME" "$@"; }

accept_licenses() {
  mkdir -p "$ANDROID_HOME/licenses"
  printf '\n24333f8a63b6825ea9c5514f83c2829b004d1fee\nd56f5187479451eabf01fb78af6dfcb131a6481e\n' \
    > "$ANDROID_HOME/licenses/android-sdk-license"
  printf '\n84831b9409646a918e30573bab4c9c91346d8abd\n' \
    > "$ANDROID_HOME/licenses/android-sdk-preview-license"
  [[ -x "${SDKMANAGER:-}" ]] && { yes | sdkm --licenses >/dev/null 2>&1 || true; }
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
# im Ziel + kopiert fehlende hinzu (ELF-Binaries & .so von aarch64-Build)
overlay_natives() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  cp -a "$src"/. "$dst"/
  find "$dst" -maxdepth 2 -type f ! -name '*.jar' ! -name '*.xml' ! -name '*.properties' \
       -exec chmod +x {} + 2>/dev/null || true
}

install_sdk() {
  step "3/6  Android-SDK $SDK_VER (aarch64) → $ANDROID_HOME"
  local bt_dir="$ANDROID_HOME/build-tools/$SDK_VER"

  # a) cmdline-tools + Lizenzen
  if install_cmdline_tools; then accept_licenses; else SDKMANAGER=""; fi

  # b) Offizielle build-tools (Java-Teile, package.xml, damit AGP sie erkennt)
  if [[ -n "$SDKMANAGER" && ( ! -f "$bt_dir/source.properties" || $FORCE -eq 1 ) ]]; then
    if sdkm "build-tools;$SDK_VER"; then
      ok "Offizielle build-tools;$SDK_VER (Java-Teile) installiert"
    else
      warn "build-tools;$SDK_VER bei Google nicht verfügbar – nur aarch64-Binaries werden genutzt."
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

  # c) Custom aarch64-SDK herunterladen & native Binaries einspielen
  local file="$DL_DIR/sdk-$SDK_VER-$SDK_ASSET" tmp="$DL_DIR/sdk-extract" root aapt2 adb
  download "$SDK_URL" "$file"
  echo "Entpacke $SDK_ASSET …"
  extract "$file" "$tmp"
  root="$(content_root "$tmp")"

  aapt2="$(find "$root" -type f -name aapt2 | head -n1 || true)"
  adb="$(find "$root" -type f -name adb | head -n1 || true)"
  [[ -n "$aapt2" ]] || die "aapt2 im SDK-Archiv nicht gefunden – Layout unbekannt ($root)."

  overlay_natives "$(dirname "$aapt2")" "$bt_dir"
  ok "build-tools/$SDK_VER: aarch64-Binaries eingespielt"
  if [[ -n "$adb" ]]; then
    overlay_natives "$(dirname "$adb")" "$ANDROID_HOME/platform-tools"
    ok "platform-tools: aarch64-Binaries eingespielt"
  fi
  rm -rf "$tmp"

  # Minimal-Metadaten, falls Google die Version nicht hatte (AGP liest Pkg.Revision)
  [[ -f "$bt_dir/source.properties" ]] || printf 'Pkg.Desc = Android SDK Build-Tools %s (aarch64)\nPkg.Revision = %s\n' "$SDK_VER" "$SDK_VER" > "$bt_dir/source.properties"

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

# =============================================================================
# 4. Android-NDK
# =============================================================================
install_ndk() {
  step "4/6  Android-NDK $NDK_VER (aarch64)"
  mkdir -p "$ANDROID_HOME/ndk"

  local file="$DL_DIR/$NDK_ASSET" tmp="$DL_DIR/ndk-extract" root ver
  download "$NDK_URL" "$file"
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
  step "5/6  Antigravity CLI (agy) installieren"
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
# 6. .bashrc
# =============================================================================
configure_bashrc() {
  step "6/6  ~/.bashrc konfigurieren"
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
[[ $SKIP_PKG -eq 1 ]] || install_packages
GIT_LOGIN=""
[[ $SKIP_GIT -eq 1 ]] || ask_git
select_versions
[[ $SKIP_GIT -eq 1 ]] || setup_git
SDKMANAGER="" CMAKE_VER="" NDK_REV=""
[[ $SKIP_SDK    -eq 1 ]] || { install_sdk; link_cmake; configure_gradle; }
[[ $SKIP_NDK    -eq 1 ]] || install_ndk
[[ $SKIP_AGY    -eq 1 ]] || install_agy
[[ $SKIP_BASHRC -eq 1 ]] || configure_bashrc

step "Fertig 🎉"
cat <<EOF
  SDK        : $ANDROID_HOME
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
