#!/bin/bash

source setup/functions.sh

# Keep the system Python available for setup and migration scripts. The
# management application uses a separate, reproducible environment managed by
# uv so it is not coupled to Ubuntu's Python minor version.

uv_version=0.11.30
python_version=3.14
inst_dir=/usr/local/lib/mailinabox
tool_dir=$inst_dir/tools
uv=$tool_dir/uv
venv=$inst_dir/env
python_dir=$inst_dir/python

mkdir -p "$tool_dir" "$python_dir" "$inst_dir/cache/uv"

if [ "$(uname -m)" != "x86_64" ]; then
	echo "Mail-in-a-Box's Python runtime requires the x86_64 architecture." >&2
	exit 1
fi

uv_asset="uv-x86_64-unknown-linux-gnu.tar.gz"
uv_sha256="04bc7d180d6138bf6dc08387acf507a823f397a98fea55da36b0ccc7fbce3b68"
app_python_minor=$python_version

if [ ! -x "$uv" ] || [ "$($uv --version | awk '{print $2}')" != "$uv_version" ]; then
		tmp_dir=$(mktemp -d)
		archive=$tmp_dir/$uv_asset
		url="https://github.com/astral-sh/uv/releases/download/$uv_version/$uv_asset"

		hide_output wget -O "$archive" "$url"
		if ! printf '%s  %s\n' "$uv_sha256" "$archive" | sha256sum --check --status; then
			echo "Downloaded uv did not match its expected SHA-256 checksum." >&2
			rm -rf "$tmp_dir"
			exit 1
		fi

		mkdir "$tmp_dir/extracted"
		tar -xzf "$archive" -C "$tmp_dir/extracted" --strip-components=1
		install -m 0755 "$tmp_dir/extracted/uv" "$uv"
		rm -rf "$tmp_dir"
fi

export UV_CACHE_DIR=$inst_dir/cache/uv
export UV_PYTHON_INSTALL_DIR=$python_dir

if ! "$uv" python find "$python_version" >/dev/null 2>&1; then
	hide_output "$uv" python install "$python_version" --install-dir "$python_dir"
fi
app_python=$("$uv" python find "$python_version")

if [ ! -x "$venv/bin/python" ] || ! "$venv/bin/python" -c \
	"import sys; raise SystemExit(0 if sys.prefix != sys.base_prefix and f'{sys.version_info[0]}.{sys.version_info[1]}' == '$app_python_minor' else 1)" \
	>/dev/null 2>&1; then
		rm -rf "$venv"
		hide_output "$uv" venv "$venv" --python "$app_python"
fi

export MIAB_UV=$uv
export MIAB_VENV=$venv
export MIAB_PYTHON=$venv/bin/python
export MIAB_APP_PYTHON=$app_python
export UV_PROJECT_ENVIRONMENT=$venv

# The lockfile is part of the repository and is authoritative during setup.
hide_output "$uv" sync --locked --no-dev --python "$app_python" --directory "$PWD"
