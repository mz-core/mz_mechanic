# mz_mechanic

Oficina server-authoritative do MZ Framework. A Wave M1 entrega vínculo e duty de mecânico via `mz_org`, ordem de serviço, diagnóstico, orçamento, consentimento do cliente, cobrança por `mz_economy`, reparo e persistência por `mz_vehicles`. A Wave M2 inicia customização incremental de carroceria e performance usando a mesma OS e as mesmas autoridades.

## Estado da entrega

- M0: contratos auditados e decisões registradas em `docs/`.
- M1: implementada para reparo estrutural completo.
- Limpeza: visível como indisponível porque sujeira não integra a persistência pública de `mz_vehicles`.
- M2: primeiro subset executável de carroceria e performance, com catálogo por capacidade do modelo, preview reversível, preço server-side e persistência de props por `mz_vehicles`.
- Cores, rodas, neon, xenon, extras, interiores, placas, buzinas e liveries: auditados, mas ainda não habilitados no fluxo executável.
- Decals personalizadas/URL: M3/M4, fora deste recurso nesta entrega.
- Modo standalone: implementado como contingência local, mas `Enabled = false` por padrão.

## Experiências da oficina

- **Mecânica física:** o `mz_mechanic` registra no `mz_target` a entrada “Diagnóstico e ordem de serviço” sobre veículos networked. O contexto/diagnóstico aceita o veículo próximo selecionado mesmo fora da baia; a criação e execução da OS continuam exigindo uma vaga configurada, orçamento, consentimento e cobrança.
- **Atendimento:** painel compacto para duty, diagnóstico, OS, orçamento, aprovação, execução e reconciliação.
- **MZ Automotive:** interface de tuning independente, aberta pelo target apenas para veículo parado em vaga configurada. Sem OS, o catálogo compatível fica disponível somente para consulta; preview, orçamento e persistência continuam protegidos pela OS e pelos callbacks financeiros.

Não existem ainda reparos separados de motor, carroceria ou pneus. Eles não são apresentados no target porque o backend atual só autoriza `full_repair`. `mz_inventory` também não possui definições canônicas de ferramentas mecânicas nesta baseline.

## Instalação manual

1. Confirme `ox_lib`, `oxmysql`, `mz_core`, `mz_economy`, `mz_org` e `mz_vehicles` iniciados antes deste recurso.
2. Aplique manualmente `sql/001_mz_mechanic_baseline.sql`. O recurso não executa DDL.
3. Gere a NUI com `pnpm --dir mz_mechanic/web install` e `pnpm --dir mz_mechanic/web build`.
4. Adicione `ensure mz_mechanic` na configuração do servidor manualmente.
5. Cadastre o personagem na organização `mechanic` com `mechanic.repair.basic`; o duty é o canônico de `mz_org`.

`mz_target` e `mz_radialmenu` são integrações opcionais descobertas em runtime. O target preserva a entidade exata; radial e `mzmechanic`/F7 fazem uma busca única pelo veículo networked mais próximo e, se nenhum existir, mantêm o Atendimento administrativo sem veículo. O blip “MZ Automotive” indica localização e não concede autorização nem abre a NUI automaticamente.

## Fluxo M1

`created → diagnosed → quoted → accepted → in_progress → pending_apply → completed`

`cancelled` e `failed` são terminais. Cobrança incerta, aplicação sem persistência, interrupção de runtime e expiração após início financeiro entram em `pending_reconciliation` e mantêm o lock.

## Contrato público

`GetMechanicCapabilities()` informa somente capacidades; não concede autorização nem executa mutações. Callbacks NUI e eventos internos usam o prefixo `mz_mechanic` e todos os intents são revalidados no servidor.

Consulte `docs/NUI_SETUP.md`, `docs/SECURITY.md` e `docs/CHECKLIST_FIVEM.md` antes da homologação.
Para M2, consulte também `docs/M2_CAPABILITY_AUDIT.md` e `docs/M2_RUNTIME_CHECKLIST.md`.
