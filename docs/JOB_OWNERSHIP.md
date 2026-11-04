# Ownership do trabalho de mecânico

## Separação de responsabilidades

- **Atividade de mecânico:** `mz_mechanic` possui fila, atribuição do técnico, diagnóstico, orçamento, consentimento, execução e encerramento.
- **Empregadora/ACL:** `mz_org` possui a organização `mechanic`, membership, cargos, permissões e duty.
- **Profissões genéricas:** `mz_jobs` permanece candidato futuro. Na auditoria atual ele declara `playableJobs=false`; não há adapter de mutação inventado.

## Autorização padrão

O personagem precisa ter membership ativa na organização configurada, a permissão `mechanic.repair.basic` e duty ativo. Cada mutação reconsulta o contexto no servidor e valida oficina, bucket, proximidade, OS, técnico atribuído e revisão.

O cliente pode criar uma OS e aceitar seu próprio orçamento sem receber papel de mecânico. Acesso ao veículo é decidido por `mz_vehicles:CanAccessVehicle`.

## Duty

Entrada/saída de serviço chama `mz_org:SetSelfOrgDutyAtPoint`. Esse owner aplica suas próprias regras e proximidade. O estado exibido é novamente lido de `GetPlayerOrgContext`; a NUI não é fonte de verdade.

## Fallback standalone

`Authorization.Standalone.Enabled` é `false`. Quando explicitamente habilitado, o vínculo fica apenas em `mz_mechanic_staff`, não representa job/duty global e não substitui `mz_org`.

Os comandos `mzmechanic_bind` e `mzmechanic_unbind` aceitam console ou ator com `staff.orgs.manage`/ACE configurado. O vínculo usa `citizenid`, oficina existente, audit log do Core e duty efêmero por sessão. Não há auto-onboarding.

## Futuro adapter `mz_jobs`

Um adapter só deve ser ligado quando `GetJobsCapabilities().playableJobs == true` e existir contrato público server-side para vínculo e duty. A troca deve preservar os mesmos checks de revisão/posição e não duplicar membership ou identidade.
