# Controle PS5 no Mac: viabilidade e plano de implementação

**Data:** 18/10/2026 (revisão 2, no mesmo dia; o que mudou está na seção 12)
**Escopo desta etapa:** só o app desktop para macOS (Apple Silicon). iPhone e Android ficam para depois. O
motor que conversa com o PS5 fica separado da interface, para ser reaproveitado.
**Status:**
- Viabilidade confirmada na rede desta casa: o PS5 responde ao protocolo a partir do Mac.
- Os fatos sobre a biblioteca foram conferidos no código-fonte do chiaki-ng (commit `c8bea26`), não só em
  relatórios.
- Ainda dependem do teste da Fase 0, que precisa de você na frente da TV: o pareamento, a sessão, o efeito
  na TV e o comportamento do HDMI-CEC.
- **Nada foi implementado.** Este documento espera a sua revisão (seção 12.2 lista as decisões em aberto).

---

## 1. Resposta curta

**É viável só com software, sem hardware novo e sem custo, com uma ressalva para streaming.**

- **Como funciona:**
  - O Mac conversa com o PS5 pelo mesmo protocolo do app oficial **PS Remote Play** (no menu do PS5,
    "Uso remoto").
  - Ele pareia uma vez com o código de 8 dígitos que aparece na TV.
  - Depois abre sessões em que manda o estado de um DualSense: direcional, ✕ ○ □ △, L1/R1, L2/R2, L3/R3,
    Create, Options, PS, touchpad e os dois analógicos. Para o PS5, é mais um controle.
  - O mesmo protocolo tira o console do repouso e o coloca em repouso.
  - O protocolo é mantido na biblioteca em C do projeto aberto **chiaki-ng**, que tem build oficial para
    Mac arm64 e um modo "só controle": a sessão abre sem decodificar vídeo nem áudio.
- **A ressalva:** a Sony não deixa assistir a serviços de vídeo nem tocar música durante o Uso remoto.
  - Com uma sessão aberta, o vídeo dos apps de streaming fica preto **também na TV**.
  - O vídeo continua rodando e os menus continuam visíveis. A imagem volta cerca de 3 s depois que a
    sessão fecha. O que acontece com o som não está documentado.
  - Um app parecido relata que o PS5 exige cerca de 9 s entre uma sessão e a próxima. O chiaki-ng fecha a
    sessão de forma limpa, então esse intervalo pode ser menor aqui; é para medir, não para assumir.
  - Por isso o app não fica conectado o tempo todo: abre a sessão enquanto você navega e a solta quando
    você dá play.
- **O complemento que contorna a ressalva: HDMI-CEC.**
  - O PS5 aceita pelo CEC as teclas de direcional, ✕ ("select"), ○ ("back"), PS ("root menu") e
    liga/desliga. Há relatos de play e pausa funcionando em alguns apps.
  - O CEC não abre sessão, então não escurece nada.
  - Se a sua LG repassar pelo SIMPLINK as teclas que o app da TV já manda pela rede, pausar e avançar
    durante o filme funciona sem hardware. Isso é um teste de 5 minutos.
  - Se a TV não repassar, a alternativa é um Raspberry Pi atrás da TV (US$ 35 a 60), opcional.
- **Recomendação:**
  1. Fazer a Fase 0, cerca de 1 h com o app oficial no iPhone.
  2. Com os tempos medidos, construir as Fases 1 a 3: o app com a sessão de Uso remoto e a integração
     com a TV.

---

## 2. O que já foi verificado nesta casa (18/10/2026)

| Item | Resultado |
|---|---|
| Descoberta do Uso remoto a partir do Mac (UDP 9302, pacote `SRCH`, script `tools/ps_discover.py`) | O PS5 respondeu na hora: `host-name: PS5-123`, `host-type: PS5`, IP **192.0.2.18**, `HTTP/1.1 200 Ok` (ligado), `system-version: 14100003` (sistema 14.10). Não veio `running-app-name`: ou o PS5 estava na tela inicial, ou ele só informa para jogos (a Fase 0 confere) |
| Porta TCP 9295 do PS5 (pareamento e início de sessão) | aberta |
| Mac | Apple Silicon, macOS 26.7.1, Wi-Fi 192.0.2.35, Xcode 27.1, Swift 6.4, Homebrew 7 |
| Dependências da biblioteca já instaladas | `openssl@3` 3.6.4 (`libcrypto.a` e `libssl.a`) e `json-c` 0.19 (`libjson-c.a`) |
| Falta instalar (Fase 1) | `cmake`, `ninja`, `pkgconf`, `miniupnpc` 2.3.3 e `libevent` 2.1.13 (ambos com bottle para macOS 26 arm64), `protobuf@29` (descontinuado no Homebrew desde 31/03/2026, mas instalável até 31/03/2027) e um venv de Python com `protobuf>=5,<6` |
| Projeto da TV | `lg-roap-control/mac_app`: SwiftUI compilado com `swiftc` + `build_app.sh`, assinatura ad-hoc com bundle id fixo, instalado em `~/Applications`. O app do PS5 segue o mesmo molde e reaproveita `LGTVClient.swift` e `TVBoxLink.swift` |

Ainda não verificado, porque precisa de você:
- o pareamento com o código;
- uma sessão aberta;
- o que a TV mostra (e toca) durante a sessão;
- o repasse de teclas pelo SIMPLINK e a interação do Link HDMI do PS5 com a TV Box.

---

## 3. Como funciona

```
Mac "Controle PS5"                                       PS5-123 · 192.0.2.18
 │ UDP 9302  SRCH ──────────────────────────────────▶  "200 Ok" (ligado) ou "620 Server Standby"
 │ UDP 9302  WAKEUP + credencial ───────────────────▶  sai do repouso (com o Link HDMI, pode ligar a TV)
 │ UDP/TCP 9295  /sie/ps5/rp/sess/rgst (PIN, 1 vez) ─▶ devolve RegistKey + RP-Key, guardados no Mac
 │ TCP 9295  /sie/ps5/rp/sess/init e /ctrl ─────────▶  abre a sessão
 │ UDP 9297  teste de rede (MTU, RTT), adaptado ao RTT: fração de segundo na rede local
 │ UDP 9296  Takion, cifrado ◀──────────────────────▶  estado do DualSense a cada mudança (e a cada 200 ms);
 │                                                      repouso, "ir para o início", eventos
```

- **Pareamento (uma vez).** Precisa de duas coisas:
  - o ID da conta PSN do usuário do PS5 (8 bytes em base64);
  - o código de 8 dígitos de *Configurações › Sistema › Uso remoto › Emparelhar dispositivo*.

  O ID vem de um login na Sony. O app abre a página de login no navegador padrão; depois do login, a Sony
  redireciona para uma URL que contém um `code`. Você cola essa URL no app, que troca o `code` pelo ID em
  duas chamadas HTTPS (o mesmo fluxo do `scripts/psn-account-id.py` do chiaki-ng). Quem já tiver o ID pode
  colar direto. O app guarda só o ID, nunca a senha.
