#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
hooks_dir="$repo_root/.git/hooks"

cat > "$hooks_dir/pre-commit" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
fixed_script="$repo_root/scripts/remote-control-debug.fixed.sh"
target_script="$repo_root/scripts/remote-control-debug.sh"

if [[ -f "$fixed_script" ]]; then
  cp "$fixed_script" "$target_script"
  git add "$target_script"
fi
EOF

chmod +x "$hooks_dir/pre-commit"
echo "Installed pre-commit hook to reset scripts/remote-control-debug.sh"
