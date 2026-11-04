# M2 — auditoria de capacidades e persistência

## Contratos canônicos comprovados

- Client `mz_vehicles:GetVehicleProperties(vehicle)`: snapshot completo usado para preview e rollback.
- Client `mz_vehicles:SetVehicleProperties(vehicle, props)`: aplica mod kit, slots, cores, rodas, extras, neon, xenon, livery e estado visual quando presentes.
- Server `mz_vehicles:GetVehicleByPlate(plate)`: resolve `vehicle_id`, estado e `props_json` persistidas.
- Server `mz_vehicles:CanAccessVehicle(source, plate)`: valida acesso do cliente.
- Server `mz_vehicles:UpdateOutVehicleSnapshot(source, plate, snapshot, options?)`: writer canônico usado no commit. Valida acesso, estado `out`, net ID/placa e distância; o commit transacional já autorizado da mecânica usa `bypassRateLimit`, enquanto snapshots comuns continuam limitados.

O `mz_mechanic` não grava tabelas de veículo e não usa placa/net ID como identidade persistente isolada: a OS mantém `vehicle_id`, lock e placa canônica resolvidos por `mz_vehicles`.

## Subset executável desta entrega

| Grupo | Slots/Natives | Capacidade por modelo | Preço | Persistência | Estado |
| --- | --- | --- | --- | --- | --- |
| Carroceria | 0 spoiler, 1/2 bumpers, 3 skirts, 4 exhaust, 6 grille, 7 hood, 10 roof | `SetVehicleModKit(0)` + `GetNumVehicleMods`; categorias com zero opções são omitidas | servidor por código/índice | props completas via `UpdateOutVehicleSnapshot` | habilitado |
| Performance | 11 engine, 12 brakes, 13 transmission, 15 suspension, 16 armor | `GetNumVehicleMods`; índice limitado também pela whitelist server | servidor por nível | props completas via `UpdateOutVehicleSnapshot` | habilitado |
| Turbo | slot toggle 18 | exibido somente quando o modelo informa opção | preço fixo server | `modTurbo` em props | habilitado |

O catálogo client serve apenas para UX/compatibilidade. O servidor ignora preço, field e slot enviados pelo browser; aceita somente `{code,value}`, aplica whitelist, limite, revisão, permit de preview, presença, duty, atribuição e lock da OS, e recalcula o total.

## Auditadas, ainda bloqueadas no fluxo executável

| Categoria | Suporte existente em `mz_vehicles` | Motivo do bloqueio incremental |
| --- | --- | --- |
| Cores primária/secundária, perolizado, wheel/interior/dashboard e RGB custom | `Get/SetVehicleColours`, custom colours e extra colours | precisa catálogo de cores, comparação e QA de rollback por combinação |
| Rodas/pneus/fumaça | wheel type, slots 23/24, custom tires e smoke | precisa tratar tipo de roda antes do índice e variações dianteira/traseira |
| Neon/xenon/tint | props e natives já aplicadas | precisa UX de quatro lados/RGB e validação visual por modelo |
| Extras | `DoesExtraExist`, `SetVehicleExtra` | precisa política de preço e conflitos com carrocerias addon |
| Livery/roof livery | slot 48 e natives de livery | dois mecanismos variam por modelo; requer descoberta sem duplicação |
| Buzina, placa/estilo | slots/plate index disponíveis | buzina requer preview sonoro; texto/identidade de placa não será alterado por tuning |
| Interior/dash/steering/seats e slots especiais | slots 27–47 disponíveis | suporte varia muito entre vanilla, Benny's, Arena e addons |
| Decals por URL | nenhum contrato nesta Wave | M3/M4 explicitamente fora de escopo |

## Limitações honestas

- `GetNumVehicleMods` é descoberta client-side; o servidor não confia nela para preço ou permissão. Um client adulterado pode pedir um índice dentro do limite da whitelist, mas não controla preço, field, writer ou veículo. Natives ignoram índices incompatíveis e o client legítimo exige leitura de volta antes de confirmar aplicação.
- Preview é visual e não persistente, com snapshot completo e rollback em cancelar, enviar orçamento, fechar, trocar abertura, timeout, seleção de personagem e resource stop. A replicação visual OneSync e câmera real ainda exigem homologação FiveM.
- Nenhuma câmera orbital foi criada: não existe protocolo canônico comprovado para ela nesta Wave.