- **Sessão "só controle".** O cliente desliga áudio e vídeo (`audio_video_disabled = 3`). O PS5 continua
  transmitindo em 360p, mas a biblioteca descarta os pacotes logo na chegada. Não precisa de FFmpeg nem de
  decodificador.
- **Ligar.** Pacote `WAKEUP` com a RegistKey, lida como hexadecimal e enviada em decimal. Funciona se o
  repouso mantiver a rede ligada (seção 10).
- **Repouso.** Comando dentro de uma sessão aberta.
- **Início.** Segurar PS por cerca de 1 s leva à tela inicial, como no controle. A biblioteca também tem um
  comando "ir para o início" (`chiaki_session_go_home`), que a Fase 1 testa no PS5 como alternativa.

---

## 4. Caminhos avaliados

| Caminho | Veredito | Resumo |
|---|---|---|
| **Uso remoto com a biblioteca do chiaki-ng** | ✅ **base do app** | Todos os botões, ligar e repouso, sem hardware. Escurece o streaming na TV enquanto conectado, então a sessão abre sob demanda |
| **HDMI-CEC pela própria TV** (ROAP → SIMPLINK → PS5) | ✅ sem sessão aberta | Testado em 18/10/2026: com **nenhuma** sessão de Uso remoto aberta, ←, →, ↓ e OK mandados pela rede para a TV chegaram ao PS5 (moveram o foco, abriram o YouTube, selecionaram itens). Com uma sessão aberta, as mesmas teclas são ignoradas. Uma tecla OK se perdeu (falha ocasional). Não escurece nada |
| HDMI-CEC com hardware (Raspberry Pi 4/5 com `cec-ctl`, ou adaptador Pulse-Eight USB-CEC) | ⚪ opcional | US$ 35 a 60, mesmas teclas do item acima. O Pulse-Eight vai no cabo HDMI, o que não combina com notebook. O Pi fica atrás da TV e recebe os comandos pela rede |
| App oficial PS Remote Play no Mac | ❌ como controle | Pede um DualSense ligado ao Mac por cabo. O painel na tela só tem Create, PS e Options, e o teclado serve para digitar e para jogos que aceitam teclado, não para navegar. E também é Uso remoto, com o mesmo escurecimento |
| Mac como teclado ou controle Bluetooth | ❌ | No macOS, o `bluetoothd` fica com os canais HID e o Mac só abre conexões de saída. O PS5 espera conectar ele mesmo, então não deve funcionar. O Typeeto parou em 2022 e a própria loja exclui PS3 e PS4. Teclado também não tem botão PS |
| Placa (ESP32, Pico) fingindo ser DualSense ou DualShock 4 | ❌ na prática | O PS5 autentica controles e confere de novo a cada cerca de 30 s. Só funciona por USB, com um adaptador licenciado fazendo a autenticação e firmware próprio. Por Bluetooth não há projeto que funcione |
| Controle virtual no macOS (CoreHID) + app oficial | ❌ | Exige a permissão `com.apple.developer.hid.virtual.device`, que a Apple concede sob pedido, e há pedidos parados há meses. Com assinatura ad-hoc, só desligando SIP/AMFI. E continua sendo Uso remoto |
| pyremoteplay, playactor, ps5-mqtt | ⚪ referência | O pyremoteplay foi arquivado em 2022, mas ainda funciona: o `keyboard-ds5` (Windows, AGPL) usa ele num controle de PS5 só por teclado, que conecta em cerca de 1 s. playactor e ps5-mqtt só ligam e desligam |
| Abrir um app direto (ex.: Netflix) | ❌ sem API | O PS5 não tem o "Second Screen" do PS4, e o "Jogar no console" do PS App é só para jogos. Resta macro de navegação, que quebra quando a Sony muda o menu |

---

## 5. Limitações e riscos

