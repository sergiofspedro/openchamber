# goal: unificar stores — update_goal escreve num store, serve metadata.openchamber.goal noutro (dispatcher I3d le o segundo)

### 1. Defeito

As tools de goal do orchestrator (`set_goal` / `create_goal` / `update_goal`)
escrevem o estado de goal num store; o dispatcher desta instancia le OUTRO:
`session_goal_status()` faz `GET /session/<id>` e le
`metadata.openchamber.goal.status`.

Quando os dois stores discordam, o gate `I3d` de `prev_wave_incomplete` segura o
pipeline para sempre, sem sinalizacao nenhuma ao dono.

**Exemplo concreto:** wave 58, 2026-10-06 — hold `I3d` sem alerta. Foi essa a
origem da C22 no projeto do utilizador (a mitigacao local foi um alerta de
telegram quando o gate segura >2h; nao resolve a causa).

### 2. Proposta de unificacao — fonte unica

Uma de:

- **(a)** as tools de goal passam a escrever na metadata serve
  (`metadata.openchamber.goal`), de forma que `GET /session/<id>` seja a unica
  fonte de verdade; ou
- **(b)** o serve expoe uma rota de goal status (`GET /session/<id>/goal`) e as
  tools usam a MESMA rota — o dispatcher deixa de ler um campo que so ele
  interpreta.

(b) e a preferida se o store das tools for intencional (estado de execucao com
granularidade que a metadata nao modela): obriga a um contrato partilhado em vez
de duplicar escrita.

### 3. Contexto

- Pipeline auto-dispatch desta instancia; gate em
  `~/.config/opencode/dispatch/lib/common.sh` (`prev_wave_incomplete`, ramo `I3d`).
- E um seed de candidata — sem forks, sem PR de codigo. Nao ha patch proposto aqui.
