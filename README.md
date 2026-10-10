# termux-android-setup

Ein Script, das in **Termux (aarch64)** eine komplette Umgebung für die Android-App-Entwicklung einrichtet: Java 17, Gradle, Kotlin, Git mit GitHub-Login, Android-SDK, NDK, Build-Tools, Antigravity CLI, Termuxify und eine fertig konfigurierte `.bashrc`.

Ziel: Android-Apps (Kotlin, Jetpack Compose, NDK/C++) direkt auf dem Smartphone bauen, ohne PC, ohne proot und ohne Root.

![Platform](https://img.shields.io/badge/platform-Termux-black)
![Arch](https://img.shields.io/badge/arch-aarch64-blue)
![License](https://img.shields.io/badge/license-GPL--3.0-green)

---

## Installation

In **Termux** (nicht in proot) ausführen:

```bash
curl -fsSL https://raw.githubusercontent.com/scto/termux-android-setup/main/setup-termux-android.sh | bash
```

Das Script fragt am Anfang nach deinen Git-Daten (Name, E-Mail, GitHub-Token) und der gewünschten SDK-, NDK- und Platform-Version. Mit **Enter** wird jeweils der Standardwert übernommen. Danach läuft die Installation ohne weitere Eingaben durch.

Nach der Installation die Shell neu laden:

```bash
source ~/.bashrc
```

### Alternative: Repo klonen

```bash
pkg install -y git
git clone https://github.com/scto/termux-android-setup.git
cd termux-android-setup
bash setup-termux-android.sh
```

### Ohne Rückfragen / mit festen Versionen

```bash
curl -fsSL https://raw.githubusercontent.com/scto/termux-android-setup/main/setup-termux-android.sh \
  | GIT_NAME="Max Muster" GIT_EMAIL="max@example.com" GIT_TOKEN="ghp_xxx" \
    bash -s -- --sdk 37.0.0 --ndk r29d --platform 36 -y
```

> **Hinweis:** Die Installation lädt mehrere GB herunter (vor allem das NDK). Am besten im WLAN ausführen und mit `termux-wake-lock` verhindern, dass Android Termux im Hintergrund beendet.

---

## Was wird installiert?

### 1. Termux-Pakete
| Bereich | Pakete |
|---|---|
| Build | `openjdk-17`, `gradle`, `kotlin`, `git`, `git-lfs` |
| Native / NDK | `build-essential`, `clang`, `cmake`, `ninja`, `make`, `binutils`, `pkg-config`, `protobuf` |
| Python | `python`, `python-pip` |
| Archive & Netz | `curl`, `wget`, `zip`, `unzip`, `tar`, `xz-utils`, `p7zip` |
| Tools | `jq`, `python`, `nano`, `vim`, `ripgrep`, `fd`, `bat`, `openssh`, `rsync`, `termux-api` |
| Für agy | `glibc-repo`, `glibc`, `ca-certificates`, `resolv-conf`, `proot` |

### 2. Git
- Fragt **user.name**, **user.email** und ein **GitHub Personal Access Token** ab. Vorhandene Werte werden als Vorschlag angezeigt, das Token kann mit Enter übersprungen werden.
- Das Token wird gegen die GitHub-API geprüft, der GitHub-Benutzername wird daraus automatisch ermittelt.
- Speicherung im **Credential Store** (`credential.helper store` → `~/.git-credentials`, Rechte `600`). Danach funktionieren `git push`/`pull` auf github.com ohne Passwortabfrage.
- Sinnvolle Defaults: `init.defaultBranch=main`, `pull.rebase=true`, `push.autoSetupRemote=true`, `fetch.prune=true`, `core.editor=nano`
- `git lfs install`

> **Token erstellen:** GitHub → Settings → Developer settings → Personal access tokens. Für klassische Tokens die Scopes `repo` und `workflow` wählen.
>
> **Hinweis:** Der Credential Store speichert das Token im Klartext (nur für deinen Termux-Benutzer lesbar). Termux bietet keinen verschlüsselten Schlüsselbund.

### 3. Android-SDK (aarch64)
- Native Binaries (`aapt2`, `aidl`, `zipalign`, `adb` …) aus [HomuHomu833/android-sdk-custom](https://github.com/HomuHomu833/android-sdk-custom), **Standard: 37.0.0**
- Google **cmdline-tools** (`sdkmanager`, `avdmanager`)
- Offizielle **build-tools** (Java-Teile/Metadaten) und **Platform** (`android.jar`) über `sdkmanager`. Die darin enthaltenen x86-Binaries werden anschließend durch die aarch64-Versionen ersetzt.
- `android.aapt2FromMavenOverride` in `~/.gradle/gradle.properties`, damit Gradle nicht das x86-aapt2 von Maven lädt
- Das Termux-CMake wird für Gradle unter `$ANDROID_HOME/cmake/<version>` verlinkt

### 4. Android-NDK (aarch64)
- Aus [HomuHomu833/android-ndk-custom](https://github.com/HomuHomu833/android-ndk-custom), **Standard: r29d**
- Installiert nach `$ANDROID_HOME/ndk/<Pkg.Revision>`, damit Gradle es über `ndkVersion` findet, plus Symlink `ndk-bundle`

### 5. Antigravity CLI (`agy`)
- Termux-Port von [wallentx/antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux)
- Auf CPUs ohne LSE-Atomics wird automatisch `qemu-user-aarch64` installiert

### 6. Termuxify
- Fragt interaktiv ab, ob das Repository [scto/Termuxify](https://github.com/scto/Termuxify) nach `~/Termuxify` heruntergeladen werden soll.
- Bietet im Anschluss die Möglichkeit, automatisch nach Startskripten (`install.sh`, `setup.sh` oder `termuxify.sh`) zu suchen und diese direkt auszuführen.

### 7. `~/.bashrc`
- `JAVA_HOME` (OpenJDK 17, mit Fallback auf das installierte `javac`)
- `GRADLE_HOME` (Termux-Gradle) und `GRADLE_USER_HOME` (`~/.gradle`: Caches, Wrapper, `gradle.properties`)
- `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `ANDROID_NDK_HOME`, `NDK`, `PATH`
- Git-, Gradle- und Komfort-Aliases (siehe unten)
- Prompt mit aktuellem Git-Branch
- Die Einträge stehen in einem markierten Block. Bei einem erneuten Lauf wird dieser ersetzt statt doppelt angehängt, vorher wird ein Backup (`~/.bashrc.bak.<datum>`) angelegt.

---

## Optionen

| Option | Beschreibung |
|---|---|
| `--sdk VER` | SDK-Version ohne Menü (z. B. `37.0.0`) |
| `--ndk VER` | NDK-Version ohne Menü (z. B. `r29d`, `r30b`) |
| `--platform N` | API-Level für `android.jar` ohne Menü (z. B. `36`) |
| `-y`, `--yes` | Keine Fragen, überall Standardwerte |
| `--skip-pkg` | Termux-Pakete überspringen |
| `--skip-sdk` | SDK überspringen |
| `--skip-ndk` | NDK überspringen |
| `--skip-agy` | Antigravity CLI überspringen |
| `--skip-termuxify` | Termuxify-Abfrage überspringen |
| `--skip-git` | Git-Einrichtung (Name, E-Mail, Token) überspringen |
| `--skip-bashrc` | `.bashrc` nicht verändern |
| `--no-platform` | Keine Platform (`android.jar`) installieren |
| `--force` | SDK/NDK neu herunterladen, auch wenn vorhanden |
| `-h`, `--help` | Hilfe anzeigen |

### Umgebungsvariablen

| Variable | Standard | Zweck |
|---|---|---|
| `ANDROID_HOME` | `~/android-sdk` | Installationsort des SDK |
| `GIT_NAME` / `GIT_EMAIL` | aus `~/.gitconfig` | Git-Identität ohne Rückfrage |
| `GIT_TOKEN` | – | GitHub-Token ohne Rückfrage (wird im Credential Store gespeichert) |
| `GITHUB_TOKEN` | – | Gegen das Rate-Limit der GitHub-API (Standard: das eingegebene Git-Token) |
| `ASSET_VARIANT` | `aarch64-linux-android` | Welche Build-Variante der Custom-Releases geladen wird |
| `DEFAULT_SDK` / `DEFAULT_NDK` | `37.0.0` / `r29d` | Vorauswahl im Menü |

---

## Aliases

<details>
<summary><b>Git</b></summary>

| Alias | Befehl |
|---|---|
| `g` | `git` |
| `gs` | `git status -sb` |
| `ga` / `gaa` | `git add` / `git add -A` |
| `gc` | `git commit -m` |
| `gca` | `git commit --amend --no-edit` |
| `gp` / `gpf` | `git push` / `git push --force-with-lease` |
| `gpl` | `git pull --rebase` |
| `gf` | `git fetch --all --prune` |
| `gco` / `gcb` / `gsw` | `checkout` / `checkout -b` / `switch` |
| `gb` | `git branch -vv` |
| `gd` / `gds` | `git diff` / `git diff --staged` |
| `gl` / `gla` | Log als Graph (letzte 20 / alle Branches) |
| `gst` / `gsp` | `git stash` / `git stash pop` |
| `grs` | `git restore` |
| `gcl` | `git clone --depth=1` |
| `glfs` | `git lfs` |
| `gwho` | Aktuellen Git-Namen und E-Mail anzeigen |
</details>

<details>
<summary><b>Gradle / Android</b></summary>

| Alias | Befehl |
|---|---|
| `gw` | `./gradlew` |
| `gwb` / `gwr` | `assembleDebug` / `assembleRelease` |
| `gwc` / `gwt` / `gwl` | `clean` / `test` / `lint` |
| `gwd` | `dependencies` |
| `gwo` | `--offline assembleDebug` |
| `gws` | `--stop` (Gradle-Daemon beenden) |
| `apkcp` | Neueste APK nach `Download/` kopieren |
| `apkinstall` | Neueste APK kopieren und mit dem Android-Installer öffnen |
| `sdkinfo` | Java-, Gradle-, SDK-, NDK-, Build-Tools- und Platform-Pfade anzeigen |
| `ndkver` | NDK-Version anzeigen |
</details>

<details>
<summary><b>Allgemein</b></summary>

| Alias | Befehl |
|---|---|
| `ll` / `la` / `l` | `ls`-Varianten |
| `..` / `...` | Verzeichnis hoch |
| `mkcd <dir>` | Ordner anlegen und hineinwechseln |
| `extract <datei>` | Beliebiges Archiv entpacken |
| `proj` | `~/projects` öffnen |
| `sd` / `dl` | Gemeinsamer Speicher / Downloads |
| `update` | `pkg update && pkg upgrade` |
| `rcedit` / `rcload` | `.bashrc` bearbeiten / neu laden |
| `wakeon` / `wakeoff` | Wake-Lock an/aus |
| `ag` / `agy-update` | Antigravity CLI starten / aktualisieren |
</details>

---

## Projekt konfigurieren

Am Ende zeigt das Script die passenden Werte an. Beispiel für `app/build.gradle.kts`:

```kotlin
android {
    compileSdk = 36
    buildToolsVersion = "37.0.0"
    ndkVersion = "29.0.14206865"   // Ausgabe von: ndkver

    // Nur bei NDK/C++-Projekten:
    // externalNativeBuild { cmake { version = "<cmake-version>" } }
}
```

`local.properties`:

```properties
sdk.dir=/data/data/com.termux/files/home/android-sdk
```

Bauen:

```bash
cd ~/projects/MeineApp
gwb          # ./gradlew assembleDebug
apkinstall   # APK installieren
```

---

## Update

Das Script kann jederzeit erneut ausgeführt werden. Bereits installierte Teile werden erkannt und übersprungen:

```bash
# Andere NDK-Version zusätzlich installieren
curl -fsSL https://raw.githubusercontent.com/scto/termux-android-setup/main/setup-termux-android.sh \
  | bash -s -- --skip-pkg --skip-sdk --skip-agy --skip-bashrc --ndk r30b

# Nur Antigravity CLI aktualisieren
agy-update
```

> Wer später mit `sdkmanager` weitere **build-tools** oder **platform-tools** nachinstalliert, bekommt wieder x86-Binaries. Dann das Script mit `--sdk <version>` erneut ausführen, um sie durch die aarch64-Versionen zu ersetzen.

---

## Problembehebung

| Problem | Lösung |
|---|---|
| `GitHub-API nicht erreichbar` / Rate-Limit | `export GITHUB_TOKEN=<token>` und erneut starten |
| `AAPT2 … Daemon startup failed` | `~/.gradle/gradle.properties` prüfen (`aapt2FromMavenOverride`), dann `gws` |
| `aapt2 startet nicht` / NDK-`clang` startet nicht | Andere Variante testen, z. B. `ASSET_VARIANT=aarch64-linux-musl` |
| Gradle bricht mit `OutOfMemory` ab | `org.gradle.jvmargs` in `~/.gradle/gradle.properties` anpassen |
| Termux wird im Hintergrund beendet | `wakeon` vor dem Build, Akku-Optimierung für Termux deaktivieren |
| `git push` fragt nach Passwort | Token abgelaufen: Script mit `--skip-pkg --skip-sdk --skip-ndk --skip-agy --skip-bashrc` erneut starten und neues Token eingeben |
| `agy` startet nicht | `agy-update` ausführen, bei Problemen siehe [antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux) |

---

## Voraussetzungen

- Android 9 oder neuer, **arm64 / aarch64**
- [Termux](https://github.com/termux/termux-app) aus F-Droid oder GitHub (nicht aus dem Play Store)
- Optional: [Termux:API](https://github.com/termux/termux-api) für `apkinstall`
- Mindestens ~8 GB freier Speicher

---

## Credits

- [HomuHomu833/android-sdk-custom](https://github.com/HomuHomu833/android-sdk-custom): Android-SDK-Binaries für aarch64
- [HomuHomu833/android-ndk-custom](https://github.com/HomuHomu833/android-ndk-custom): Android-NDK für aarch64
- [wallentx/antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux): Antigravity CLI für Termux
- [Termux](https://termux.dev)

## Lizenz

[GPL-3.0](LICENSE)
