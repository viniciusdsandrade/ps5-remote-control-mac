#!/usr/bin/env bash
# Compara o ○ depois de PS numa versão da biblioteca (build/ps5ctl-VARIANTE, de scripts/lib_variant.sh).
# 1) sessão de normalização: um ○ numa sessão nova fecha a Central de Controle se ela estiver aberta;
# 2) sessão de teste: PS (abre a Central) e ○ (deveria fechar), com captura depois de cada passo.
# Uso: tools/ab_test.sh VARIANTE SAIDA_DIR
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
V="${1:?uso: ab_test.sh VARIANTE SAIDA_DIR}"; OUT="${2:?uso: ab_test.sh VARIANTE SAIDA_DIR}"
BIN="build/ps5ctl-$V"
[[ -x "$BIN" ]] || { echo "falta $BIN (scripts/lib_variant.sh)" >&2; exit 2; }
mkdir -p "$OUT"
"$BIN" script --out "$OUT/norm" "wait 1" "press circle" "wait 0.5" > "$OUT/norm.log" 2>&1
"$BIN" script --out "$OUT/t1" "wait 1" "shot a_antes" "press ps" "wait 1.2" "shot b_apos_ps" "press circle" "wait 1.5" "shot c_apos_circulo" > "$OUT/t1.log" 2>&1
echo "$V: exit=$?"
grep -E 'HIST' "$OUT/t1.log" | sed -E 's/^\[chiaki info\] //' > "$OUT/t1.hist"
tools/contact_sheet.sh "$OUT/t1" a_antes b_apos_ps c_apos_circulo
