# ps5-remote-control

App para Mac (Apple Silicon) que funciona como um controle de PS5 na tela: você clica nos botões de um
DualSense virtual e o PS5 recebe como se fosse um controle. Usa o protocolo do **Uso remoto** (Remote Play)
pela biblioteca aberta [chiaki-ng](https://github.com/chiaki-ng/chiaki-ng), na sua rede local, sem hardware
extra. O volume e o mudo da TV LG vêm do projeto `lg-roap-control`.

O plano completo, os riscos e o que já foi medido estão em [PLANO_MAC.md](PLANO_MAC.md).

## Regra de ouro: só mouse

O app obedece **só ao mouse**, clicando nos botões da janela. Nenhuma tecla vira botão do PS5 nem comando
da TV. Veja a seção 7.2 do plano e o teste abaixo (`--selftest-input`).

## Como funciona, em uma frase

O Mac abre uma sessão de Uso remoto **sem áudio nem vídeo** só para mandar o estado do controle. O PS5 não
deixa assistir a serviços de vídeo durante o Uso remoto: com uma sessão aberta, a imagem dos apps de
streaming fica escura na TV (volta uns 3 s depois que a sessão fecha). Por isso o app abre a sessão quando
você aperta algo e a solta sozinho, mais rápido quando há um app de vídeo na frente.

## Requisitos

- Mac com Apple Silicon, macOS 14 ou mais novo, Xcode (ferramentas de linha de comando) e Homebrew.
- PS5 na mesma rede, com *Configurações › Sistema › Uso remoto › Ativar o Uso remoto* ligado.
- Para ligar o PS5 pelo app: *Configurações › Sistema › Economia de energia › Recursos disponíveis no modo
  de repouso*: **Continuar conectado à Internet** e **Habilitar opção de ligar o PS5 a partir da rede**.
- Para os testes com capturas de tela: `ffmpeg` (`brew install ffmpeg`).

## Compilar e instalar

```bash
git submodule update --init vendor/chiaki-ng      # a biblioteca, em commit fixo
scripts/build_chiaki.sh                           # só a libchiaki, tudo estático (build/chiaki)
scripts/build_ps5ctl.sh                           # CLI de prova e de testes (build/ps5ctl)
scripts/build_app.sh                              # app "Controle PS5" em ~/Applications + atalho na Mesa
NO_INSTALL=1 scripts/build_app.sh                 # só compila, sem instalar
```

O volume, o mudo e o "Ligar tudo" pela TV vêm de um projeto irmão de controle da TV LG (`lg-roap-control`, fora
deste repositório). Se ele estiver ao lado deste (ou em `LG_ROAP_CONTROL_DIR`), o app compila com a TV; se não,
compila com `mac_app/TVStub` e funciona só com o PS5.

## App do iPhone (em desenvolvimento)

O mesmo controle no iPhone, com o mesmo motor (`shared/`). Só para instalação pessoal pelo Xcode: a licença
AGPL do chiaki-ng não convive com os termos da App Store, e com uma conta Apple gratuita cada instalação vale
7 dias (e cabem três apps assim por aparelho).

```bash
brew install xcodegen
cp ios_app/Local.xcconfig.example ios_app/Local.xcconfig   # Team ID e bundle id próprios (ficam fora do Git)
scripts/build_chiaki_ios.sh                                # a libchiaki para iPhone e Simulador (XCFramework)
scripts/build_ios.sh simulator                             # compila para o Simulador
scripts/build_ios.sh install --launch                      # compila, assina, instala e abre no iPhone
```

Diferenças em relação ao Mac, todas pelas regras de rede local do iOS (nota técnica TN3179 da Apple):
- **Sem broadcast.** Mandar broadcast exige uma permissão especial da Apple. O app pergunta ao endereço salvo e,
  se o console ficar em silêncio, sonda um a um os endereços da sub-rede (no máximo um /24), no máximo uma vez a
  cada 30 s em segundo plano.
- **Só em primeiro plano.** Ao sair do app ou bloquear a tela, a sessão é solta; o primeiro toque reabre.
- **Pareamento no Keychain**, só neste aparelho (não sincroniza pelo iCloud).
- **Só toque.** Um teclado físico nunca comanda nada (`ios_app/Guard`).

## Parear (uma vez)

No app, o assistente guia o processo. Pela linha de comando:

```bash
build/ps5ctl account-id                           # login da Sony no navegador; cole a URL; imprime o ID da conta
build/ps5ctl pair --pin 12345678 --account-id ID  # PIN de "Emparelhar dispositivo" no PS5
```

O pareamento fica em `~/.config/ps5_remote_control/host.json` (permissão 0600; as chaves dão controle do
PS5 a quem as tiver na rede local). **Esquecer o pareamento não tem volta**: o app pede confirmação.

## `ps5ctl`

```
discover | status | account-id | pair | wake | press BOTÃO | hold BOTÃO MS | home | standby | bench |
script PASSO... | set-login-pin | forget          (--ds4, --host IP, -v)
```

`ps5ctl script` abre uma sessão **com vídeo**, executa passos e salva capturas da tela do PS5 (decodificadas
com o ffmpeg), para ver o efeito de cada botão sem olhar a TV:

```bash
build/ps5ctl script --out /tmp/teste "shot antes" "press right" "shot depois"
tools/contact_sheet.sh /tmp/teste antes depois    # as duas lado a lado em /tmp/teste/contato.jpg
```

Passos: `wait S`, `shot NOME`, `press BOTÃO [ms]`, `hold BOTÃO MS`, `home`, `stick X Y`, `stickoff`. Com app de
streaming na frente a captura sai **preta** (conteúdo protegido; isso não é contornado).

## Testes

- `"Controle PS5" --selftest-input`: posta teclas e um clique simulados pelo caminho real de eventos e
  confere que a janela descarta toda tecla, que nenhum comando passa durante teclas e que o clique passa.
  Roda em modo de teste (nada vai ao PS5 nem à TV) e **sempre** com `PS5_CONFIG_DIR` apontando para uma pasta
  de mentira:

  ```bash
  C=$(mktemp -d); printf '%s\n' '{"hostID":"DUMMY","nickname":"TESTE","mac":"00:00:00:00:00:00","lastAddress":"127.0.0.1","registKey":"deadbeef","rpKeyHex":"00112233445566778899aabbccddeeff","rpKeyType":0,"accountID":"AAAAAAAAAAA=","pairedAt":"2026-10-18T00:00:00Z"}' > "$C/host.json"
  PS5_CONFIG_DIR="$C" "$HOME/Applications/Controle PS5.app/Contents/MacOS/Controle PS5" --selftest-input
  ```

- `"Controle PS5" --selftest-live`: usa o console de verdade pela política do próprio app (fila do primeiro
  comando, soltura por inatividade, intervalo entre sessões) com três toques de PS. A Central de Controle
  deve terminar no estado oposto ao inicial.
- `tools/cc_toggle_test.sh VARIANTE SAIDA [MS] [RODADAS]`: alterna PS e ○ várias vezes numa sessão e conta as
  falhas de cada botão pelo brilho das capturas (precisa do PS5 na tela inicial). `VARIANTE` = `main` para
  `build/ps5ctl`; `PS5CTL_FLAGS=--ds4` compara o modo DualShock 4.
- `tools/seq_test.sh VARIANTE SAIDA`: → → → ↓ ↑ ← ← ← numa sessão; o foco deve voltar ao ponto de partida.
  `tools/contact_grid.sh` monta a grade das capturas.
- `scripts/lib_variant.sh NOME COMMIT` (com `RESEND_COUNT=N` opcional): gera `build/ps5ctl-NOME` ligado à
  biblioteca num commit à escolha, com o registro dos pacotes de histórico de botões, para comparar versões
  (PLANO_MAC.md, seção 13). `tools/ab_test.sh` faz o teste rápido de PS seguido de ○ numa variante.

## Estrutura

```
vendor/chiaki-ng/    biblioteca (submódulo em commit fixo)
scripts/             build_chiaki, build_ps5ctl, build_app, lib_variant
tools/               ps_discover.py (sondagem), contact_sheet.sh, contact_grid.sh, cc_toggle_test.sh, seq_test.sh, ab_test.sh
mac_app/CChiaki/     bridging header da biblioteca
shared/Engine/       motor sem interface (usado pelos apps): descoberta, acordar, pareamento, sessão, estado do controle
shared/Theater/      HomeTheater: modos de clique, rota CEC, "Ligar tudo" e "Desligar tudo"
mac_app/CLI/         ps5ctl
mac_app/UI/          app SwiftUI, trava de teclado (InputGuard) e autotestes (teclado e ao vivo)
mac_app/Icon/        make_icon.swift: o ícone (um DualSense) desenhado em código; o build gera o .icns (Mac) e o PNG do iPhone
shared/UI/           o desenho do DualSense em SwiftUI, usado pelos dois apps
ios_app/             app do iPhone: project.yml (XcodeGen), Platform, Guard (só toque), UI e testes
```

## Privacidade

Nada neste repositório identifica o dono ou a casa: endereços de exemplo usam a faixa de documentação
`192.0.2.x`, MACs e nomes de console são marcadores, e pareamento, chaves e configuração ficam só em
`~/.config` no Mac de quem usa. `scripts/verificar-privacidade.sh` confere isso antes de cada commit e push;
quem publica uma cópia deve manter, fora do repositório, uma segunda auditoria com os próprios valores reais.

## Licença

Copyright (C) 2026 Controle PS5 contributors.

**AGPL-3.0-only**, com a permissão adicional para ligar com a OpenSSL ([LICENSE](LICENSE)). O código do
protocolo vem do [chiaki-ng](https://github.com/chiaki-ng/chiaki-ng), também AGPL-3.0: quem distribuir o app
precisa oferecer o código-fonte completo nos mesmos termos.
