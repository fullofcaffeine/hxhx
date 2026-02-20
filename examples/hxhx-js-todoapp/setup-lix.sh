#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [ ! -f .haxerc ]; then
  lix scope create >/dev/null
fi

install_from_github() {
  local repo_url="$1"
  lix install "$repo_url" >/dev/null
}

install_from_github "https://github.com/MVCoconut/coconut.ui.git"
install_from_github "https://github.com/MVCoconut/coconut.vdom.git"
install_from_github "https://github.com/haxetink/tink_web.git"
install_from_github "https://github.com/haxetink/tink_sql.git"

# Keep core on a modern version to avoid resolver edge-cases with older transitive pins.
install_from_github "https://github.com/haxetink/tink_core.git"

mkdir -p deps

sql_cp_raw="$(awk '/^-cp / { print $2; exit }' haxe_libraries/tink_sql.hxml)"
if [ -z "$sql_cp_raw" ]; then
  echo "Unable to resolve tink_sql classpath from haxe_libraries/tink_sql.hxml" >&2
  exit 1
fi

sql_rel="${sql_cp_raw#\$\{HAXE_LIBCACHE\}/}"
sql_src=""
for root in "${HAXE_LIBCACHE:-}" "$HOME/haxe/haxe_libraries" "$HOME/.haxe/lib"; do
  [ -n "$root" ] || continue
  candidate="$root/$sql_rel"
  if [ -d "$candidate" ]; then
    sql_src="$candidate"
    break
  fi
done

if [ -z "$sql_src" ]; then
  echo "Unable to locate tink_sql source directory for: $sql_rel" >&2
  exit 1
fi

ln -sfn "$sql_src" deps/tink_sql_src
