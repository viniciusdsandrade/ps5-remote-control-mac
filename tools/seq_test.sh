#!/usr/bin/env bash
# Sequência longa de direcional numa sessão só (9 toques, 18 eventos: passa da janela de histórico):
# → → → ↓ ↑ ← ← ←, com captura depois de cada toque. Se nenhum evento se perder nem se repetir, o foco
# volta exatamente à posição inicial. Começa por uma sessão de normalização (○ numa sessão nova).
# Uso: tools/seq_test.sh VARIANTE SAIDA_DIR   (VARIANTE: build/ps5ctl-VARIANTE)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
V="${1:?uso: seq_test.sh VARIANTE SAIDA_DIR}"; OUT="${2:?uso: seq_test.sh VARIANTE SAIDA_DIR}"
BIN="build/ps5ctl-$V"
[[ "$V" == "main" ]] && BIN="build/ps5ctl"
[[ -x "$BIN" ]] || { echo "falta $BIN" >&2; exit 2; }
mkdir -p "$OUT"
"$BIN" script --out "$OUT/norm" "wait 1" "press circle" "wait 0.5" > "$OUT/norm.log" 2>&1
steps=("wait 1" "shot s0_inicio")
names=(s0_inicio)
i=1
for move in right right right down up left left left; do
  steps+=("press $move" "wait 0.7" "shot s${i}_$move")
  names+=("s${i}_$move")
  i=$((i + 1))
done
"$BIN" script --out "$OUT/seq" "${steps[@]}" > "$OUT/seq.log" 2>&1
echo "$V: exit=$?"
grep -E 'HIST' "$OUT/seq.log" | sed -E 's/^\[chiaki info\] //' > "$OUT/seq.hist"
tools/contact_grid.sh "$OUT/seq" 3 "${names[@]}"
