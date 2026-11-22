# shellcheck shell=bash
# SEUL point d'appel de done_check.sh (run-fullrun.sh, checkpoint.sh, workflow opencode-fullrun.yml le sourcent ;
# un test échoue si un appel direct, non purgé, existe ailleurs dans le dépôt).
#
# done_check.sh est le validateur indépendant : son verdict ne doit jamais dépendre de variables d'environnement que
# le job ($GITHUB_ENV) ou l'agent aurait injectées. On vide donc, à CHAQUE appel, le mode test et les surcharges du
# CLI de verdict (OC_DONE_TEST_MODE, OC_VERDICT_CLI, OC_BUN, OC_VERDICT_TIMEOUT) ; les autres OC_* passent en préfixe :
#   OC_DONE_REPO=... OC_ISA=... fullrun_done_check "$chemin/done_check.sh" 2>/dev/null | head -n1
fullrun_done_check() { # $1 = chemin de done_check.sh
  env -u OC_DONE_TEST_MODE -u OC_VERDICT_CLI -u OC_BUN -u OC_VERDICT_TIMEOUT bash "$1"
}
