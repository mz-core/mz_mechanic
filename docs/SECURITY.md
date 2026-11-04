# Segurança

## Fronteiras de confiança

O browser envia somente intenção. O servidor rejeita campos desconhecidos e nunca aceita preço, placa, `vehicle_id`, serviço, permissão, posição ou estado calculados pela NUI.

Para mutações, o servidor valida conforme o caso:

- identidade canônica e vínculo do autor;
- membership, permissão e duty do mecânico;
- cliente proprietário/autorizado e consentimento explícito;
- oficina, bay, distância, routing bucket e entidade veicular;
- ID persistente + placa conferidos contra `mz_vehicles`;
- técnico atribuído, estado e revisão otimista da OS;
- catálogo e preço calculados server-side;
- operação financeira e recibo idempotentes.

## Concorrência e recuperação

- `lock_vehicle_id` possui índice único: uma OS ativa por veículo.
- A transição `accepted → in_progress` acontece por CAS antes do débito; somente o vencedor cobra.
- Toda transição grava chave/fingerprint no registro da OS e tenta espelhar em journal/evento.
- Estados financeiros incertos e aplicação já ocorrida nunca liberam lock nem estornam por suposição: vão para `pending_reconciliation`.
- Expiração antes do pagamento falha e libera lock; depois do início financeiro reconcilia.
- Disconnect do técnico desatribui estados seguros e reconcilia estados com pagamento/aplicação.

## Dados expostos

Respostas públicas removem token de aplicação e recibos internos da economia. A NUI recebe status/valor da cobrança, não metadados ou saldo do ledger.

## Limitações deliberadas

- Não há endpoint de resolução automática de `pending_reconciliation`; a análise é administrativa/manual nesta Wave.
- Standalone e personalização estão OFF por padrão.
- Não existem endpoints canary novos nem fluxo client legítimo para canaries existentes.
