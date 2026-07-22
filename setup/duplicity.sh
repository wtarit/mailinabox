#!/bin/bash

source setup/functions.sh

if [ -z "${MIAB_UV:-}" ]; then
	# Allow this script to be run directly during development or recovery.
	source setup/python.sh
fi

echo "Installing duplicity in its isolated Python environment..."

duplicity_project="$PWD/setup/duplicity"
duplicity_venv=/usr/local/lib/mailinabox/duplicity-env
duplicity_bin=$duplicity_venv/bin/duplicity
app_python_version=$(
	"$MIAB_APP_PYTHON" -c 'import platform; print(platform.python_version())'
)

if [ ! -x "$duplicity_venv/bin/python" ] || ! "$duplicity_venv/bin/python" -c \
	"import platform, sys; raise SystemExit(0 if sys.prefix != sys.base_prefix and platform.python_version() == '$app_python_version' else 1)" \
	>/dev/null 2>&1; then
	rm -rf /usr/local/lib/mailinabox/duplicity-env
	hide_output "$MIAB_UV" venv "$duplicity_venv" --python "$MIAB_APP_PYTHON" || exit 1
fi

# Keep duplicity's large backend dependency set isolated from the management
# daemon. The dedicated lockfile makes setup repeatable and upgrades explicit.
hide_output env UV_PROJECT_ENVIRONMENT="$duplicity_venv" \
	"$MIAB_UV" sync --locked --no-dev --python "$MIAB_APP_PYTHON" \
	--directory "$duplicity_project" || exit 1

if [ ! -x "$duplicity_bin" ] || [ "$("$duplicity_venv/bin/python" -c 'import duplicity; print(duplicity.__version__)')" != "3.1.0" ]; then
	echo "ERROR: The isolated duplicity installation has an unexpected version." >&2
	exit 1
fi
