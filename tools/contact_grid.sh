#!/usr/bin/env bash
# Junta capturas do `ps5ctl script` numa grade (DIR/grade.jpg), COLS por linha, na ordem dada.
# Uso: tools/contact_grid.sh DIR COLS nome1 nome2 ...
set -euo pipefail

DIR="${1:?uso: contact_grid.sh DIR COLS nome1 nome2 ...}"
COLS="${2:?uso: contact_grid.sh DIR COLS nome1 nome2 ...}"
shift 2
FFMPEG="$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)"
names=("$@")
count=${#names[@]}
args=()
filter=""
for ((i = 0; i < count; i++)); do
  args+=(-i "$DIR/${names[$i]}.jpg")
  filter+="[$i]scale=480:270[v$i];"
done
# Completa a última linha com quadros pretos para a grade ficar retangular.
rows=$(( (count + COLS - 1) / COLS ))
total=$(( rows * COLS ))
for ((i = count; i < total; i++)); do
  filter+="color=c=black:s=480x270:d=1[v$i];"
done
row_labels=""
for ((r = 0; r < rows; r++)); do
  inputs=""
  for ((c = 0; c < COLS; c++)); do inputs+="[v$((r * COLS + c))]"; done
  filter+="${inputs}hstack=inputs=$COLS[r$r];"
  row_labels+="[r$r]"
done
if (( rows > 1 )); then
  filter+="${row_labels}vstack=inputs=$rows[out]"
else
  filter+="[r0]copy[out]"
fi
"$FFMPEG" -loglevel error -y "${args[@]}" -filter_complex "$filter" -map "[out]" -frames:v 1 -q:v 3 "$DIR/grade.jpg"
echo "$DIR/grade.jpg"
