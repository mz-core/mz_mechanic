# Revisão da NUI — hotfix de sessão e painel vehicle-first

## Diagnóstico

### Problemas observados

- A abertura anterior aplicava foco e fazia `mz_mechanic:getContext` imediatamente pelo browser.
- Quando o personagem ainda não possuía sessão ativa no cache canônico, `mz_core:ResolvePlayerIdentity` retornava `session_not_found`.
- A interface tratava qualquer falha como uma faixa genérica e podia mostrar o código técnico bruto.
- O loading dependia apenas do retorno do `fetch`; não havia geração de request para invalidar respostas tardias ou fora de ordem.
- O shell ocupava até 78% da largura, usava navegação de dashboard e escondia mais do veículo/jogo do que o necessário.
- Existiam um botão “X” global, tabs sem utilidade imediata para M1 e uma entrada de Personalização bloqueada.

### Causa comprovada em código

O encadeamento real era:

`Client.Open` → `mz_mechanic:open` → NUI `load()` → `mz_mechanic:getContext` → `Service.GetContext` → `Adapters.ResolveIdentity` → `mz_core:ResolvePlayerIdentity`.

`ResolvePlayerIdentity` retorna `session_not_found` quando a sessão do source não existe ou não está ativa. A primeira correção removeu corretamente o cache client como gate, mas o runtime continuou falhando mesmo com `client_session active=true`.

A causa real estava no adapter dinâmico: ele chamava `exports[resource][exportName](source)` com sintaxe de função. O proxy de exports Lua do FiveM usa semântica de método; consumidores funcionais usam `exports['mz_core']:ResolvePlayerIdentity(source)`. Sem o proxy/self, o Core recebia o proxy no lugar do `source`, `validSource` falhava e o retorno correto para aquele argumento inválido era `session_not_found`. O adapter agora chama `exportFn(resourceExports, source)`, equivalente ao `:`. O callback também normaliza/rejeita source inválido antes do Core.

O client continua usando `GetPlayerSession()` somente como diagnóstico. No servidor, `ResolvePlayerIdentity(source)` preserva `session_not_found`, `character_not_active` e `player_not_loaded`; `IsPlayerLoaded(source)` e `identity.active` produzem `session_not_ready` somente quando a identidade realmente existe, mas o lifecycle ainda não está pronto.

### Hipóteses ainda dependentes de runtime

- A ordem exata dos eventos em uma conexão real pode variar conforme latência, restart parcial e seleção de personagem.
- A ergonomia com veículo, câmera e HUD reais depende de homologação dentro do FiveM.
- Os testes offline não comprovam integração com uma instância real de CEF, banco, economia ou OneSync.

### Contratos Core verificados

| Contexto | Contrato | Assinatura | Retorno e uso correto |
| --- | --- | --- | --- |
| Client | `GetPlayerSession` | `GetPlayerSession()` | snapshot local `MZClient.PlayerSession` ou `nil`; diagnóstico, não autoridade |
| Server | `GetPlayerSession` | `GetPlayerSession(source)` | snapshot canônico da sessão; não é chamado pelo client |
| Server | `ResolvePlayerIdentity` | `ResolvePlayerIdentity(source)` | `{ok=true, citizenid, active, ...}` ou erro canônico de sessão/personagem/player |
| Server | `IsPlayerLoaded` | `IsPlayerLoaded(source)` | booleano autoritativo de player + sessão + vínculo do personagem |
| Client event | `mz_core:client:playerLoaded` | `(playerData, expectedSessionToken)` | atualiza `MZClient.PlayerData` e `MZClient.PlayerSession` |
| Client event | `mz_core:client:characterSelectionRequired` | `(selectionData)` | limpa o cache client e fecha a NUI do mecânico |

`MZMechanicConfig.Debug` fica `false` por padrão. Quando habilitado temporariamente, a homologação registra `client_session`, `callback`, `core`, `identity`, `authorization`, `vehicle` e `complete`, sempre com `requestId` e sem identifiers, token, citizenid ou placa.

## Referência legada inspecionada

Referência somente leitura: `D:\git-hub\mz_mechanicpanel`. Não foi identificada uma licença no diretório inspecionado; nenhum código, SVG ou asset foi copiado.

| Ideia da referência | Decisão | Aplicação atual |
| --- | --- | --- |
| Painel estreito à direita | Reutilizada conceitualmente | Shell lateral compacto, sem backdrop fullscreen |
| Veículo/placa em primeiro plano | Reutilizada conceitualmente | Cabeçalho persistente do veículo e condição real |
| Total de orçamento evidente | Reutilizada conceitualmente | Linhas do orçamento e total autorizado juntos |
| Aprovação explícita do cliente | Reutilizada conceitualmente | CTA contextual apenas no estado `quoted` |
| Scroll localizado | Reutilizada conceitualmente | Somente o conteúdo operacional rola |
| Câmera orbital e preview 3D | Adiada | Não há contrato canônico comprovado nesta Wave; o modo inspecionar apenas oculta a UI |
| Catálogo de mods/upgrades | Reutilizado conceitualmente | M2 oferece somente carroceria/performance comprovadas por modelo, sem entradas fictícias |
| QBCore, SQL e sessão próprios | Rejeitados | Contratos canônicos MZ permanecem autoridades |
| Assets e identidade visual legados | Rejeitados | Sem licença comprovada e sem necessidade funcional |
| “X” global e overlay de aprovação | Rejeitados | ESC devolve foco; confirmação é inline |

## Mudanças implementadas

- O client usa `GetPlayerSession()` somente para log diagnóstico; nunca como precondição.
- O servidor usa `ResolvePlayerIdentity(source)` e `IsPlayerLoaded(source)` conforme os contratos públicos do Core.
- Abertura e retry recebem um `requestId` monotônico. Close, nova abertura e resource stop invalidam requests anteriores.
- Sessão ausente vira um estado recuperável com “Tentar novamente” e “Voltar ao jogo”, sem polling automático e sem código técnico visível.
- A NUI possui watchdog de 8 segundos, aborta requests ao fechar e ignora respostas fora de ordem.
- A taxonomia separa sessão (`session_not_found`, `character_not_active`, `player_not_loaded`, `session_not_ready`), autorização (`missing_permission`, `not_on_duty`, `not_mechanic`) e veículo (`invalid_net_id`, `vehicle_not_found`, acesso, bucket, distância e vaga).
- Enquanto `Debug = true`, logs P0 registram somente request, source efêmero, tipo/shape, estágio, lifecycle/booleanos e código de resultado; IDs de sessão, cidadão e placa não são impressos.
- O painel foi reduzido a um fluxo contextual: Atendimento → Diagnóstico → Orçamento → Execução.
- Foram removidos tabs, Personalização, métricas de dashboard, botão “X” global e modal com backdrop.
- Ações M1 permanecem; M2 acrescenta workspace vehicle-first apenas quando o servidor publica `customization=true`.

## Contratos preservados

- Callbacks existentes e envelopes `{ok,error}`.
- Autoridade server-side para identidade, profissão, duty, veículo, preço, cobrança, aplicação e persistência.
- Transparência da raiz, foco controlado pelo client e fechamento via ESC.
- Componentes source-owned e assets locais; nenhum CDN ou dependência runtime no `mz_ui`.
