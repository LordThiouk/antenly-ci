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
