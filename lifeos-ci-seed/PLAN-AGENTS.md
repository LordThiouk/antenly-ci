# Plan — un workflow par agent LifeOS (FullRun)

Source : `LordThiouk/lifeos` (privé) non clonable ici (aucun `CI_TOKEN`/`GH_TOKEN` → 404) ; inventaire
reconstruit depuis `opencode/step-agents.sh`, `_next.yml`, `opencode/config/opencode.json` et
`opencode/ci-preamble.md` d'antenly-ci. Skill FullRun : `opencode/skills/FullRunWorkflow/SKILL.md`
(chemin à confirmer). Auteur : Papa Diop.

## Agents

| Agent | Rôle (une ligne) | Étape FullRun | Fichier source lifeos |
| --- | --- | --- | --- |
| Nix/LifeOS | Agent principal : applique l'Algorithm LifeOS et dispatche les sous-agents | toutes (plan→close), orchestration | `opencode/nix-lifeos.prompt.md` |
| Vera | Plan / intake : ISA, ISC, périmètre | 2 `vera` (validé par Algorithm) | `opencode/agents/Vera.md` |
| Algorithm | Validateur des étapes de plan | 0-2 `scaffold`/`completeness_pre`/`vera` | `opencode/agents/Algorithm.md` |
| Serena | Architecture, spec, dispatch map | 3 `serena` (validé par Architect) | `opencode/agents/Serena.md` |
| Architect | Concepteur système (lecture seule) | 3 `serena` | `opencode/agents/Architect.md` |
| Engineer | Implémentation TDD (logique) | 4 `build` | `opencode/agents/Engineer.md` |
| Anvil | Génération de code long contexte (logique) | 4 `build` | `opencode/agents/Anvil.md` |
| Forge | Producteur/auditeur de code | 4 `build` (`forge-code`), 5 `verify` (`forge-audit`) | `opencode/agents/Forge.md` |
| Aditi | Construction UI | 4 `build` (`aditi-ui`) | `opencode/agents/Aditi.md` |
| Designer | UX/UI, specs visuelles | 4 `build` (UI) | `opencode/agents/Designer.md` |
| Silas | Sécurité offensive, audit | 5 `verify` | `opencode/agents/Silas.md` |
| code-reviewer | Revue de code | 5 `verify` (`code-review`) | `opencode/agents/code-reviewer.md` |
| Max | Porte finale et clôture | 6 `max`, 7 `close` | `opencode/agents/Max.md` |

## Workflows à créer

Un wrapper `.github/workflows/agent-<slug>.yml` par agent (`nix`, `vera`, `algorithm`, `serena`,
`architect`, `engineer`, `anvil`, `forge`, `aditi`, `designer`, `silas`, `code-reviewer`, `max`).
Aucune duplication : chaque wrapper ne fait que `uses: ./.github/workflows/_agent-run.yml` avec
`agent`, `phase`, `step`, `target_agent`, puis `uses: ./.github/workflows/_next.yml` si chaînage.
`_agent-run.yml` exécute les étapes du skill FullRun : validation des entrées → checkout lifeos-ci
(outils) → checkout du dépôt cible → clone lifeos lecture seule → installation bun/opencode →
gel des outils root → préflight `FullRunPreflight.ts` → prompt + ISA → `run-fullrun.sh` (dispatch
de l'agent) → `done_check.sh` (verdict réel) → carry/checkpoint signé → push/PR si `lifeos_write`
→ notification. Les noms sont slugifiés (`Nix/LifeOS`→`nix`, `code-reviewer` inchangé).

## Tâches à lancer en parallèle

- Vague 0 (séquentielle) : `agent-vera` → carry plan.
- Vague 1 : `agent-serena` (dépend de Vera).
- Vague 2 (parallèle, build) : `agent-engineer`, `agent-anvil`, `agent-forge` (code),
  `agent-aditi`, `agent-designer` — dépendent de Serena ; parallélisme réel seulement si les
  scopes `[scope:…]` sont disjoints et les branches séparées.
- Vague 3 (parallèle, verify) : `agent-silas`, `agent-code-reviewer`, `agent-forge` (audit) —
  dépendent du build.
- Vague 4 : `agent-max` (dépend de tous les verify), puis `agent-close` (même workflow Max).
- `agent-nix` orchestre, ne se lance pas en parallèle des vagues.

## Questions ouvertes

- Clone lifeos impossible (dépôt privé, aucun `CI_TOKEN`/`GH_TOKEN` exposé) : chemins `agents/*.md`
  et noms exacts à confirmer ; le mapping vient de `step-agents.sh`/`_next.yml`.
- Vera/Serena : agents ou phases ? `step-agents.sh` attribue leurs verdicts à Algorithm/Architect.
- Faut-il un workflow pour les agents hors FullRun (Artist, chercheurs, BrowserAgent déprécié) ?
- `_agent-run.yml` actuel n'expose pas `stop_after_step`/`target_agent`/`chain_phase` : inputs à
  ajouter pour un vrai run par agent.
- Parallélisme build : branches/PR séparées nécessaires, sinon conflits de push et de carry.
- `agent-close` séparé ou étape de `agent-max` ? Le pipeline fusionne 6 `max` et 7 `close`.
