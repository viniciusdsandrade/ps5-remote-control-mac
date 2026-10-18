#!/usr/bin/env bash
# Auditoria genérica de privacidade: roda antes de cada commit e push.
# Falha se algum arquivo do repositório tiver dado que identifique o dono ou a casa (IPs de rede local,
# MACs, e-mails, pastas de usuário, nome padrão de console, ID de conta PSN, arquivos de pareamento,
# imagens) ou se o histórico tiver autor fora do e-mail noreply do GitHub ou datas fora de UTC.
# Os valores reais de cada casa ficam numa segunda auditoria, local, fora do repositório.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail=0
files=()
while IFS= read -r f; do files+=("$f"); done < <(git ls-files -co --exclude-standard | grep -v '^vendor/')

check() { # descrição, padrão, [padrão permitido]
  local what="$1" pattern="$2" allow="${3:-}" hits
  hits=$(grep -n -I -E -- "$pattern" "${files[@]}" 2>/dev/null || true)
  if [[ -n "$allow" && -n "$hits" ]]; then hits=$(grep -v -E -- "$allow" <<< "$hits" || true); fi
  if [[ -n "$hits" ]]; then
    echo "FALHA  $what"
    sed 's/^/         /' <<< "$hits" | head -20
    fail=1
  else
    echo "ok     $what"
  fi
}

check "IPs de rede local (use 192.0.2.x)" \
  '(^|[^0-9.])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3})([^0-9]|$)'
check "MACs (use aa:bb:cc:dd:ee:ff)" \
  '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' 'aa:bb:cc:dd:ee:ff|00:00:00:00:00:00'
check "host-id de console (12 hexadecimais)" \
  '(^|[^0-9A-Za-z])[0-9A-F]{12}([^0-9A-Za-z]|$)' 'AABBCCDDEEFF'
check "e-mails" \
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' 'users\.noreply\.github\.com|@example\.(com|org)|fsf\.org'
check "pastas de usuário" '/Users/[A-Za-z]|/home/[a-z]'
check "nome padrão de console (use PS5-123)" 'PS5-[0-9]{3}' 'PS5-123'
# ID de conta PSN: base64 de 8 bytes = 11 caracteres e '='. Procura a palavra inteira (letras, números, + / _ e '='),
# não um trecho de palavra maior como CMAKE_OSX_ARCHITECTURES=. Mostra só arquivo:linha, nunca o valor.
psn_hits=$(grep -n -I -o -E '[A-Za-z0-9+/_]+=' "${files[@]}" 2>/dev/null \
  | grep -E ':[A-Za-z0-9+/]{11}=$' | grep -v -F 'AAAAAAAAAAA=' | sed -E 's/:[^:]*$//' || true)
if [[ -n "$psn_hits" ]]; then
  echo "FALHA  ID de conta PSN (base64 de 8 bytes)"
  sed 's/^/         /' <<< "$psn_hits" | head -20
  fail=1
else
  echo "ok     ID de conta PSN (base64 de 8 bytes)"
fi

bad_files=$(printf '%s\n' "${files[@]}" | grep -i -E '\.(png|jpe?g|heic|gif|mov|mp4|h264)$|(^|/)(host|androidtv|config)\.json$|\.env$|\.jks$' || true)
if [[ -n "$bad_files" ]]; then
  echo "FALHA  imagens, vídeos ou arquivos de pareamento no repositório"
  sed 's/^/         /' <<< "$bad_files"
  fail=1
else
  echo "ok     sem imagens, vídeos ou arquivos de pareamento"
fi

if git rev-parse --verify -q HEAD > /dev/null; then
  bad_authors=$(git log --format='%ae%n%ce' | sort -u | grep -v -E '@users\.noreply\.github\.com$' || true)
  bad_dates=$(git log --format='%ai%n%ci' | grep -v -E '\+0000$' || true)
  if [[ -n "$bad_authors" ]]; then echo "FALHA  autor ou committer fora do noreply do GitHub"; fail=1; else echo "ok     autores com e-mail noreply"; fi
  if [[ -n "$bad_dates" ]]; then echo "FALHA  datas de commit fora de UTC (use TZ=UTC)"; fail=1; else echo "ok     datas de commit em UTC"; fi
fi

if (( fail )); then echo "Auditoria de privacidade: FALHOU"; exit 1; fi
echo "Auditoria de privacidade: ok"
