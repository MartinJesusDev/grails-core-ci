#!/usr/bin/env bash
# Instala las herramientas locales de grails-core-ci en ~/.local/bin.
#
# Uso: ./install.sh [--copy]
#   Por defecto crea enlaces simbólicos (git pull actualiza las herramientas).
#   --copy copia los scripts, útil si el repo no va a estar siempre en la misma ruta.
#
# Requisitos: gh autenticado (gh auth status), jq, timeout y column.
set -euo pipefail

src_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bin_dir="${BIN_DIR:-$HOME/.local/bin}"
state_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/gh-ci-watch-$(id -u)"
mode=symlink

case "${1:-}" in
    --copy) mode=copy ;;
    '') ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "install.sh: opción desconocida '$1'" >&2; exit 2 ;;
esac

mkdir -p "$bin_dir" "$state_dir"
chmod 700 "$state_dir" 2>/dev/null || true

for tool in gh-ci-watch gh-ci-status; do
    src="$src_dir/bin/$tool"
    [[ -f $src ]] || { echo "install.sh: falta $src" >&2; exit 2; }
    chmod +x "$src"
    dest="$bin_dir/$tool"
    if [[ $mode == copy ]]; then
        install -m 755 "$src" "$dest"
        echo "instalado (copia): $dest"
    else
        ln -sfn "$src" "$dest"
        echo "instalado (enlace): $dest -> $src"
    fi
done

missing=()
for cmd in gh jq timeout column; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
done
if ((${#missing[@]})); then
    echo "faltan dependencias: ${missing[*]}" >&2
    echo "instálalas antes de usar las herramientas (en Debian/Ubuntu: apt install gh jq coreutils util-linux)" >&2
else
    echo "dependencias OK: gh jq timeout column"
fi

echo "logs de sesión: $state_dir"
echo "siguiente paso: gh auth status && gh-ci-status"
