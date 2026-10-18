#!/usr/bin/env bash
# Junta capturas do `ps5ctl script` lado a lado numa imagem só (DIR/contato.jpg), para ler vários
# resultados de uma vez. Uso: tools/contact_sheet.sh DIR nome1 nome2 ...
set -euo pipefail

DIR="${1:?uso: contact_sheet.sh DIR nome1 nome2 ...}"
shift
[[ $# -ge 1 ]] || { echo "informe os nomes das capturas" >&2; exit 2; }

FFMPEG="$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)"
args=()
filter=""
inputs=""
i=0
for name in "$@"; do
  args+=(-i "$DIR/$name.jpg")
  filter+="[$i]scale=360:-1[v$i];"
  inputs+="[v$i]"
  i=$((i + 1))
done
"$FFMPEG" -loglevel error -y "${args[@]}" -filter_complex "${filter}${inputs}hstack=inputs=$i" -q:v 3 "$DIR/contato.jpg"
echo "$DIR/contato.jpg"
