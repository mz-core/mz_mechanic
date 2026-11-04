# M2 — checklist de homologação runtime

Nenhum item abaixo foi validado in-game por testes Node/Lua/Playwright.

## Gate P0

1. Deixe `Debug=false` normalmente. Para uma captura controlada, mude temporariamente para `true` e reinicie somente `mz_mechanic`.
2. Abra a oficina com personagem ativo. A mesma request deve mostrar `client_session active=true`, callback com source numérico, `core resolve_identity result_type=table ok=true source_match=true` e, ao final, `complete result=ok` ou um erro real de autorização/veículo.
3. Confirme que `missing_permission`, `not_on_duty`, `vehicle_not_found` e `rate_limited` não aparecem como `session_not_found`.
4. Retorne `Debug=false` após coletar a evidência.

## Preview e rollback

- [ ] Veículo vanilla com opções e veículo sem opções: categorias vazias não aparecem.
- [ ] Veículo addon: índices exibidos correspondem ao modelo.
- [ ] Cancelar, ESC, modo inspecionar, timeout, fechar NUI, trocar veículo, despawn e restart restauram exatamente as props anteriores.
- [ ] Preview não muda `props_json`; guardar/retirar antes do commit restaura o estado persistido.
- [ ] Dois técnicos não conseguem customizar a mesma OS/veículo simultaneamente.

## Orçamento, cobrança e commit

- [ ] Cliente e técnico permanecem na oficina, na bay e no mesmo bucket.
- [ ] Browser não consegue enviar preço, field, slot, placa ou vehicle ID.
- [ ] Alterar revisão, permit, item duplicado ou índice inválido é rejeitado.
- [ ] Duplo clique/replay não duplica orçamento nem cobrança.
- [ ] Cliente vê itens/total e dá consentimento expresso.
- [ ] Saldo insuficiente não aplica props; cobrança aprovada gera um ledger.
- [ ] Falha de aplicação estorna; falha/ambiguidade após débito entra em reconciliação.
- [ ] Commit aplicado persiste após guardar, retirar, respawn, reconnect e txAdmin/restart.
- [ ] Conta de teste confirma engine/brakes/transmission/suspension/armor/turbo sem alterar desgaste mecânico indevidamente.

## NUI/CEF

- [ ] Centro permanece transparente com carro legível em fundos claros e escuros.
- [ ] 1366×768, 1920×1080, 2560×1440, 3440×1440 e viewport baixo sem clipping.
- [ ] Mouse, teclado, ESC contextual e foco retornam ao jogo.
- [ ] “Inspecionar carro” oculta e restaura a UI sem perder carrinho.
- [ ] Não há backdrop preto, captura invisível, CDN ou Node requerido na VPS.
