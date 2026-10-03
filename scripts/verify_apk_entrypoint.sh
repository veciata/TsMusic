#!/usr/bin/env bash
#
# Verifies that an Android APK's dex actually contains the class named by its
# manifest's launcher activity.
#
# A missing launch activity yields an APK that installs successfully and then
# crashes immediately on launch with:
#   java.lang.ClassNotFoundException: Didn't find class "com.veciata.tsmusic.MainActivity"
# Nothing fails at build time, so this check turns that silent runtime failure
# into a build failure.
#
# Usage: tool/verify_apk_entrypoint.sh <apk> [fully.qualified.ActivityClass]
#        The activity class is read from the manifest when omitted.
set -euo pipefail

APK="${1:-}"
EXPECTED="${2:-}"

if [[ -z "$APK" ]]; then
  echo "usage: $(basename "$0") <apk> [fully.qualified.ActivityClass]" >&2
  exit 64
fi

if [[ ! -f "$APK" ]]; then
  echo "FAIL: APK not found: $APK" >&2
  exit 1
fi

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$SDK" ]]; then
  # Fall back to android/local.properties, which is how the Flutter tool and
  # local Gradle builds locate the SDK when the env vars are not exported.
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  LOCAL_PROPERTIES="$SCRIPT_DIR/../android/local.properties"
  if [[ -f "$LOCAL_PROPERTIES" ]]; then
    SDK="$(sed -n 's/^sdk\.dir=//p' "$LOCAL_PROPERTIES" | head -1)"
  fi
fi
if [[ -z "$SDK" || ! -d "$SDK" ]]; then
  echo "FAIL: Android SDK not found (set ANDROID_HOME/ANDROID_SDK_ROOT, or" \
       "ensure android/local.properties has sdk.dir)" >&2
  exit 1
fi

# Highest build-tools version available wins.
newest_tool() {
  ls -1 "$SDK"/build-tools/*/"$1" 2>/dev/null | sort -V | tail -1 || true
}

AAPT2="$(newest_tool aapt2)"
DEXDUMP="$(newest_tool dexdump)"
if [[ -z "$DEXDUMP" ]]; then
  DEXDUMP="$(command -v dexdump || true)"
fi

if [[ -z "$EXPECTED" ]]; then
  if [[ -z "$AAPT2" ]]; then
    echo "FAIL: aapt2 not found under $SDK/build-tools" >&2
    exit 1
  fi
  EXPECTED="$(
    "$AAPT2" dump badging "$APK" 2>/dev/null |
      sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p" |
      head -1
  )"
fi

if [[ -z "$EXPECTED" ]]; then
  echo "FAIL: no launchable activity found in $APK" >&2
  exit 1
fi

if [[ -z "$DEXDUMP" ]]; then
  echo "FAIL: dexdump not found under $SDK/build-tools" >&2
  exit 1
fi

DESCRIPTOR="L$(echo "$EXPECTED" | tr '.' '/');"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
unzip -o -q "$APK" '*.dex' -d "$WORKDIR"

shopt -s nullglob
DUMP="$WORKDIR/dexdump.txt"
for dex in "$WORKDIR"/*.dex; do
  # Dump to a file rather than piping: `grep -q` exits on the first match, which
  # would SIGPIPE dexdump and make `set -o pipefail` report a false failure.
  "$DEXDUMP" -f "$dex" >"$DUMP" 2>/dev/null || true
  if grep -qF "$DESCRIPTOR" "$DUMP"; then
    echo "OK: manifest launcher activity $EXPECTED is present in $(basename "$dex")"
    exit 0
  fi
done

{
  echo "FAIL: $EXPECTED ($DESCRIPTOR) is not present in any dex of $APK"
  echo
  echo "The manifest declares this activity, so the app will install and then crash"
  echo "on launch with ClassNotFoundException. That normally means the app's Kotlin"
  echo "sources were never compiled into the build. Two things to check:"
  echo "  1. Kotlin support is enabled (android.builtInKotlin in android/gradle.properties)."
  echo "  2. The release build is not reusing a GeneratedPluginRegistrant.java that a"
  echo "     previous debug build left behind, since Flutter excludes dev-dependency"
  echo "     plugins (integration_test) from release builds."
} >&2
exit 1