| # | Ponto | Impacto | Como o plano trata |
|---|---|---|---|
| 1 | **Streaming escurece na TV com sessão aberta.** A Sony lista "Watching video services" e "Playing music" entre o que não funciona junto com o Uso remoto. Um app parecido (`keyboard-ds5`) descreve o efeito: o vídeo continua rodando, os menus aparecem e a imagem volta cerca de 3 s depois de desconectar. O som não está documentado | alto | Sessão só enquanto você navega. Botão "▶ Assistir" manda ✕ e solta a sessão na hora. Em app de vídeo, a sessão é solta sozinha pouco depois de um ✕ (seção 6.3). Pausar e avançar vão pelo CEC, se a Fase 0 confirmar |
| 2 | **Intervalo mínimo entre sessões.** O `keyboard-ds5` relata cerca de 9 s e por isso desligou o modo "conectar a cada comando", pouco confiável. O chiaki-ng fecha a sessão de forma limpa (`disconnect` explícito), o que pode encurtar o intervalo | médio/alto | **Medido em 18/10/2026 com `ps5ctl bench`:** o console recusa ('já em uso') por 6 a 8 s depois de uma sessão fechar, e aceita aos 8 s; conexão em 2,3 a 2,6 s. A política usa 8 s e mostra "pronto em X s" em vez de falhar |
| 3 | Um relato de 2023 diz que o PS Portal não conectava com um app de vídeo aberto | médio | Teste na Fase 0: com a Netflix tocando, a sessão abre? |
| 4 | Só uma sessão de Uso remoto por vez | médio | Avisar "em uso por outro dispositivo" (motivo `RP_IN_USE`) e não insistir |
| 5 | Licença AGPL-3.0 do chiaki-ng | baixo, para uso pessoal | Se um dia distribuir o app, ele inteiro precisa ser AGPL, com o código aberto |
| 6 | Uma atualização do PS5 quebrar o protocolo | baixo/médio | Nenhum caso em 2025 e 2026. Usar commit fixo do chiaki-ng e atualizar quando sair correção |
| 7 | As correções de entrada (#823, #838, #840: eventos perdidos e botão preso) só existem no `main`, não na v1.10.0 | médio | Compilar do `main`, a partir de `c8bea26` |
| 8 | O envio de texto pelo teclado do PS5 existe na biblioteca, mas ninguém confirmou que funciona no PS5 | baixo | Experimental na Fase 4. Se não funcionar, sai |
| 9 | Rede local do macOS: um usuário do chiaki-ng no macOS 15 teve a TCP 9295 bloqueada | médio | App assinado com bundle id fixo e `NSLocalNetworkUsageDescription`, igual ao app da TV |
| 10 | O login Sony é instável e limita tentativas | baixo | O pareamento é feito uma vez só, e há campo para colar o ID pronto |
| 11 | `protobuf@29`, usado só para compilar, será desativado no Homebrew em 31/03/2027. O gerador do nanopb precisa do pacote Python `protobuf` 5.x, compatível com esse `protoc` | baixo | Compilar a biblioteca e guardar os `.a`; trocar quando o chiaki-ng migrar |
| 12 | Um relato antigo diz que ligar um DualSense físico derrubava a sessão | baixo | Teste na Fase 0 |
| 13 | **Link HDMI do PS5 × TV Box.** O CEC do PS5 e o One-Touch Play dependem do "Link de dispositivo HDMI". Com ele ligado, há relatos de PS5 acordando sozinho quando a TV liga, e o "Link de desligamento" põe o PS5 em repouso quando a TV desliga. Hoje a TV Box liga a TV pelo CEC (fluxo "Ligar a TV" do app da TV), o que pode acordar o PS5 junto | médio | Fase 0 testa as duas interações. Se o PS5 acordar quando a TV Box liga a TV, a escolha fica entre aceitar isso (o timer de repouso do PS5 o desliga depois) e desligar o Link HDMI, abrindo mão do CEC e do One-Touch Play. Decisão em aberto (seção 12.2, item D) |
| 14 | Aviso na TV ao conectar. A Sony documenta o pop-up "Uso remoto conectado" só quando outro usuário entra no console; para o mesmo usuário não há documentação | baixo | **Confirmado em 18/10/2026:** ao conectar, a TV mostra o aviso "[usuário] se conectou pelo Uso remoto." e, no canto superior direito, um painel com ícones de controle, microfone e teclado enquanto a sessão está aberta. Existe a opção de ocultar o pop-up em *Configurações › Sistema › Uso remoto* (o painel não) |
| 15 | **Queda da biblioteca com app de vídeo na frente.** Quando o PS5 avisa que a tela não pode ser transmitida, a biblioteca chama um callback sem checar se é nulo. Sem `display_sink`, o processo cai (`SIGSEGV` em `ctrl_connect`). Pegou o `ps5ctl` três vezes em 18/10/2026 | alto | **Corrigido:** `PSSession` instala o `display_sink`. O aviso virou o sinal "app de vídeo na frente" (`videoBlocked`), melhor que adivinhar pelo nome do app |
| 16 | **○ depois de outro botão na mesma sessão.** Em 18/10/2026: ○ numa sessão nova funciona (fecha a Central de Controle); PS curto alterna a Central certo 4 vezes seguidas nas duas versões da biblioteca testadas; mas PS seguido de ○ não fecha a Central (commit atual), e ○ seguido de PS não abre (commit anterior à #840). Só aparece misturando tipos de botão | alto | **Resolvido (seção 13):** a mistura de botões não era a causa (36/36). Toques longos falham mais; o app agora manda toques fixos de 80 ms. Falha residual medida: cerca de 1 em 75 toques |

---

## 6. Arquitetura

### 6.1 Pastas

```
ps5-remote-control/
├── PLANO_MAC.md                ← este plano
├── tools/ps_discover.py        ← sondagem de descoberta (só leitura) usada nesta análise
├── vendor/chiaki-ng/           ← submódulo git em commit fixo (main, a partir de c8bea26)
├── scripts/
│   ├── build_chiaki.sh         ← CMake + Ninja → build/chiaki/{include,lib}
│   └── build_app.sh            ← swiftc + bundle + codesign ad-hoc + ~/Applications (mesmo molde do app da TV)
└── mac_app/
    ├── CChiaki/                ← bridging header + um shim C pequeno (estruturas e callbacks)
    ├── (Engine: hoje em shared/Engine) ← sem SwiftUI: PSDiscovery, PSWake, PSRegistration, PSNAccountID,
    │                             PSSession, PadState, HostStore, CECRoute
    ├── UI/                     ← SwiftUI: PS5RemoteView, DualSensePad, PairingView, SettingsView, MenuBar, KeyMap
    └── AppMain.swift
```

O `build_app.sh` também compila três arquivos do app da TV: `../lg-roap-control/mac_app/LGTVClient.swift`,
`TVBoxLink.swift` e `AndroidTVRemote.swift`. Assim o volume, o mudo, o "ligar a TV" e a rota CEC vêm do app
da TV, sem código duplicado.

### 6.2 Peças

| Peça | O que faz | Em cima de |
|---|---|---|
| `PSDiscovery` | Acha o PS5 e diz se está ligado ou em repouso. Informa o app aberto (`running-app-name`, quando o PS5 manda) e o IP atual, reconhecendo o console pelo `host-id` | `chiaki_discovery_service_*`, com ping a cada 500 ms, como o chiaki-ng |
| `PSWake` | Tira o PS5 do repouso | `chiaki_discovery_wakeup(…, ps5: true)` |
| `PSRegistration` | Transforma PIN + ID da conta em RegistKey, RP-Key, MAC e apelido do console | `chiaki_regist_start` |
| `PSNAccountID` | Abre o login da Sony no navegador padrão, recebe a URL de redirecionamento colada, troca o `code` pelo `user_id` (duas chamadas HTTPS com `URLSession`) e converte em 8 bytes little-endian → base64. Aceita também o ID colado pronto | O mesmo fluxo de `scripts/psn-account-id.py` do chiaki-ng, sem navegador embutido |
| `PSSession` | Sessão só controle. Eventos: conectou, pediu PIN de login, saiu (com motivo). Também repouso e "ir para o início" | `chiaki_session_*` com `audio_video_disabled = 3` |
| `PadState` | Estado do DualSense: toque, segurar, analógicos, gatilhos e touchpad | `ChiakiControllerState` + `chiaki_session_set_controller_state` |
| `CECRoute` | Manda ✕, ○, direcional e play/pausa pela TV (ROAP → SIMPLINK → PS5), sem sessão. Entra só se a Fase 0 confirmar | `LGTVClient.sendKey` |
| `HostStore` | Guarda `~/.config/ps5_remote_control/host.json`, com permissão 0600. As chaves dão controle do PS5 a quem as tiver na rede local, por isso o arquivo é só do usuário | O mesmo padrão do `androidtv.json` do app da TV |
| `PS5Controller` | `@MainActor ObservableObject` que a interface observa; aplica a política de conexão e escolhe a rota de cada tecla | Espelha o `LGTVClient` |

### 6.3 Detalhes que importam

- **Threads.**
  - A biblioteca roda em threads próprias e chama os callbacks nelas.
  - As strings da descoberta e o resultado do pareamento ficam na pilha dessas threads. Copie tudo dentro
    do callback e só depois publique no MainActor.
  - O serviço de descoberta chama o callback com o próprio mutex preso: não chame a API de descoberta de
    dentro dele.
  - `ChiakiSession`, `ChiakiRegist` e `ChiakiDiscoveryService` têm mutex dentro. Aloque no heap, nunca
    mova, e passe o objeto Swift como `user` via `Unmanaged`.
  - No Swift 6, o invólucro é uma `final class … @unchecked Sendable` com lock.
- **Clique, segurar e repetir** (decidido pelos testes de 18/10/2026, seção 13):
  - Cada clique num botão vira um **toque de duração fixa** (80 ms), qualquer que seja a duração do clique.
    Nos testes, toques de 80 ms falharam cerca de 1 vez em 75; toques de 200 a 250 ms, 4 vezes em 41.
  - **Direcional:** segurar o mouse gera toques repetidos (o primeiro na hora, depois de 400 ms um a cada
    160 ms), como a autorrepetição do próprio PS5.
  - **L2/R2:** segurar de verdade (aperta no clique, solta ao largar), porque gatilho analógico precisa.
  - **Início:** PS segurado por **1,5 s**. Com 1 s o PS5 às vezes entendeu como toque curto.
  - A biblioteca manda um evento por mudança e reenvia o último, o que evita botão "preso".
- **Mapeamento.**
  - Create é o bit `SHARE`.
  - Não existe bit de Mute (é o microfone), então ele fica de fora.
  - Faixas: analógicos em int16 (para cima é negativo), gatilhos de 0 a 255, touchpad de 1919×1079.
- **PIN de login do PS5.** Se o usuário do console tiver senha de 4 dígitos, a sessão pede (evento
  `LOGIN_PIN_REQUEST`). O app pergunta uma vez, guarda e manda sozinho nas próximas.
- **Política de conexão** (valores medidos e ajustados em 18/10/2026):
  - **Abertura.** A sessão abre no primeiro comando, acordando o PS5 antes se ele estiver em repouso. Esse
    comando fica na fila e é enviado assim que a sessão abre. Medido: conexão em 2,3 a 2,7 s; um toque
    enviado no mesmo instante em que a sessão abre funciona (8 de 8).
  - **Fechamento fora de apps de vídeo conhecidos:** 30 s sem comando; ou **6 s depois de um ✕** sem outro
    comando, em qualquer app, porque o ✕ costuma ser o play e o PS5 não avisa quando um app de vídeo abre
    no meio da sessão.
  - **Fechamento em apps de vídeo conhecidos:** 5 s depois de um ✕; 20 s depois dos demais comandos.
  - **"▶ Assistir"** manda ✕ e solta a sessão na hora. A imagem volta em cerca de 3 s.
  - **Como o app sabe que é vídeo:** pelo aviso do PS5 de conteúdo que não pode ser transmitido, que chega ao
    conectar quando um app de vídeo já está na frente; ou pelo modo "Assistindo", ligado à mão. A descoberta
    do PS5 14.10 **não** informa o app aberto (testado com o YouTube na frente).
  - **Intervalo mínimo entre sessões** (8 s, medido). Se um comando chegar durante o intervalo, o app guarda
    só esse primeiro comando, mostra "pronto em X s" e o envia assim que a sessão abrir. Comandos repetidos
    na espera são descartados. Testado ao vivo no app: 3 toques, cada um depois de uma soltura por
    inatividade, todos entregues (o 2º e o 3º passaram pelo intervalo e reconectaram em cerca de 10 s).
  - **Rota CEC**, se a Fase 0 confirmar: com vídeo tocando, ✕, ○, direcional e play/pausa vão pela TV, sem
    sessão e sem escurecer. Os outros botões abrem a sessão.
  - **Falhas.** Reconexão com espera crescente, e o IP é redescoberto pelo `host-id`.

---

## 7. Interface

### 7.1 Janela principal

```
+-----------------------------------------------------------------------------+
| * PS5-123 - pronto (conecta ao tocar)       Netflix     [Energia] [Ajustes] |
|                                                                             |
|   [ L2 ] [ L1 ]                                          [ R1 ] [ R2 ]      |
|   [Create]    .------------- touchpad -------------.         [Options]      |
|               '-----------------------------------'                         |
|            ^                                                  /\            |
|         <     >                                            []    ()         |
|            v                                                  X             |
|          (L3)             [ PS ]   [ Inicio ]                (R3)           |
+-----------------------------------------------------------------------------+
| TV [ - ] [ Mudo ] [ + ]     [ > Assistir ]     [ Ligar tudo ] [ Desligar ]  |
+-----------------------------------------------------------------------------+
```

- **Visual:** o mesmo do app da TV (fundo escuro, `RemoteButtonStyle`), com as cores do DualSense. Na tela,
  os botões usam os símbolos reais (✕ ○ □ △).
- **Status:** em repouso, pronto, conectando, conectado (com o aviso "vídeo escuro na TV enquanto
  conectado"), pronto em X s, em uso por outro dispositivo, sem resposta (desligado ou fora da rede).
- **Analógicos:** círculos que se arrastam e voltam ao centro ao soltar.
- **Gatilhos:** clique dá pressão total; arrasto dá pressão parcial.
- **Energia:** o botão abre as opções Ligar, Repouso, "Ligar tudo" e "Desligar tudo".

### 7.2 Teclado: nenhuma tecla comanda nada (decisão do usuário, 18/10/2026)

O app só obedece ao **mouse**, clicando nos botões da janela. Nenhuma tecla vira botão do PS5 nem comando
da TV (nem direcional, ✕, ○, nem volume). Isso substitui a tabela de atalhos das revisões anteriores.

A garantia vem de três camadas (`mac_app/UI/InputGuard.swift`):

1. **A janela descarta toda tecla.** Ficam livres só os atalhos com Command (sair, fechar, ocultar,
   minimizar) e digitar dentro das folhas de pareamento e de PIN, porque elas não mandam nada ao console.
2. **Os controles não recebem foco de teclado**, então Espaço ou Return não apertam um botão.
3. **Cada ponto de entrada de comando recusa executar** se o evento em tratamento for de teclado
   (cobre um item de menu escolhido com Return). Vale para todo botão do PS5, analógico, gatilho, início,
   assistir, ligar, repouso, ligar/desligar tudo e volume/mudo da TV.

Teste: `"Controle PS5" --selftest-input` posta 52 eventos de tecla (26 teclas, descer e soltar) e um clique
pelo caminho real de eventos do app, em modo de teste (nada vai ao PS5 nem à TV; usa uma pasta de
configuração à parte, `PS5_CONFIG_DIR`). Resultado em 18/10/2026: a janela descartou 52 de 52, **0 comandos**
passaram durante as teclas, e o clique passou (9 do PS5 e 4 da TV).

### 7.3 Extras

- **Barra de menus** (`MenuBarExtra`): direcional, ✕, ○, PS, "Assistir" e volume, para usar sem abrir a
  janela.
- **Janela:** "Sempre na frente" e "abrir ao iniciar o Mac".
- **Texto (experimental):** quando o PS5 abre o teclado da tela, um campo no Mac manda o texto digitado.

---

## 8. Fases

### Fase 0: teste prático, sem código (cerca de 1 h, com você na frente da TV)

Objetivo: medir o que muda o desenho antes de escrever código.

1. **Preparar o PS5** (seção 10). Anote como estavam as três opções de HDMI antes de mexer.
2. **SIMPLINK → PS5 (5 min).**
   1. Ponha a TV na entrada do PS5, com o SIMPLINK ligado.
   2. No app da TV, mande ↑ ↓ ← →, OK, Voltar, Play e Pausa.
   3. Se nada acontecer, aperte SIMPLINK no app, escolha o PS5 na lista e repita.
   4. Anote quais teclas o PS5 obedeceu, também com a Netflix tocando.
3. **Uso remoto com streaming (20 min).** Use o PS Remote Play oficial no iPhone: ele tem controle na tela
   e usa o mesmo protocolo.
   1. Com a Netflix tocando na TV, conecte. A sessão abriu? A imagem e o som da TV continuaram? Apareceu
      algum aviso na TV?
   2. Já conectado, navegue (os menus aparecem?), dê play num título e veja a TV.
   3. Desconecte e cronometre quanto tempo a imagem leva para voltar.
   4. Tente reconectar logo em seguida e cronometre o intervalo que o PS5 exige entre sessões.
   5. Repita os passos 1 e 2 no YouTube e na Globoplay, anotando o tempo de conexão.
4. **Energia e Link HDMI.**
   1. Com o PS5 em repouso, conecte pelo app oficial. Ele acordou? A TV ligou sozinha e trocou para a
      entrada do PS5?
   2. Coloque o PS5 em repouso pelo app.
   3. Com o PS5 em repouso e a TV desligada, ligue a TV pelo botão "Ligar" do app da TV (via TV Box). O PS5
      acordou junto?
   4. Com o PS5 ligado, desligue a TV pelo app da TV. O PS5 foi para o repouso?
5. **Descoberta com app aberto.** Com a Netflix aberta, rode `python3 tools/ps_discover.py` e veja se
   aparece `running-app-name`.
6. **Opcional.**
   - Ligue um DualSense físico com a sessão aberta. A sessão cai?
   - Quem quiser já usar algo hoje: o chiaki-ng v1.10.0 (DMG arm64), com "Video Disabled" e o teclado
     mapeado, funciona como controle provisório. Se ele não conectar, provavelmente é a permissão de rede
     local (o app dele não a pede).

Anote os resultados aqui:

| Teste | Resultado |
|---|---|
| SIMPLINK: teclas que o PS5 obedece (sem vídeo / com vídeo) | Sem sessão de Uso remoto aberta: ←, →, ↓ e OK funcionam (inclusive dentro do YouTube). Com sessão aberta: ignoradas. Play/pausa pela TV não testados |
| A sessão abre com vídeo tocando? | |
| TV com sessão aberta: imagem / som / menus / aviso na tela | Menus aparecem; aviso "[usuário] se conectou pelo Uso remoto." e painel de ícones no canto. Imagem e som de app de vídeo: a confirmar olhando a TV |
| A imagem volta quantos segundos depois de desconectar? | |
| Intervalo mínimo entre sessões (s) | 8 (o console recusa por 6 a 8 s; medido com `ps5ctl bench`) |
| Tempo de conexão (s) | 2,3 a 2,7 |
| Acordar do repouso liga a TV na entrada certa? | |
| Ligar a TV pela TV Box acorda o PS5? Desligar a TV põe o PS5 em repouso? | |
| `running-app-name` aparece com a Netflix aberta? | Não: com o YouTube na frente a descoberta não informa app nenhum (PS5 14.10) |

Esses números definem a política de conexão (seção 6.3). O resultado do SIMPLINK decide se a rota CEC entra
na Fase 3 ou se vira o Raspberry Pi da Fase 5. O item 4 decide o que fazer com o Link HDMI (seção 12.2,
item D).

### Fase 1: biblioteca compilada + CLI de prova (1 a 2 dias)

- **Repositório:** `git init` e o chiaki-ng como submódulo, em commit fixo do `main` (a partir de
  `c8bea26`). Só os submódulos necessários: `nanopb`, `jerasure`, `gf-complete` e `curl`.
- **`scripts/build_chiaki.sh`:**
  - `brew install cmake ninja pkgconf miniupnpc libevent protobuf@29`;
  - um venv de Python com `protobuf>=5,<6`, para o gerador do nanopb;
  - CMake só com a biblioteca: GUI, CLI, testes, SteamDeck, atalho da Steam, FFmpeg, Pi, Setsu, Speex e Opus
    desligados.

  A biblioteca liga `json-c`, `miniupnpc`, `libevent` e o `curl` do submódulo mesmo no uso em rede local
  (servem ao modo pela internet, que o app não usa). Se algum pacote do Homebrew não trouxer `.a`, compile
  essa dependência junto; se o tamanho incomodar, dá para remover o modo pela internet com stubs de sete
  funções, mas isso é otimização, não requisito.
- **`ps5ctl`:** um CLI em Swift com o mesmo motor. Comandos: `discover`, `pair --pin 12345678`, `wake`,
  `press <botão>`, `hold <botão> <ms>`, `home` (testa o `go_home`), `standby`. Ele mede o tempo de conexão
  e o intervalo entre sessões com fechamento limpo.
- **Pronto quando:**
  - `ps5ctl pair` grava o `host.json`;
  - `ps5ctl press down` mexe a seleção na TV;
  - `standby` e `wake` funcionam;
  - o tempo de conexão e o intervalo entre sessões estão medidos;
  - `otool -L` não mostra nenhuma dependência do Homebrew no binário.

### Fase 2: app com pareamento e controle (2 a 3 dias)

- **Assistente de pareamento:** achar o PS5; obter o ID da conta (botão que abre o login da Sony no
  navegador e campo para colar a URL de redirecionamento, ou campo para colar o ID pronto); código de 8
  dígitos; pronto.
- **Controle:** tela do DualSense (só mouse, seção 7.2), estados e política de conexão (seção 6.3).
- **Empacotamento:**
  - `Info.plist` com `NSLocalNetworkUsageDescription` e bundle id `com.ps5remote.mac`;
  - assinatura ad-hoc;
  - instalação em `~/Applications`, com atalho na Mesa.
- **Pronto quando:** valem os critérios 1, 2 e 5 da seção 9.

### Fase 3: energia e integração com a TV (cerca de 1 dia)

- **Energia:** Ligar, Repouso e Início.
- **Volume e mudo** da TV pelo `LGTVClient`.
- **"Ligar tudo":** acorda o PS5 e espera a TV ligar pelo One-Touch Play do PS5, já na entrada dele. Se a
  TV não responder em alguns segundos, usa o caminho da TV Box (`turnOn()`). Se a Fase 0 levar a desligar o
  Link HDMI, o caminho passa a ser só a TV Box, e a troca de entrada fica com você (ou com uma macro
  `External input` + setas + OK, frágil).
- **"Desligar tudo":** repouso do PS5 e `power` da TV, nessa ordem.
- **Rota CEC,** se a Fase 0 confirmar o SIMPLINK: `CECRoute` para ✕, ○, direcional e play/pausa enquanto
  você assiste.
- **Pronto quando:** valem os critérios 3 e 4 da seção 9.

### Fase 4: conforto (1 a 2 dias)

- Barra de menus.
- Abrir ao iniciar o Mac (`SMAppService`) e "sempre na frente".
- Texto experimental (`enable_keyboard`).
- Login da Sony em janela embutida (`WKWebView`), se o fluxo pelo navegador incomodar.
- README com instalação e solução de problemas.

### Fase 5: opcional

- **Prévia do vídeo** (VideoToolbox, 360p a 540p), para usar sem olhar a TV. Os menus aparecem; o
  streaming fica preto.
- **CEC por hardware**, se o SIMPLINK não repassar as teclas e você quiser pausar sem escurecer. Um
  Raspberry Pi 4/5 numa entrada HDMI livre da TV, com `cec-ctl` e um servidor HTTP pequeno; o `CECRoute`
  passa a falar com ele.

**Esforço:**

| Escopo | Dias de trabalho |
|---|---|
| Mínimo utilizável (Fases 1 a 3) | 4 a 6 |
| Com a Fase 4 | 6 a 8 |

---

## 9. Critérios de aceite (app pronto)

1. **Pareamento que fica.** O app acha o PS5-123 e pareia com o código uma vez. Depois de fechar o app ou
   reiniciar o Mac, conecta sem pedir nada, inclusive o PIN de login do console, se houver.
2. **Controle completo, só pelo mouse.** Clicando nos botões da janela, inclusive segurando, chegam ao PS5:
   - todos os botões do DualSense: direcional, ✕ ○ □ △, L1/R1, L2/R2 analógicos, L3/R3, Create, Options, PS
     e touchpad;
   - os dois analógicos.

   O teclado nunca comanda nada (seção 7.2); o autoteste `--selftest-input` prova isso.
3. **Streaming utilizável.** Com um app de vídeo aberto, o app navega e dá play. Com o vídeo tocando, pausa
   e continua, pela rota CEC ou reabrindo a sessão. A imagem e o som da TV voltam sozinhos depois do último
   comando, no tempo medido na Fase 0.
4. **Energia.** O app liga o PS5 do repouso e o coloca em repouso. "Ligar tudo" deixa a TV e o PS5 ligados,
   na entrada certa.
5. **Convivência.**
   - Se outro dispositivo estiver usando o Uso remoto, o app avisa em vez de travar.
   - Se o PS5 mudar de IP, o app o encontra de novo sozinho.
   - O intervalo entre sessões aparece como "pronto em X s", e a interface não trava na espera.

---

## 10. Preparação (uma vez)

No PS5, com os nomes do menu em português do Brasil:

1. *Configurações › Sistema › Uso remoto › **Ativar o Uso remoto***.
2. *Configurações › Sistema › Economia de energia › Recursos disponíveis no modo de repouso*: ative
   **Continuar conectado à Internet** e **Habilitar opção de ligar o PS5 a partir da rede**.
3. *Configurações › Sistema › HDMI*: há três opções, cujos nomes podem variar um pouco na tradução:
   - **Link de dispositivo HDMI**: necessário para o CEC (teclas pela TV) e para as duas opções abaixo;
   - **Reprodução com um toque** (One-Touch Play): ligar o PS5 liga a TV e troca para a entrada dele;
   - **Link de desligamento** (Power Off Link): desligar a TV põe o PS5 em repouso.

   Para a Fase 0, deixe as três ligadas. O que fica ligado depois é decisão da seção 12.2, item D.
4. Na hora de parear: *Configurações › Sistema › Uso remoto › **Emparelhar dispositivo***, que mostra o
   código de 8 dígitos.
5. **Opcional:** reservar no roteador o IP 192.0.2.18 para o PS5 (MAC `aa:bb:cc:dd:ee:ff`). O app
   encontra o console mesmo se o IP mudar, mas o IP fixo evita esperas.

Na TV: SIMPLINK ligado. O app da TV já depende disso.

---

## 11. Referências

**Protocolo e biblioteca**

- chiaki-ng: <https://github.com/chiaki-ng/chiaki-ng>
  - versão v1.10.0, de 03/04/2026; o `main` foi lido no commit `c8bea26`, de 09/10/2026;
  - arquivos conferidos: `lib/include/chiaki/{discovery,regist,session,controller,takion}.h`,
    `lib/src/{session,ctrl,senkusha,discovery}.c`, `lib/CMakeLists.txt`, `scripts/psn-account-id.py`,
    `gui/src/psnaccountid.cpp` e `.github/workflows/build-release.yaml`.
- `keyboard-ds5`, controle só por teclado em cima do pyremoteplay: <https://github.com/tejasbnshetty/keyboard-ds5>.
  Fonte do escurecimento na TV, da conexão em cerca de 1 s e dos cerca de 9 s entre sessões.
- pyremoteplay (arquivado): <https://github.com/ktnrg45/pyremoteplay>

**Sony: restrições e configurações**

- Restrições oficiais do Uso remoto: <https://remoteplay.dl.playstation.net/remoteplay/lang/en/index.html>
- Configurações do Uso remoto (pt-BR): <https://www.playstation.com/pt-br/support/games/remote-play-settings/>
- Uso remoto e modo de repouso (pt-BR): <https://www.playstation.com/pt-br/support/hardware/playstation-remote-play-on-psportal/>
- PS Remote Play no PC e no Mac: <https://www.playstation.com/en-us/support/games/playstation-remote-play-on-pc-and-mac/>
- Funções dos botões do PS5: <https://www.playstation.com/en-gb/support/hardware/ps5-button-functions/>
- PS App, "Jogar no console": <https://www.playstation.com/en-us/support/games/playstation-app-features/>

**HDMI-CEC**

- PS5 por CEC com `cec-ctl`: <https://gist.github.com/Gezine/a0a6e4748df084b8092b256e34539019>
- O mesmo, discutido no ResetEra: <https://www.resetera.com/threads/wait-did-you-know-you-can-control-the-ps5-with-your-tv-remote.340150/>
- Adaptador Pulse-Eight USB-CEC: <https://www.pulse-eight.com/p/104/usb-hdmi-cec-adapter>
- Link de dispositivo HDMI do PS5: <https://tomsguide.com/how-to/this-hidden-ps5-feature-could-change-how-you-use-your-console-heres-how-to-access-it>
- PS5 acordando quando a TV liga: <https://www.bgr.com/2186983/how-to-stop-playstation-5-from-turning-on-with-tv/>

**Alternativas descartadas**

- Mac como HID Bluetooth: <https://github.com/jqssun/darwin-bt-remote>
- Autenticação de controles no PS5: <https://github.com/OpenStickCommunity/Site/blob/main/docs/faq/faq-console-compatibility.mdx>
- CoreHID `HIDVirtualDevice`: <https://developer.apple.com/documentation/corehid/hidvirtualdevice>

---

## 12. Revisão de 18/10/2026

### 12.1 O que a revisão mudou

| # | Antes | Agora | Por quê |
|---|---|---|---|
| 1 | Login da Sony numa janela embutida (`WKWebView`) já na Fase 2 | Login no navegador padrão + colar a URL de redirecionamento, ou colar o ID pronto. Janela embutida só na Fase 4, se incomodar | É uma operação única; o fluxo pelo navegador tem menos código e menos risco com a página da Sony |
| 2 | "Início" era um botão sem definição de como funciona | Início = PS segurado por 1 s (comportamento documentado do controle). O comando `go_home` da biblioteca existe e vira teste da Fase 1 | O `go_home` nunca foi confirmado no PS5 |
| 3 | Em app de vídeo, a sessão caía 8 s depois de qualquer comando | 5 s depois de um ✕; 20 s depois dos demais; 2 min fora de apps de vídeo | Nos menus só as prévias escurecem; soltar cedo demais custava o intervalo entre sessões a cada leitura de sinopse |
| 4 | Na espera entre sessões, só "pronto em X s" | Guarda o primeiro comando e o envia quando a sessão abrir; descarta repetições | O comando que você deu é o que você queria; apertar de novo é impaciência |
| 5 | Intervalo de cerca de 9 s tratado como fato | Tratado como medida a fazer: o chiaki-ng fecha a sessão com `disconnect` explícito, diferente do app de referência | Conferido em `lib/src/streamconnection.c` |
| 6 | Meta de conexão de 1 a 3 s sem base | Mantida, agora com base: o teste de rede da conexão adapta o tempo limite ao RTT (5× o RTT, entre 5 e 500 ms) | Conferido em `lib/src/senkusha.c` |
| 7 | Nada sobre o Link HDMI do PS5 interferir no fluxo da TV Box | Risco 13, dois testes novos na Fase 0 e decisão D | O "Ligar a TV" do app da TV usa CEC; com o Link HDMI ligado, o PS5 pode acordar junto |
| 8 | `opus` listado como dependência instalada | Removido: a compilação desliga o Opus. `libssl.a` conferido. `miniupnpc` e `libevent` têm bottle para macOS 26 arm64; `protobuf@29` está descontinuado, mas instalável | Lista alinhada ao que a Fase 1 vai usar |
| 9 | Maquete da janela desalinhada e com emoji | Redesenhada em ASCII puro, com colunas alinhadas | Legibilidade |
| 10 | Fase 0 sem aviso na TV, sem interação com a TV Box | Itens adicionados aos passos e à tabela de anotação | Riscos 13 e 14 |
| 11 | `h` para PS, sem Início no teclado | `Shift+h` = Início | Paridade com o botão |
| 12 | Seção 10 citava só o Link HDMI e o One-Touch Play | As três opções de HDMI e o efeito de cada uma | Fase 0 precisa saber o que ligar |

Conferido no código-fonte e confirmado sem mudança: enum `CHIAKI_AUDIO_VIDEO_DISABLED = 3`, bits do
controle (Create = `SHARE`, sem bit de Mute), campos do pareamento (`pin`, `psn_account_id`),
`chiaki_discovery_wakeup`, parse de `running-app-name`, opções do CMake e dependências ligadas.

### 12.2 Decisões em aberto para você

| | Decisão | Proposta |
|---|---|---|
| A | Com que rapidez soltar a sessão em apps de vídeo | 5 s depois de um ✕, 20 s depois dos demais comandos, 2 min fora de apps de vídeo. Ajustar com os tempos da Fase 0 |
| B | O que fazer com um comando dado durante o intervalo entre sessões | Guardar só o primeiro e enviar quando a sessão abrir, com contagem na tela |
| C | Como obter o ID da conta PSN | Login no navegador padrão e colar a URL de redirecionamento, com campo para colar o ID pronto. Janela embutida fica para a Fase 4 |
| D | Link HDMI do PS5 (decidir depois da Fase 0) | Manter ligado, pelo CEC e pelo One-Touch Play, se o PS5 não acordar quando a TV Box liga a TV. Se acordar, escolher entre aceitar isso ou desligar o Link e abrir mão do CEC |
| E | Ordem das fases | Fases 1 a 3 primeiro; barra de menus e "abrir ao iniciar" na Fase 4 |
| F | Nome e identificador do app | "Controle PS5", bundle id `com.ps5remote.mac`, instalado em `~/Applications` com atalho na Mesa, como o app da TV |

---

## 13. O que a implementação revelou (18/10/2026)

### 13.1 Instrumento de teste

`ps5ctl script` abre uma sessão **com vídeo**, executa passos ("press circle", "hold ps 1000", "shot nome")
e salva capturas da tela do PS5 decodificadas com o ffmpeg. Assim dá para ver o efeito de cada botão sem
depender de olhar a TV. Duas limitações: a tela fica **preta** quando há app de streaming na frente (o PS5
não transmite conteúdo protegido, e o plano não tenta contornar isso), e a própria sessão escurece a
imagem da TV enquanto está aberta.

### 13.2 Achados

| # | Achado | Como foi visto |
|---|---|---|
| 1 | O app e o `ps5ctl` caíam quando havia app de vídeo na tela (risco 15) | `ps5ctl script` saiu com 139; relatório de queda: ponteiro nulo em `ctrl_connect` |
| 2 | A interface oficial do chiaki-ng sempre anuncia o cliente como **DualSense** no PS5. Meu código anunciava DualShock 4. Agora o padrão é DualSense (`--ds4` no `ps5ctl` volta ao modo antigo para comparar) | leitura de `gui/src/streamsession.cpp` |
| 3 | Os botões viajam só por eventos de **histórico**; o estado (analógicos, giroscópio) vai em outro pacote. Por isso "analógico funciona e botão não" é possível | leitura de `feedbacksender.c` |
| 4 | O commit fixado (`c8bea26`, 09/10/2026) inclui três mudanças de **dias antes** no envio de botões (#823, #838, #840), todas ausentes da v1.10.0 estável. A #840 preenche a contagem de eventos no cabeçalho com um palpite do autor ("*may be why*…") | `git log` e `git show c938844a` |
| 5 | PS curto e PS segurado funcionam (a segurar saiu do app de vídeo para a tela inicial) | capturas das execuções 2 e 4 |
| 6 | ○ funciona numa sessão nova | execução 4: Central de Controle aberta → um ○ → fechada |
| 7 | ○ **não** funciona logo depois de PS na mesma sessão (commit atual) | execução 5: Central abre, ○ não fecha |
| 8 | Com a biblioteca anterior à #840, PS **não** abre a Central logo depois de ○ | execução 6 |
| 9 | Quatro PS seguidos alternam certo (abre, fecha, abre, fecha) nas duas versões | execução 7 |
| 10 | `PSDiscovery.find` caía para "o primeiro PS5 que responder" mesmo com `host-id` conhecido. Corrigido | autoteste regravou o endereço de um arquivo de teste |

### 13.3 Medições estatísticas (18/10/2026, tarde)

`tools/cc_toggle_test.sh` alterna PS (abre a Central de Controle) e ○ (fecha) numa sessão só, com captura
depois de cada toque. Cada captura é classificada pelo brilho (Central aberta ≈ 32, fechada ≈ 6 a 9), e cada
passo é julgado pelo estado real anterior.

| Versão da biblioteca | Toque | PS | ○ | RTT da sessão |
|---|---|---|---|---|
| `c8bea26` (atual, fixada) | 80 ms | 6/6 | 6/6 | ~5 ms |
| v1.10.0 (estável) | 80 ms | 6/6 | 6/6 | ~5 ms |
| `c8bea26` repetindo 1 evento por pacote | 80 ms | 6/6 | 6/6 | ~4 ms |
| `c8bea26` (atual) | 200 ms | **5/6** | 5/5 | ~5 ms |
| `c8bea26`, anunciando DualSense | 80 ms | 6/6 | 6/6 | ~5 ms |
| `c8bea26`, anunciando DualShock 4 (modo do build antigo) | 80 ms | 6/6 | 6/6 | ~5 ms |
| `c8bea26` | 80 ms | **7/8** | 7/7 | ~5 ms |
| `c8bea26` | 150 ms | 8/8 | 8/8 | ~5 ms |
| `c8bea26` | 200 ms | **7/8** | 7/7 | ~5 ms |
| `c8bea26` | 250 ms | **7/8** | **6/7** | ~5 ms |

Conclusões:

- A hipótese de 13.2 ("misturar botões de 2 e 3 bytes no mesmo pacote quebra") foi **refutada**: 36 toques
  alternando PS e ○ sem falha nenhuma, nas três versões.
- As falhas das execuções 2, 5 e 6 aconteceram com a rede pior: o teste de rede mediu RTT de 15 a 23 ms
  nelas, contra 4 a 9 ms nas que passaram, e uma registrou pacotes fora de ordem. Perda de pacotes é a
  explicação mais provável. As mudanças recentes da biblioteca (#823, #838, #840) servem justamente para
  recuperar eventos perdidos, então a versão fixada continua a atual.
- O modo do controle não explica nada: DualSense e DualShock 4 deram 12/12 cada.
- **Duração do toque importa.** Somando o dia: 80 ms falhou 1 vez em cerca de 75 toques; 150 ms, 0 em 16;
  200 ms, 2 em 26; 250 ms, 2 em 15. O app espelhava a duração do clique (um clique humano dura 80 a 250 ms),
  o que explica bem o relato "o voltar não funciona". **Correção:** cada clique vira um toque fixo de 80 ms
  (seção 6.3).
- O primeiro toque de uma sessão **não** se perde: enviado 0, 0,3, 0,6 ou 1 s depois de conectar, 8 de 8.

### 13.4 Testes de ponta a ponta (18/10/2026)

| Teste | Resultado |
|---|---|
| Sequência longa de direcional (→ → → ↓ ↑ ← ← ←, 18 eventos numa sessão) | Os 9 movimentos certos; o foco volta exatamente ao ponto de partida |
| YouTube: ↑ (aba Jogos), → (aba Mídia), ✕ (abre a aba), → (YouTube), ✕ (abre o app), PS segurado | Funcionou; com o YouTube aberto a captura fica preta (conteúdo protegido) e o PS segurado volta ao início. A aba Mídia mostra YouTube, Prime Video, Netflix, Disney+, Apple TV, Twitch e Spotify |
| Repouso pelo app (`standby`) | O PS5 entra em repouso e responde "620 Server Standby" na descoberta |
| Acordar (`wake`) | Com **um** pacote de wake falhou uma vez. **Correção:** reenviar a cada 4 s. Depois: ligado em 19,6 s, no 5º pacote (e 15 s numa tentativa manual) |
| Endereço depois de acordar | Uma resposta da descoberta chegou com origem `0.0.0.0` (rede do console subindo). **Correção:** respostas sem endereço válido são descartadas, para o app nunca salvar esse endereço |
| Início (PS segurado) | Com 1 s, uma vez o PS5 entendeu como toque curto. **Correção:** 1,5 s |
| App de verdade, ao vivo (`--selftest-live`) | 3 toques de PS pela política do app (fila, soltura por inatividade, intervalo entre sessões): os 3 entregues |
| Rota pela TV (SIMPLINK), olhando a TV pela consulta `screen_image` da LG | Funciona **sem** sessão de Uso remoto aberta (← → ↓ OK); com sessão aberta, ignorada. Uma tecla OK se perdeu |
| YouTube por dentro, olhando a TV | Escolha de conta, menu lateral, recomendados e play pelo ✕ do Uso remoto: o vídeo tocou. A imagem estava visível 1 s depois de a sessão fechar (a pesquisa falava em cerca de 3 s) |
| Incidente no YouTube | Na tela "Quem está assistindo?", um ↓ seguido de OK escolheu "Assistir como visitante". A conta do usuário foi restaurada pelo próprio controle (menu lateral → Fazer login → conta). Lição: nos testes, olhar cada tela antes de confirmar |
| A TV **durante** a sessão, com vídeo tocando | Não verificado: as capturas foram tiradas, mas os testes foram encerrados a pedido antes da análise |
| Aviso de conteúdo protegido | Chega ao conectar com um app de vídeo na frente. Quando o app de vídeo abre **no meio** da sessão, o PS5 não avisa. **Correção:** soltar a sessão 6 s depois de um ✕ em qualquer app (seção 6.3) |


### 13.5 Incidente: pareamento apagado

Durante o autoteste do teclado, o clique simulado executou `forget()`, que apaga `host.json` de verdade
(o modo de teste não protegia esse comando; só a trava de teclado o barrou). O pareamento do usuário foi
perdido durante o teste e não há cópia (sem snapshot do Time Machine) nem como reconstruir as chaves. Precisa parear
de novo, com um código novo do PS5 (o ID da conta PSN não muda).

Correções: `forget()` é inerte no modo de teste; o autoteste roda com `PS5_CONFIG_DIR` apontando para uma pasta
de mentira e confere que o arquivo continua lá; "Esquecer" no app pede confirmação.

Restaurado no mesmo dia com um código novo do PS5. Desde então há uma cópia de segurança temporária do arquivo
fora do repositório, usada só durante os testes.
