#!/usr/bin/env bash
# =============================================================================
# Erzeugt EINMALIG das Release-Asset "cmdline-tools" (sdkmanager, avdmanager, …) in diesem Repo.
#
# Quelle: das SDK-Archiv android-sdk-<SDK_VERSION> (HomuHomu833/android-sdk-custom). Es enthält neben
# build-tools/platform-tools auch cmdline-tools/ (reines Java, architekturunabhängig). Das Archiv wird
# temporär entpackt, nur cmdline-tools/ wird als eigenes Asset veröffentlicht:
#
#   Release  cmdline-tools-<Revision>            (Revision aus source.properties, z. B. cmdline-tools-19.0)
#   Asset    cmdline-tools-<Revision>.tar.xz     (Top-Ordner cmdline-tools/ mit bin/, lib/, source.properties)
#            cmdline-tools-<Revision>.tar.xz.sha256
#
# Das Setup-Script (setup-termux-android.sh --cmdline-tools) lädt dieses Asset statt Googles cmdline-tools.
#
# Reihenfolge der Quelle: 1. eigener Mirror (Release android-sdk-<ver>), 2. Upstream-Release <ver>.
# Idempotent: ist Release + Asset schon da, passiert nichts (FORCE=true lädt neu hoch).
#
# Umgebung:
#   GH_TOKEN      Token mit Schreibrecht auf TARGET_REPO (im Workflow: github.token)
#   TARGET_REPO   owner/repo, in das veröffentlicht wird
#   SDK_VERSION   SDK-Version, aus der entpackt wird (Standard 37.0.0)
#   VARIANT       Archiv-Variante (Standard aarch64-linux-android; cmdline-tools sind in allen identisch)
#   UPSTREAM_REPO Fallback-Quelle (Standard HomuHomu833/android-sdk-custom)
#   DRY_RUN       true = herunterladen, entpacken, packen, prüfen – aber nichts anlegen oder hochladen
#   FORCE         true = vorhandenes Asset neu hochladen
# =============================================================================
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN fehlt}"
: "${TARGET_REPO:?TARGET_REPO fehlt (owner/repo)}"
SDK_VERSION="${SDK_VERSION:-37.0.0}"
VARIANT="${VARIANT:-aarch64-linux-android}"
UPSTREAM_REPO="${UPSTREAM_REPO:-HomuHomu833/android-sdk-custom}"
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"
WORK="${RUNNER_TEMP:-/tmp}/cmdline-work"

die() { echo "::error::$*" >&2; exit 1; }

