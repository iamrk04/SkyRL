#!/bin/bash
# UV wrapper script for Docker
# Intercepts 'uv run' and uses the pre-built venv Python directly
# This prevents Ray from detecting uv and creating new venvs per worker

if [[ "$1" == "run" ]]; then
    shift  # remove "run"
    # Skip all uv options until we hit -m or a .py file
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --extra|--project|--directory)
                shift 2  # skip option and its value
                ;;
            --active|--no-sync|--frozen|--locked)
                shift  # skip flag
                ;;
            -m)
                # Found -m, run with venv python
                exec /app/skyrl-tx/.venv/bin/python "$@"
                ;;
            *.py)
                # Found a .py file, run with venv python
                exec /app/skyrl-tx/.venv/bin/python "$@"
                ;;
            *)
                shift  # skip unknown option
                ;;
        esac
    done
    echo "uv-wrapper: could not find -m or .py file in args: $@" >&2
    exit 1
else
    # For non-run commands (sync, add, etc), use real uv
    exec /home/ray/.local/bin/uv "$@"
fi
