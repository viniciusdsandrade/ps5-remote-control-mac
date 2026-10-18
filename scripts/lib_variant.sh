#!/usr/bin/env bash
# Gera build/ps5ctl-NOME: o ps5ctl ligado à libchiaki num commit/tag à escolha, com o registro dos
# pacotes de histórico de botões ligado ("HIST t=... seq=... : bytes"). Serve para comparar versões da
# biblioteca no mesmo teste (veja PLANO_MAC.md, seção 13). Usa uma cópia de trabalho à parte
# (build/src-838), então o submódulo fixado em vendor/chiaki-ng não é tocado.
#
# Uso: scripts/lib_variant.sh NOME COMMIT_OU_TAG
set -euo pipefail

NAME="${1:?uso: lib_variant.sh NOME COMMIT_OU_TAG}"
REF="${2:?uso: lib_variant.sh NOME COMMIT_OU_TAG}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK="$PROJECT_DIR/build/src-838"
BUILD="$PROJECT_DIR/build/chiaki-838"

if [[ ! -d "$WORK" ]]; then
  git -C "$PROJECT_DIR/vendor/chiaki-ng" worktree add -f "$WORK" "$REF"
fi

echo "==> Copia de trabalho em $REF"
git -C "$WORK" checkout -q -f "$REF"
git -C "$WORK" log -1 --format='    %h %ad %s' --date=short
git -C "$WORK" submodule update --init --depth 1 third-party/nanopb third-party/jerasure third-party/gf-complete third-party/curl >/dev/null

echo "==> Aplicando o registro dos pacotes de histórico"
python3 -I - "$WORK/lib/src/feedbacksender.c" <<'EOF'
import re, sys, pathlib
path = pathlib.Path(sys.argv[1])
text = path.read_text()
if "<stdio.h>" not in text:
    text = text.replace("#include <string.h>\n", "#include <string.h>\n#include <stdio.h>\n", 1)
match = re.search(r"static void feedback_sender_send_history_packet\(([^)]*)\)\n\{\n", text)
if not match:
    sys.exit("função feedback_sender_send_history_packet não encontrada")
has_count = "event_count" in match.group(1)
log = (
    "\t{\n"
    "\t\tchar hex[256]; size_t n = 0;\n"
    "\t\tfor(size_t i = 0; i < buf_size && n + 3 < sizeof(hex); i++)\n"
    "\t\t\tn += (size_t)snprintf(hex + n, sizeof(hex) - n, \"%02x \", buf[i]);\n"
    "\t\thex[n] = 0;\n"
    + ("\t\tCHIAKI_LOGI(feedback_sender->log, \"HIST t=%llu seq=%u count=%u len=%zu: %s\", (unsigned long long)chiaki_time_now_monotonic_ms(), (unsigned)feedback_sender->history_seq_num, (unsigned)event_count, buf_size, hex);\n"
       if has_count else
       "\t\tCHIAKI_LOGI(feedback_sender->log, \"HIST t=%llu seq=%u len=%zu: %s\", (unsigned long long)chiaki_time_now_monotonic_ms(), (unsigned)feedback_sender->history_seq_num, buf_size, hex);\n")
    + "\t}\n"
)
text = text[:match.end()] + log + text[match.end():]
path.write_text(text)
print("    registro aplicado" + (" (com contagem de eventos)" if has_count else ""))
EOF

# Opcional: RESEND_COUNT=N troca quantos eventos recentes cada pacote de histórico repete (padrão do
# commit: 4 na v1.10.0, 8 no main de outubro/2026). Serve para testar se os eventos repetidos causam o
# problema do ○ depois de outro botão.
if [[ -n "${RESEND_COUNT:-}" ]]; then
  python3 -I - "$WORK/lib/src/feedbacksender.c" "$RESEND_COUNT" <<'EOF2'
import re, sys, pathlib
path = pathlib.Path(sys.argv[1]); text = path.read_text()
new, n = re.subn(r"(#define FEEDBACK_HISTORY_RESEND_EVENT_COUNT )0x[0-9a-fA-F]+", r"\g<1>" + hex(int(sys.argv[2])), text)
if n != 1:
    sys.exit("FEEDBACK_HISTORY_RESEND_EVENT_COUNT não encontrado")
path.write_text(new)
print("    repetição de eventos por pacote: " + sys.argv[2])
EOF2
fi

echo "==> Compilando a biblioteca e o ps5ctl-$NAME"
CHIAKI_SRC_DIR="$WORK" CHIAKI_BUILD_DIR="$BUILD" "$SCRIPT_DIR/build_chiaki.sh" >/dev/null
CHIAKI_SRC_DIR="$WORK" CHIAKI_BUILD_DIR="$BUILD" PS5CTL_OUT="$PROJECT_DIR/build/ps5ctl-$NAME" "$SCRIPT_DIR/build_ps5ctl.sh" >/dev/null
echo "==> Pronto: build/ps5ctl-$NAME"
