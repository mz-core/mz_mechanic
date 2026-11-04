# NUI

A interface é um projeto React + TypeScript + Vite + Tailwind independente. Os componentes shadcn necessários são source-owned em `web/src/components/ui`; não existe import runtime de `mz_ui` ou `@mz/ui`.

## Build

```powershell
pnpm --dir mz_mechanic/web install
pnpm --dir mz_mechanic/web lint
pnpm --dir mz_mechanic/web typecheck
pnpm --dir mz_mechanic/web build
```

O Vite usa `base: './'`; fontes, CSS e JavaScript saem locais em `web/dist`. Não há CDN nem runtime Node no FiveM.

## Contrato CEF

- A raiz inicia vazia e transparente.
- `mz_mechanic:open` recebe `view = atendimento | tuning`, abre em loading e solicita uma única resolução autoritativa ao servidor. O modo também segue no callback de contexto para que somente o Tuning exija baia e veículo parado. O snapshot client de `GetPlayerSession()` é apenas diagnóstico e nunca bloqueia a abertura.
- No servidor, `ResolvePlayerIdentity(source)` preserva os erros canônicos e `IsPlayerLoaded(source)` confirma readiness antes do contexto da oficina.
- `mz_mechanic:contextLoading` e `mz_mechanic:context` carregam `requestId`; respostas antigas, tardias ou posteriores ao close são ignoradas.
- `mz_mechanic:retryContext` é acionado somente por ação explícita do usuário; não há loop automático de retry.
- Atendimento e Tuning usam a mesma raiz, o mesmo transporte e um único foco; uma nova abertura invalida a anterior.
- O catálogo de Tuning sem OS é calculado no client a partir da configuração compartilhada e das capacidades nativas do veículo, apenas para exibição. Nenhuma seleção, cobrança ou persistência é liberada sem sessão de preview autorizada pelo servidor.
- ESC sai primeiro do modo inspecionar. No Tuning direto, cancela/rollbacka e fecha; quando o Tuning nasceu do Atendimento, retorna ao painel compacto. Confirmações inline continuam sendo consumidas antes do fechamento.
- Toda chamada possui timeout, cancelamento, envelope `{ok,error}` e nome explícito.
- `?preview=1` serve apenas para QA visual local e mostra “PREVIEW OFFLINE”; nenhuma mutação é enviada.

## Componentes source-owned

Button, Card, ScrollArea e Skeleton. São componentes source-owned derivados do padrão oficial já adotado pelo `mz_ui`; tokens e composição permanecem locais da oficina. Atendimento usa composição tactical editorial compacta. MZ Automotive usa composição vehicle-first com centro transparente, categorias inferiores e painel técnico contextual, sem imagens/CDN.
