# Auditoria de integração M0

Auditoria feita contra código-fonte real. Graphify foi usado apenas para localizar escopo; os contratos abaixo foram confirmados nos exports e serviços dos recursos proprietários.

| Domínio | Evidência pública | Uso no `mz_mechanic` | Estado |
| --- | --- | --- | --- |
| Identidade | `mz_core:ResolvePlayerIdentity`, `GetSourceByCitizenId` | Resolve `citizenid` e presença; nenhuma escrita no Core | comprovado |
| Organização/ACL/duty | `mz_org:GetPlayerOrgContext`, `SetSelfOrgDutyAtPoint` | Organização `mechanic`, permissão real `mechanic.repair.basic`, membership ativa e duty | comprovado |
| Jobs genéricos | `mz_jobs:GetJobsReadiness`, `GetJobsCapabilities` | Somente capability; `playableJobs=false`, sem mutação pública utilizada | ausente para gameplay |
| Economia | `mz_economy:RemoveMoney`, `AddMoney`, `GetOperationResult` | Débito/estorno idempotentes e confirmação pelo ledger canônico | comprovado |
| Veículos | `GetVehicleByPlate`, `CanAccessVehicle`, `UpdateOutVehicleSnapshot`, `IsVehicleDomainReady` | ID persistente, ownership/access e persistência de engine/body | comprovado |
| Target | `AddGlobalVehicle`, `RemoveGlobalVehicle` | Entradas de Atendimento e Tuning; entidade e vaga filtradas no client e revalidadas no servidor | comprovado |
| Radial | `RegisterOption`, `RemoveOption` | Entrada opcional próxima da oficina | comprovado |
| Inventário | `HasPlayerItem` existe, mas não há ferramenta mecânica em `shared/items.lua` | Não integrado; nenhum item fictício exigido | bloqueado por catálogo |
| Notificação/animação | `ox_lib`; `mz_animations:PlayByName/Stop`; fallback native | Feedback local e animação `mecanico2` na aplicação | comprovado em contrato; runtime pendente |
| Banco | `oxmysql` | Tabelas próprias de OS, eventos, idempotência e vínculo standalone | script aditivo manual |

## Decisões

- `mz_mechanic` é o único writer das ordens e do lifecycle do atendimento.
- `mz_org` continua owner do vínculo organizacional, ACL e duty. Não existe campo `job` inventado no PlayerData/Core.
- `mz_economy` continua único writer de saldo e ledger. O recurso guarda apenas recibos e estado da cobrança na OS.
- `mz_vehicles` continua owner da identidade/persistência veicular. A OS referencia `vehicle_id`; placa e netId são provas auxiliares revalidadas.
- Limpeza fica OFF: o snapshot público inspecionado persiste fuel/engine/body/props, não sujeira.
- Personalização M2 usa catálogo por modelo, preview reversível e `UpdateOutVehicleSnapshot`; categorias futuras continuam bloqueadas conforme `M2_CAPABILITY_AUDIT.md`.

## Referência funcional `mz_mechanicpanel`

- `getVehicleAtBay()` percorria `GetGamePool('CVehicle')` uma vez e escolhia o veículo mais próximo de `vehiclePoint` dentro de `vehicleDistance`.
- `tryOpenPanel()` exigia veículo parado, opcionalmente vazio, obtinha placa/net ID da mesma entidade e só então solicitava abertura ao servidor; `openPanel()` preservava essa entidade durante toda a sessão.
- As vagas funcionais de referência usavam `(-211.67, -1324.81, 30.26)` e `(-196.35, -1324.20, 30.89)`, ambas com raio `3.6`. Estes pontos foram reaproveitados; a calibração visual no mapa continua pendente no FiveM.
- A câmera antiga criava uma `DEFAULT_SCRIPTED_CAMERA`, apontava para o veículo e oferecia rotação orbital e zoom por FOV. Não foi portada nesta correção.
- O catálogo antigo cobre performance, rodas/pneus, pinturas, neon/xenon, extras, liveries, carroceria e interior. Somente o subset MZ já autorizado de carroceria/performance continua executável; o restante permanece inventariado para uma próxima etapa.
- Preview/rollback antigos mantinham propriedades originais no client, mas seus contratos QBCore de dinheiro, jobs, itens e `player_vehicles` não foram transportados.

## Matriz de falha segura

- `mz_org` indisponível: ninguém recebe permissão pelo modo padrão; standalone continua OFF.
- schema ausente: callbacks retornam `schema_not_installed:*`; nenhum DDL é executado.
- economia indisponível/falha definitiva: OS falha antes da aplicação e libera lock.
- resultado financeiro incerto: `pending_reconciliation`, lock preservado.
- aplicação ocorreu, mas persistência falhou: `pending_reconciliation`, sem estorno automático.
- pagamento confirmado, aplicação falhou: estorno idempotente; se o recibo de estorno for incerto, reconciliação.
