#!/usr/bin/env bash
# Teste estatístico de botões: numa sessão só, alterna PS (abre a Central de Controle) e ○ (fecha),
# RODADAS vezes, com captura depois de cada toque. Classifica cada captura como "aberta" ou "fechada"
# pelo brilho da faixa central da imagem (aberta ≈ 32, fechada ≈ 6 a 9) e conta as falhas de cada
# botão comparando com o estado real anterior. Começa numa sessão de normalização (○ numa sessão nova).
# Precisa do PS5 na tela inicial.
# PS5CTL_FLAGS=--ds4 passa opções ao ps5ctl (ex.: anunciar como DualShock 4).
# Uso: tools/cc_toggle_test.sh VARIANTE SAIDA_DIR [SEGURAR_MS=80] [RODADAS=6] [ESPERA_INICIAL_S=1]
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
V="${1:?uso: cc_toggle_test.sh VARIANTE SAIDA_DIR [SEGURAR_MS] [RODADAS] [ESPERA_INICIAL_S]}"
OUT="${2:?uso: cc_toggle_test.sh VARIANTE SAIDA_DIR [SEGURAR_MS] [RODADAS] [ESPERA_INICIAL_S]}"
HOLD="${3:-80}"; ROUNDS="${4:-6}"; FIRST_WAIT="${5:-1}"
BIN="build/ps5ctl-$V"
[[ "$V" == "main" ]] && BIN="build/ps5ctl"
[[ -x "$BIN" ]] || { echo "falta $BIN" >&2; exit 2; }
mkdir -p "$OUT"
"$BIN" ${PS5CTL_FLAGS:-} script --out "$OUT/norm" "wait 1" "press circle" "wait 0.5" > "$OUT/norm.log" 2>&1
steps=("wait $FIRST_WAIT" "shot r00_inicio")
for ((i = 1; i <= ROUNDS; i++)); do
  steps+=("press ps $HOLD" "wait 1.0" "shot r$(printf %02d $i)a_ps" "press circle $HOLD" "wait 1.0" "shot r$(printf %02d $i)b_circulo")
done
"$BIN" ${PS5CTL_FLAGS:-} script --out "$OUT/cc" "${steps[@]}" > "$OUT/cc.log" 2>&1 || { echo "$V: sessão falhou"; tail -3 "$OUT/cc.log"; exit 1; }
python3 -I - "$OUT/cc" "$V${PS5CTL_FLAGS:+ $PS5CTL_FLAGS}" "$HOLD" <<'EOF'
import os, subprocess, sys
folder, variant, hold = sys.argv[1], sys.argv[2], sys.argv[3]
ffmpeg = "/opt/homebrew/bin/ffmpeg"
def bright(path):
    raw = subprocess.run([ffmpeg, "-loglevel", "error", "-i", path, "-vf",
                          "crop=iw:ih*0.45:0:ih*0.15,scale=1:1,format=gray", "-f", "rawvideo", "-"],
                         capture_output=True).stdout
    return raw[0] if raw else -1
shots = sorted(f[:-4] for f in os.listdir(folder) if f.endswith(".jpg"))
states, line = [], []
for name in shots:
    b = bright(os.path.join(folder, name + ".jpg"))
    is_open = b >= 18
    states.append((name, is_open))
    line.append(f"{name.split('_')[0]}:{'A' if is_open else 'f'}({b})")
ps_ok = ps_fail = circ_ok = circ_fail = circ_noop = 0
for (prev_name, prev_open), (name, now_open) in zip(states, states[1:]):
    if name.endswith("_ps"):
        if now_open != prev_open: ps_ok += 1
        else: ps_fail += 1
    else:
        if not prev_open:
            circ_noop += 1            # ○ com a Central fechada: nada a verificar
        elif not now_open: circ_ok += 1
        else: circ_fail += 1
print(f"{variant} (toque {hold} ms): PS {ps_ok} ok / {ps_fail} falha · ○ {circ_ok} ok / {circ_fail} falha"
      + (f" ({circ_noop} sem efeito esperado)" if circ_noop else ""))
print("   " + " ".join(line))
EOF
