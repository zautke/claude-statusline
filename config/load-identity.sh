# shellcheck shell=bash
# Load config/identity.env as KEY=VALUE lines (values may contain spaces; no quoting, no
# expansion), so bash and pwsh (ConvertFrom-StringData) read the same file the same way.
load_identity() {
  local k v
  while IFS='=' read -r k v || [[ -n $k ]]; do
    case "$k" in ''|'#'*) continue ;; esac
    printf -v "$k" '%s' "$v"
  done <"$1"
}