[[ "$TARGET_REPO"   =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "Ungültiges TARGET_REPO"
[[ "$UPSTREAM_REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "Ungültiges UPSTREAM_REPO"
[[ "$SDK_VERSION"   =~ ^[A-Za-z0-9._-]+$ ]]                 || die "Ungültige SDK_VERSION"
[[ "$VARIANT"       =~ ^[A-Za-z0-9._-]+$ ]]                 || die "Ungültige VARIANT"
for b in DRY_RUN FORCE; do [[ "${!b}" == true || "${!b}" == false ]] || die "$b muss true oder false sein"; done

retry() { # retry <n> <befehl…>
  local n=$1 i; shift
  for ((i = 1; i <= n; i++)); do "$@" && return 0; echo "  Versuch $i/$n fehlgeschlagen: $1 $2" >&2; sleep $((i * 5)); done
  return 1
}

rm -rf "$WORK"; mkdir -p "$WORK/src" "$WORK/x" "$WORK/stage" "$WORK/out"
ARCHIVE="android-sdk-$VARIANT.tar.xz"

# ---- 1. SDK-Archiv holen (Mirror, sonst Upstream) ----
echo "::group::SDK-Archiv $ARCHIVE ($SDK_VERSION)"
src_from=""
if retry 2 gh release download "android-sdk-$SDK_VERSION" -R "$TARGET_REPO" -p "$ARCHIVE" -D "$WORK/src" --clobber 2>/dev/null; then
  src_from="$TARGET_REPO (Release android-sdk-$SDK_VERSION)"
elif retry 3 gh release download "$SDK_VERSION" -R "$UPSTREAM_REPO" -p "$ARCHIVE" -D "$WORK/src" --clobber; then
  src_from="$UPSTREAM_REPO (Release $SDK_VERSION)"
else
  die "$ARCHIVE weder in $TARGET_REPO (android-sdk-$SDK_VERSION) noch in $UPSTREAM_REPO ($SDK_VERSION) gefunden"
fi
[[ -s "$WORK/src/$ARCHIVE" ]] || die "Archiv fehlt nach dem Download"
echo "Quelle: $src_from · $(du -h "$WORK/src/$ARCHIVE" | cut -f1)"
echo "::endgroup::"

# ---- 2. Nur cmdline-tools/ temporär entpacken ----
echo "::group::cmdline-tools entpacken"
tar -xJf "$WORK/src/$ARCHIVE" -C "$WORK/x" --wildcards '*cmdline-tools/*' \
  || die "Kein cmdline-tools/ im Archiv"
sm=$(find "$WORK/x" -type f -path '*/cmdline-tools/bin/sdkmanager' | head -n1 || true)
[[ -n "$sm" ]] || die "bin/sdkmanager im Archiv nicht gefunden"
root=$(dirname "$(dirname "$sm")")
props="$root/source.properties"
[[ -f "$props" ]] || die "source.properties fehlt in cmdline-tools"
REV=$(sed -n 's/^Pkg\.Revision *= *//p' "$props" | tr -d '\r ' | head -n1)
[[ "$REV" =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "Ungültige Pkg.Revision '$REV'"
echo "cmdline-tools Revision $REV"
cp -a "$root" "$WORK/stage/cmdline-tools"
chmod +x "$WORK/stage/cmdline-tools"/bin/* 2>/dev/null || true
rm -rf "$WORK/x"                       # temporär: Rest des SDK-Archivs wird nicht aufgehoben
echo "::endgroup::"

# ---- 3. Selbsttest (falls Java da ist) ----
if command -v java >/dev/null 2>&1; then
  got=$("$WORK/stage/cmdline-tools/bin/sdkmanager" --sdk_root="$WORK/sdkroot" --version 2>/dev/null | awk 'NF{gsub(/[ \r]/,""); print; exit}' || true)
  [[ "$got" == "$REV" ]] || die "sdkmanager meldet '$got', erwartet '$REV'"
  echo "sdkmanager --version: $got"
else
  echo "::warning::Java fehlt – sdkmanager-Selbsttest übersprungen"
fi

# ---- 4. Packen (reproduzierbar) ----
ASSET="cmdline-tools-$REV.tar.xz"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='2010-01-01 00:00:00 UTC' \
    -cf - -C "$WORK/stage" cmdline-tools | xz -6 -T0 > "$WORK/out/$ASSET"
( cd "$WORK/out" && sha256sum "$ASSET" > "$ASSET.sha256" )
SHA=$(cut -d' ' -f1 "$WORK/out/$ASSET.sha256")
echo "Asset: $ASSET ($(du -h "$WORK/out/$ASSET" | cut -f1)), sha256 ${SHA:0:12}…"

# ---- 5. Release anlegen und hochladen ----
TAG="cmdline-tools-$REV"
status="neu"
if gh release view "$TAG" -R "$TARGET_REPO" >/dev/null 2>&1; then
  existing=$(gh release view "$TAG" -R "$TARGET_REPO" --json assets -q '.assets[].name')
  if [[ "$FORCE" != true ]] && grep -qxF "$ASSET" <<<"$existing" && grep -qxF "$ASSET.sha256" <<<"$existing"; then
    echo "Release $TAG enthält $ASSET schon – nichts zu tun (FORCE=true lädt neu hoch)."
    status="vorhanden"
  else
    status="aktualisiert"
  fi
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] würde Release $TAG ($status) mit $ASSET und $ASSET.sha256 veröffentlichen"
elif [[ "$status" != vorhanden ]]; then
  if ! gh release view "$TAG" -R "$TARGET_REPO" >/dev/null 2>&1; then
    notes="Android cmdline-tools $REV (sdkmanager, avdmanager, …) – reines Java, für alle Architekturen.
Entpackt aus dem SDK-Archiv android-sdk-$SDK_VERSION ($src_from).
Asset: Top-Ordner cmdline-tools/ (bin/, lib/, source.properties). Installation: nach \$ANDROID_HOME/cmdline-tools/latest/.
SHA-256 in der .sha256-Datei. Herkunft/Lizenz siehe https://github.com/$UPSTREAM_REPO."
    retry 3 gh release create "$TAG" -R "$TARGET_REPO" --title "cmdline-tools $REV" --notes "$notes" --latest=false \
      || die "Release $TAG konnte nicht angelegt werden"
  fi
  retry 3 gh release upload "$TAG" "$WORK/out/$ASSET" "$WORK/out/$ASSET.sha256" -R "$TARGET_REPO" --clobber \
    || die "Upload fehlgeschlagen"
  echo "Veröffentlicht: $TAG / $ASSET"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## cmdline-tools → $TARGET_REPO"
    echo "| Release | Asset | SHA-256 | Quelle | Status | Trockenlauf |"
    echo "|---|---|---|---|---|---|"
    echo "| \`$TAG\` | \`$ASSET\` | \`${SHA:0:16}…\` | $src_from | $status | $DRY_RUN |"
  } >> "$GITHUB_STEP_SUMMARY"
fi
