# _lib-trusted-mcp.sh — sourced library for quarantine-pack.
# DO NOT execute directly. Source from wrap-mcp-output.sh.
#
# Exposes two functions over the trusted-MCP allowlist file
# (~/.claude/quarantine.d/trusted-mcp-allowlist.txt by default):
#
#   is_trusted_mcp <tool_name> <allowlist_path>
#       Returns 0 if tool_name has an exact-prefix match against any
#       non-comment, non-blank line in the file. Missing file → fail-closed
#       (return 1) per TM7 — never silently trust everything on misconfig.
#
#   matched_trusted_namespace <tool_name> <allowlist_path>
#       Echoes the matched namespace prefix on stdout (empty when no match).
#
# Functions never call `exit`; mirrors the _lib-audit-classify.sh discipline.

is_trusted_mcp() {
  local tool="$1" file="$2"
  [ -z "$tool" ] && return 1
  [ -f "$file" ] || return 1
  local line ns
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    ns="${line%%[[:space:]]*}"
    [ -z "$ns" ] && continue
    case "$tool" in "${ns}"*) return 0 ;; esac
  done < "$file"
  return 1
}

matched_trusted_namespace() {
  local tool="$1" file="$2"
  [ -f "$file" ] || { echo ""; return; }
  local line ns
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    ns="${line%%[[:space:]]*}"
    [ -z "$ns" ] && continue
    case "$tool" in "${ns}"*) echo "$ns"; return ;; esac
  done < "$file"
  echo ""
}
