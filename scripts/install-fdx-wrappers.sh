#!/bin/bash
# install-fdx-wrappers.sh — IMP18 / candidata C23
# Instala wrappers fdx-* em PATH que imprimem orientacao no stdout e saem 127.
# Idempotente: reexecutar sobrescreve. NUNCA cria um wrapper chamado exactamente 'fdx'.
set -euo pipefail

DEST="${1:-${FDX_WRAPPER_DIR:-$HOME/.local/bin}}"
mkdir -p "$DEST"

NOMES=(
  fdx-batch
  fdx-context
  fdx-decisions
  fdx-diff
  fdx-git
  fdx-graph
  fdx-grep
  fdx-impact
  fdx-lint
  fdx-ls
  fdx-outline
  fdx-read
  fdx-search
  fdx-test
  fdx-tree
  fdx-validate
  fdx-worktree
)

for nome in "${NOMES[@]}"; do
  install -m 755 /dev/null "$DEST/$nome"
  cat > "$DEST/$nome" <<'WRAPPER_EOF'
#!/bin/sh
# wrapper C23/IMP18 — nao e um binario; ver dispatch/tests/fdx-mcp-wrapper-contract.test.py
name="$(basename "$0")"
case "$name" in
  fdx-grep) alt="/bin/grep" ;;
  fdx-read) alt="cat/sed" ;;
  fdx-ls)   alt="ls" ;;
  fdx-tree) alt="find" ;;
  fdx-git)  alt="git --no-pager" ;;
  *)        alt="grep/cat/sed e as nativas do shell" ;;
esac
printf '%s\n' \
  "$name: ferramenta MCP — não é um binário. No bash usa $alt; a tool $name chama-se pelo sistema de tools." \
  "AGENTS.md §Ferramentas: MCP não é binário — e sai com 127: um '2>/dev/null' a seguir NÃO transforma isto em resultado vazio de pesquisa."
exit 127
WRAPPER_EOF
  chmod 755 "$DEST/$nome"
done

echo "install-fdx-wrappers: 17 wrappers em $DEST"
