# Checklist de homologação FiveM

Testes offline e Playwright não equivalem a runtime. Execute este roteiro em servidor descartável depois de aplicar o SQL manualmente.

## Um jogador

- [ ] Resource inicia depois de dependências e informa `M1 ready`.
- [ ] NUI permanece invisível/transparenta antes de abrir e não captura cursor.
- [ ] F7/radial selecionam o veículo networked mais próximo quando ele está a até 8 m; sem veículo, abrem duty/fila sem inventar contexto veicular; fora da oficina o servidor rejeita.
- [ ] Target entrega a entidade exata para “Diagnóstico e ordem de serviço”; o contexto aceita veículo próximo fora do box, enquanto a criação da OS ainda exige vaga de serviço.
- [ ] “MZ Automotive — tuning” aparece apenas para veículo parado dentro de uma das vagas configuradas.
- [ ] Blip identifica a oficina, mas não abre interface nem concede autorização ao atravessar a área.
- [ ] Atendimento e Tuning nunca aparecem juntos nem mantêm dois focos/cursor preso.
- [ ] Tuning sem veículo apresenta retorno ao Atendimento; com veículo e sem OS mostra catálogo somente leitura, sem preview, orçamento, cobrança ou persistência.
- [ ] Conferir visualmente os centros `bay_1 = -211.67, -1324.81, 30.26` e `bay_2 = -196.35, -1324.20, 30.89`; registrar distância exibida com `Debug = true` sem ampliar o raio antes da calibração.
- [ ] ESC fecha diálogo antes do painel e sempre devolve foco.
- [ ] Personagem sem organização/permissão não assume, diagnostica ou executa OS.
- [ ] Mecânico autorizado alterna duty no ponto aceito por `mz_org`.
- [ ] Veículo fora da bay, de outro bucket ou sem acesso é recusado.
- [ ] Reinício com OS `in_progress`/`pending_apply` leva a reconciliação, sem concluir ou estornar automaticamente.

## Dois jogadores: cliente + técnico

- [ ] Cliente abre uma única OS para seu veículo persistente em estado `out`.
- [ ] Segundo cliente/técnico não forja `vehicle_id`, placa, preço, revisão ou serviço pelo callback.
- [ ] Dois técnicos concorrentes: só um é atribuído e só um ganha a execução financeira.
- [ ] Técnico diagnostica; orçamento exibido corresponde ao dano lido no servidor.
- [ ] Somente o cliente da OS aceita o orçamento, presencialmente e no mesmo bucket.
- [ ] Saldo insuficiente falha sem aplicar reparo gratuito.
- [ ] Pagamento aprovado gera um único ledger mesmo após retry.
- [ ] Reparo aplica natives, persiste engine/body via `mz_vehicles` e só então completa/libera lock.
- [ ] Aplicação tenta `mz_animations:mecanico2`; com o resource ausente, o cenário native mantém o fluxo sem alterar autoridade.
- [ ] Guardar/retirar e respawn do veículo preservam engine/body reparados.
- [ ] Cancelamento pré-pagamento libera lock; cancelamento pós-início financeiro é bloqueado.
- [ ] Disconnect do cliente/técnico e despawn do veículo seguem os estados documentados.

## Evidências

Guarde console server/client, IDs de OS/operação, linhas do ledger e screenshots em `mz_testkit/results/mz_mechanic/`. Não marque “FiveM PASS” sem concluir este roteiro no jogo.
