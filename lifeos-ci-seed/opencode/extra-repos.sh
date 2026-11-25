#!/usr/bin/env bash
# Dépôts supplémentaires d'un FullRun galass-ci : parse, checkout, contrôles, push, PR brouillon.
#   extra-repos.sh parse     valide EXTRA_REPOS_RAW / TARGET_REPO, écrit la liste normalisée
#   extra-repos.sh checkout  clone chaque dépôt dans EXTRA_ROOT/<repo> (jeton sur stdin)
#   extra-repos.sh check     garde-fous + gitleaks + clé ISA ; écrit l'état (dépôt modifié ou non)
#   extra-repos.sh push      pousse la branche de fonctionnalité des dépôts propres et modifiés
#   extra-repos.sh pr        ouvre une PR en brouillon par dépôt poussé (jamais fusionnée)
#   extra-repos.sh wip-once  un passage de push périodique (wippush) par dépôt supplémentaire
# Jamais de push sur main/master, jamais de --force, jamais de jeton dans une URL, un argument,
# un fichier ou la sortie. Ne sort aucune valeur de secret. Le journal fullrun-logs reste dans
# le dépôt cible : ce script ne touche pas aux branches fullrun-logs/* ni fullrun-prompts.
set +x
set -uo pipefail

# Liste blanche : allowed-repos.sh à côté de ce script (checkout galass-ci ou
# copie figée dans /opt/fullrun-tools). Jamais le répertoire courant.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
allowed="$here/allowed-repos.sh"
[ -f "$allowed" ] || allowed="$here/../targets/allowed-repos.sh"
if [ ! -f "$allowed" ]; then
  echo "allowed-repos.sh introuvable : $allowed" >&2
  exit 1
fi
# shellcheck source=opencode/allowed-repos.sh
# shellcheck disable=SC1091
. "$allowed"
set +e -u -o pipefail
type allowed_repo >/dev/null 2>&1 || { echo "allowed-repos.sh incomplet" >&2; exit 1; }

valid_branch() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$ ]] || return 1
  case "${1,,}" in
    main|master|head|refs/*|*..*|*/|*.lock|fullrun-logs/*|fullrun-prompts|fullrun-prompts/*) return 1 ;;
  esac
  return 0
}

repo_url() {
  printf 'https://github.com/LordThiouk/%s.git' "$1"
}

fail() { echo "$1" >&2; exit 1; }

# Liste normalisée (virgules, sans espaces) sur stdout. Exit 1 si invalide.
parse() {
  local target="${TARGET_REPO:-}" raw="${EXTRA_REPOS_RAW-}" r extras=""
  if [ -n "$target" ]; then
    allowed_repo "$target" || fail "TARGET_REPO invalide"
  fi
  IFS=',' read -r -a ers <<<"$raw"
  for r in "${ers[@]}"; do
    r="${r//[[:space:]]/}"
    [ -n "$r" ] || continue
    allowed_repo "$r" || fail "extra_repos invalide : dépôt non autorisé"
    [ -z "$target" ] || [ "$r" != "$target" ] || fail "extra_repos ne peut pas répéter target_repo"
    case ",$extras," in
      *",$r,"*) fail "extra_repos : dépôt en double" ;;
    esac
    extras="${extras:+$extras,}$r"
  done
  printf '%s\n' "$extras"
}

read_token() {
  TOKEN=""
  if [ "${EXTRA_TOKEN_STDIN:-}" = 1 ]; then
    IFS= read -r TOKEN || true
  elif [ -n "${EXTRA_TOKEN:-}" ]; then
    TOKEN="$EXTRA_TOKEN"
  fi
  # Ne jamais exporter le jeton ; il ne passe à git que par GIT_CONFIG_VALUE (process local).
}

# En-tête d'auth git, jamais en argument ni dans une URL. $TOKEN lu par read_token.
git_auth_env() {
  local auth
  auth=$(printf 'x-access-token:%s' "$TOKEN" | base64 -w0)
  # Masque côté Actions si le hook est dispo ; no-op ailleurs (tests).
  # stdout : Actions n'enregistre le masque que s'il transite par le flux du step.
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::add-mask::$auth"
  fi
  AUTH_HEADER="AUTHORIZATION: basic $auth"
}

# git isolé : pas de config utilisateur, pas de hooks, jeton seulement si $1=auth.
# EXTRA_GIT : binaire de test (jamais en CI) pour intercepter push sans réseau.
run_git() {
  local auth="${1:-}"; shift
  local gitbin="${EXTRA_GIT:-/usr/bin/git}"
  if [ "$auth" = auth ]; then
    [ -n "${TOKEN:-}" ] || return 2
    env -i PATH="${PATH:-/usr/bin:/bin}" HOME="${EXTRA_HOME:-${RUNNER_TEMP:-/tmp}}" \
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
      GIT_CONFIG_COUNT=2 \
      GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null \
      GIT_CONFIG_KEY_1=http.https://github.com/.extraheader GIT_CONFIG_VALUE_1="$AUTH_HEADER" \
      "$gitbin" "$@"
  else
    env -u EXTRA_TOKEN -u TOKEN -u AUTH_HEADER -u PUSH_TOKEN -u GALASS_TOKEN \
      git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"
  fi
}

src_for() {
  local repo="$1"
  if [ -n "${EXTRA_SRC_DIR:-}" ]; then
    printf 'file://%s/%s.git' "$EXTRA_SRC_DIR" "$repo"
  else
    repo_url "$repo"
  fi
}

ensure_state() {
  : "${EXTRA_STATE:?}"
  mkdir -p "$EXTRA_STATE" || exit 3
}

write_state() {
  local repo="$1" key="$2" val="$3"
  ensure_state
  printf '%s\n' "$val" > "$EXTRA_STATE/${repo}.${key}"
}

read_state() {
  local f="$EXTRA_STATE/${1}.${2}"
  [ -f "$f" ] || { printf ''; return 1; }
  tr -d '\n' < "$f"
}

# --- checkout -----------------------------------------------------------------
checkout() {
  : "${EXTRA_ROOT:?}" "${IN_BRANCH:?}"
  valid_branch "$IN_BRANCH" || fail "branche interdite : checkout refusé"
  local list repos r dir src def head
  list="${EXTRA_REPOS-}"
  [ -n "$list" ] || { echo "Aucun dépôt supplémentaire"; return 0; }
  read_token
  if [ -z "${EXTRA_SRC_DIR:-}" ]; then
    [ -n "${TOKEN:-}" ] || fail "jeton absent : checkout des dépôts supplémentaires refusé"
    git_auth_env
  fi
  ensure_state
  mkdir -p "$EXTRA_ROOT"
  IFS=',' read -r -a repos <<<"$list"
  for r in "${repos[@]}"; do
    r="${r//[[:space:]]/}"
    allowed_repo "$r" || fail "dépôt supplémentaire non autorisé"
    [ "$r" != "${TARGET_REPO:-}" ] || fail "extra_repos ne peut pas répéter target_repo"
    dir="$EXTRA_ROOT/$r"
    src=$(src_for "$r")
    rm -rf "$dir"
    mkdir -p "$dir"
    if [ -n "${EXTRA_SRC_DIR:-}" ]; then
      # Tests locaux : clone depuis un dépôt nu file://, sans jeton.
      git clone -q --no-checkout "$src" "$dir" || fail "clone impossible (dépôt supplémentaire)"
      git -C "$dir" remote set-url origin "$src"
      git -C "$dir" fetch -q --no-tags origin '+refs/heads/*:refs/remotes/origin/*' \
        || fail "fetch impossible (dépôt supplémentaire)"
    else
      # Clone ET fetch authentifiés (en-tête via l'environnement du process, jamais dans l'URL).
      # On ne retire l'en-tête local éventuel qu'après le fetch : un fetch nu échoue sur un dépôt privé.
      run_git auth clone -q --no-checkout "$src" "$dir" || fail "clone impossible (dépôt supplémentaire)"
      git -C "$dir" remote set-url origin "$src"
      run_git auth -C "$dir" fetch -q --no-tags origin '+refs/heads/*:refs/remotes/origin/*' \
        || fail "fetch impossible (dépôt supplémentaire)"
      git -C "$dir" config --local --unset-all http.https://github.com/.extraheader 2>/dev/null || true
    fi
    if git -C "$dir" rev-parse --verify -q "origin/$IN_BRANCH" >/dev/null; then
      git -C "$dir" checkout -q -B "$IN_BRANCH" "origin/$IN_BRANCH"
    else
      def=$(git -C "$dir" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
      def="${def#origin/}"
      [ -n "$def" ] || def=$(git -C "$dir" rev-parse --abbrev-ref origin/HEAD 2>/dev/null || true)
      def="${def#origin/}"
      if [ -z "$def" ]; then
        # Dépôt nu de test sans symbolic-ref : prendre la branche par défaut détectable.
        def=$(git -C "$dir" branch -r --format='%(refname:short)' | awk -F/ '/^origin\//{print $2; exit}')
      fi
      [ -n "$def" ] || fail "branche par défaut introuvable (dépôt supplémentaire)"
      case "${def,,}" in
        main|master) ;;
        *) # on part de la branche par défaut, même si son nom n'est pas main
          ;;
      esac
      git -C "$dir" checkout -q -B "$IN_BRANCH" "origin/$def"
    fi
    [ "$(git -C "$dir" rev-parse --abbrev-ref HEAD)" = "$IN_BRANCH" ] \
      || fail "checkout hors de la branche de fonctionnalité"
    git -C "$dir" config user.name "Nix"
    git -C "$dir" config user.email "nix@galass.local"
    printf '#!/bin/sh\necho "push interdit pendant le run opencode" >&2\nexit 1\n' > "$dir/.git/hooks/pre-push"
    chmod +x "$dir/.git/hooks/pre-push"
    if [ -x "$here/merge-signed-carry.sh" ]; then
      "$here/merge-signed-carry.sh" install-hook "$dir" || true
    fi
    head=$(git -C "$dir" rev-parse HEAD)
    write_state "$r" base "$head"
    write_state "$r" head "$head"
    write_state "$r" modified "no"
    echo "Checkout $r @ $IN_BRANCH (${head:0:7})"
  done
}

# --- check --------------------------------------------------------------------
check() {
  : "${EXTRA_ROOT:?}" "${IN_BRANCH:?}" "${EXTRA_STATE:?}"
  valid_branch "$IN_BRANCH" || fail "branche interdite : contrôles refusés"
  local list repos r dir base head G gl cfg_args ignore_dir work S
  list="${EXTRA_REPOS-}"
  [ -n "$list" ] || { echo "Aucun dépôt supplémentaire"; return 0; }
  gl="${EXTRA_GITLEAKS:-gitleaks}"
  G=(git -c core.hooksPath=/dev/null -c core.fsmonitor=false)
  work="${EXTRA_WORK:-${RUNNER_TEMP:-/tmp}/extra-scan}"
  mkdir -p "$work"
  IFS=',' read -r -a repos <<<"$list"
  for r in "${repos[@]}"; do
    r="${r//[[:space:]]/}"
    allowed_repo "$r" || fail "dépôt supplémentaire non autorisé"
    dir="$EXTRA_ROOT/$r"
    [ -d "$dir/.git" ] || fail "checkout absent : $r"
    cd "$dir" || fail "checkout illisible : $r"
    [ "$(git rev-parse --abbrev-ref HEAD)" = "$IN_BRANCH" ] \
      || fail "$r : branche changée, contrôles refusés"
    base=$(read_state "$r" base) || fail "$r : SHA de départ absent"
    [[ "$base" =~ ^[0-9a-f]{40}$ ]] || fail "$r : SHA de départ invalide"
    git merge-base --is-ancestor "$base" HEAD \
      || fail "$r : historique réécrit depuis le SHA de départ, push refusé"
    # Travail non commité : conservé dans un commit explicite pour la reprise.
    # D'abord réintroduire les enregistrements signés du carry déjà présents sur la branche.
    for _msc in "${T:-/opt/fullrun-tools}/merge-signed-carry.sh" "$here/merge-signed-carry.sh"; do
      if [ -x "$_msc" ]; then
        "$_msc" "$dir" || true
        break
      fi
    done
    if [ -n "$("${G[@]}" status --porcelain)" ]; then
      "${G[@]}" add -A
      "${G[@]}" commit -q -m "wip(ci): état non commité à la fin du run (dépôt supplémentaire $r)" || true
    fi
    head=$(git rev-parse HEAD)
    write_state "$r" head "$head"
    if [ "$head" = "$base" ]; then
      write_state "$r" modified "no"
      write_state "$r" check "ok"
      echo "$r : inchangé (${head:0:7})"
      continue
    fi
    if git diff --name-only "$base" HEAD | grep -q '^\.github/workflows/'; then
      write_state "$r" check "workflows"
      write_state "$r" modified "yes"
      fail "$r : modification de .github/workflows, push refusé"
    fi
    # gitleaks + clé ISA sur les seuls commits du run, dans un dépôt nu neuf.
    cfg_args=()
    if git cat-file -e "$base:.gitleaks.toml" 2>/dev/null; then
      git show "$base:.gitleaks.toml" > "$work/gitleaks.toml"
      cfg_args=(--config "$work/gitleaks.toml")
    fi
    ignore_dir="$work/gl-ignore-$r"
    rm -rf "$ignore_dir"; mkdir -p "$ignore_dir"
    if git cat-file -e "$base:.gitleaksignore" 2>/dev/null; then
      git show "$base:.gitleaksignore" > "$ignore_dir/.gitleaksignore"
    fi
    S="$work/scan-$r.git"
    rm -rf "$S"
    git init -q --bare "$S"
    if ! git -C "$S" fetch -q --no-tags "file://$dir" "+refs/heads/$IN_BRANCH:refs/heads/$IN_BRANCH" >/dev/null 2>&1 \
       || [ "$(git -C "$S" rev-parse "refs/heads/$IN_BRANCH")" != "$head" ]; then
      write_state "$r" check "copie"
      fail "$r : copie de contrôle impossible, push refusé"
    fi
    if ! "$gl" git "${cfg_args[@]}" --gitleaks-ignore-path "$ignore_dir" \
         --log-opts="$base..refs/heads/$IN_BRANCH" --redact --no-banner \
         --report-path "$work/gitleaks-$r.json" "$S" >/dev/null 2>&1; then
      write_state "$r" check "gitleaks"
      write_state "$r" modified "yes"
      fail "$r : gitleaks a trouvé un secret probable, push refusé"
    fi
    if [ -n "${EXTRA_ISA_KEY_FILE:-}" ] && [ -s "${EXTRA_ISA_KEY_FILE}" ]; then
      git -C "$S" log -p --binary --no-ext-diff --no-textconv --format= "$base..refs/heads/$IN_BRANCH" \
        > "$work/run-$r.diff"
      if grep -qiF -- "$(tr -d '\n' < "$EXTRA_ISA_KEY_FILE")" "$work/run-$r.diff"; then
        rm -f "$work/run-$r.diff"
        write_state "$r" check "cle"
        write_state "$r" modified "yes"
        fail "$r : la clé ISA apparaît dans les commits, push refusé"
      fi
      rm -f "$work/run-$r.diff"
    fi
    write_state "$r" modified "yes"
    write_state "$r" check "ok"
    echo "$r : modifié, contrôles OK (${base:0:7}..${head:0:7})"
  done
}

# --- push ---------------------------------------------------------------------
push_extras() {
  : "${EXTRA_ROOT:?}" "${IN_BRANCH:?}" "${EXTRA_STATE:?}"
  valid_branch "$IN_BRANCH" || fail "branche interdite : push refusé"
  local list repos r dir head base remote B work=0
  list="${EXTRA_REPOS-}"
  [ -n "$list" ] || { echo "Aucun dépôt supplémentaire"; return 0; }
  read_token
  if [ -z "${EXTRA_SRC_DIR:-}" ]; then
    [ -n "${TOKEN:-}" ] || fail "jeton absent : push des dépôts supplémentaires refusé"
    git_auth_env
  fi
  IFS=',' read -r -a repos <<<"$list"
  for r in "${repos[@]}"; do
    r="${r//[[:space:]]/}"
    allowed_repo "$r" || fail "dépôt supplémentaire non autorisé"
    [ "$(read_state "$r" check 2>/dev/null || true)" = ok ] \
      || fail "$r : contrôles non faits ou en échec, push refusé"
    [ "$(read_state "$r" modified)" = yes ] || { echo "$r : inchangé, pas de push"; continue; }
    dir="$EXTRA_ROOT/$r"
    head=$(read_state "$r" head)
    [[ "$head" =~ ^[0-9a-f]{40}$ ]] || fail "$r : SHA contrôlé absent, push refusé"
    [ "$(git -C "$dir" rev-parse HEAD)" = "$head" ] \
      || fail "$r : le HEAD a bougé après les contrôles, push refusé"
    [ "$(git -C "$dir" rev-parse --abbrev-ref HEAD)" = "$IN_BRANCH" ] \
      || fail "$r : branche changée, push refusé"
    if [ -n "${EXTRA_SRC_DIR:-}" ]; then
      remote=$(src_for "$r")
    else
      remote=$(repo_url "$r")
    fi
    B="${EXTRA_WORK:-${RUNNER_TEMP:-/tmp}/extra-push}/$r.git"
    rm -rf "$B"
    git init -q --bare "$B"
    if ! git -C "$B" -c protocol.file.allow=always fetch -q --no-tags \
         "file://$dir" "+refs/heads/$IN_BRANCH:refs/heads/$IN_BRANCH" >/dev/null 2>&1 \
       || [ "$(git -C "$B" rev-parse "refs/heads/$IN_BRANCH")" != "$head" ]; then
      fail "$r : copie locale impossible, push refusé"
    fi
    if [ -n "${EXTRA_SRC_DIR:-}" ]; then
      git -C "$B" -c protocol.file.allow=always push --no-verify --porcelain \
        "$remote" "$head:refs/heads/$IN_BRANCH" >/dev/null 2>&1 \
        || fail "$r : push refusé (branche avancée ailleurs) : rien n'a été forcé"
    else
      run_git auth -C "$B" push --no-verify --porcelain \
        "$remote" "$head:refs/heads/$IN_BRANCH" >/dev/null 2>&1 \
        || fail "$r : push refusé (branche avancée ailleurs, ou jeton sans droit) : rien n'a été forcé"
    fi
    write_state "$r" pushed "yes"
    work=1
    echo "Push OK : $r@$IN_BRANCH → ${head:0:7}"
  done
  [ "$work" = 1 ] || echo "Aucun dépôt supplémentaire à pousser"
}

# --- PR brouillon -------------------------------------------------------------
pr_extras() {
  : "${IN_BRANCH:?}" "${EXTRA_STATE:?}"
  valid_branch "$IN_BRANCH" || fail "branche interdite : pas de PR"
  local list repos r base existing url ghbin
  list="${EXTRA_REPOS-}"
  [ -n "$list" ] || { echo "Aucun dépôt supplémentaire"; return 0; }
  ghbin="${EXTRA_GH:-gh}"
  command -v "$ghbin" >/dev/null 2>&1 || { echo "gh absent : pas de PR supplémentaires" >&2; return 0; }
  read_token
  if [ -z "${EXTRA_SRC_DIR:-}" ] && [ -z "${TOKEN:-}" ]; then
    echo "jeton absent : pas de PR supplémentaires" >&2
    return 0
  fi
  IFS=',' read -r -a repos <<<"$list"
  for r in "${repos[@]}"; do
    r="${r//[[:space:]]/}"
    allowed_repo "$r" || continue
    [ "$(read_state "$r" pushed 2>/dev/null || true)" = yes ] || { echo "$r : pas poussé, pas de PR"; continue; }
    base="${IN_BASE:-}"
    if [ -z "$base" ]; then
      if [ -n "${EXTRA_SRC_DIR:-}" ]; then
        base="${EXTRA_PR_BASE:-main}"
      else
        base=$(GH_TOKEN="$TOKEN" "$ghbin" api "repos/LordThiouk/$r" --jq .default_branch 2>/dev/null) || base=""
      fi
    fi
    [[ "$base" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$ ]] \
      || { echo "$r : branche cible introuvable, pas de PR" >&2; continue; }
    if [ -n "${EXTRA_SRC_DIR:-}" ]; then
      existing=$("$ghbin" pr list --repo "LordThiouk/$r" --head "$IN_BRANCH" \
                   --state open --json number --jq 'length' 2>/dev/null) || existing=0
    else
      existing=$(GH_TOKEN="$TOKEN" "$ghbin" pr list --repo "LordThiouk/$r" --head "$IN_BRANCH" \
                   --state open --json number --jq 'length' 2>/dev/null) || existing=0
    fi
    if [ "$existing" != 0 ]; then
      echo "$r : PR déjà ouverte pour $IN_BRANCH, rien à créer"
      continue
    fi
    if [ -n "${EXTRA_SRC_DIR:-}" ]; then
      url=$("$ghbin" pr create --repo "LordThiouk/$r" --draft \
              --base "$base" --head "$IN_BRANCH" \
              --title "FullRun ${IN_JOB:-job} (${IN_BRANCH})" \
              --body "Run FullRun automatique (dépôt supplémentaire). PR en brouillon : revue humaine obligatoire, jamais de fusion automatique." 2>/dev/null) || url=""
    else
      url=$(GH_TOKEN="$TOKEN" "$ghbin" pr create --repo "LordThiouk/$r" --draft \
              --base "$base" --head "$IN_BRANCH" \
              --title "FullRun ${IN_JOB:-job} (${IN_BRANCH})" \
              --body "Run FullRun automatique (dépôt supplémentaire). PR en brouillon : revue humaine obligatoire, jamais de fusion automatique." 2>/dev/null) || url=""
    fi
    [ -n "$url" ] || { echo "$r : création de la PR impossible" >&2; continue; }
    write_state "$r" pr "$url"
    echo "PR en brouillon : $url"
  done
}

# --- wip périodique -----------------------------------------------------------
# Un passage wippush.sh once par dépôt supplémentaire : même garde-fous (gitleaks,
# clé ISA, jamais main, jamais --force). Les échecs sont des lignes [suivi], jamais fatals.
wip_once() {
  : "${EXTRA_ROOT:?}" "${IN_BRANCH:?}" "${EXTRA_STATE:?}"
  valid_branch "$IN_BRANCH" || fail "branche interdite : wip refusé"
  local list repos r dir base wipsh st remote job run
  list="${EXTRA_REPOS-}"
  [ -n "$list" ] || { echo "Aucun dépôt supplémentaire"; return 0; }
  wipsh="${EXTRA_WIPPUSH:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wippush.sh}"
  [ -f "$wipsh" ] || fail "wippush.sh introuvable"
  job="${IN_JOB:-${WIP_JOB:-wipjob}}"
  run="${IN_RUN:-${WIP_RUN:-1}}"
  read_token
  IFS=',' read -r -a repos <<<"$list"
  for r in "${repos[@]}"; do
    r="${r//[[:space:]]/}"
    allowed_repo "$r" || fail "dépôt supplémentaire non autorisé"
    dir="$EXTRA_ROOT/$r"
    if [ ! -d "$dir/.git" ]; then
      echo "[suivi] $r : checkout absent, wip ignoré"
      continue
    fi
    if [ "$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)" != "$IN_BRANCH" ]; then
      echo "[suivi] $r : hors de $IN_BRANCH, wip ignoré"
      continue
    fi
    base=$(read_state "$r" base 2>/dev/null || true)
    st="${EXTRA_WIP_STATE:-${EXTRA_STATE}/wip}/$r"
    mkdir -p "$st" || fail "état wip inaccessible"
    if [ -n "${EXTRA_SRC_DIR:-}" ]; then
      remote=$(src_for "$r")
    else
      remote=$(repo_url "$r")
    fi
    # Jeton uniquement sur stdin de wippush ; retiré de l'environnement du fils.
    if [ -n "${TOKEN:-}" ]; then
      printf '%s\n' "$TOKEN" | \
        WIP_TOKEN_STDIN=1 \
        WIP_STATE="$st" WIP_REPO="$dir" WIP_BRANCH="$IN_BRANCH" \
        WIP_JOB="$job" WIP_RUN="$run" WIP_REMOTE="$remote" \
        WIP_BASE_SHA="$base" \
        WIP_GITLEAKS="${EXTRA_GITLEAKS:-${WIP_GITLEAKS:-gitleaks}}" \
        WIP_GL_CONFIG="${WIP_GL_CONFIG:-}" \
        WIP_GL_IGNORE="${WIP_GL_IGNORE:-}" \
        WIP_ISA_KEY_FILE="${EXTRA_ISA_KEY_FILE:-${WIP_ISA_KEY_FILE:-}}" \
        env -u TOKEN -u EXTRA_TOKEN -u AUTH_HEADER -u GALASS_TOKEN -u PUSH_TOKEN \
        bash "$wipsh" once
    else
      WIP_TOKEN_STDIN=0 \
        WIP_STATE="$st" WIP_REPO="$dir" WIP_BRANCH="$IN_BRANCH" \
        WIP_JOB="$job" WIP_RUN="$run" WIP_REMOTE="$remote" \
        WIP_BASE_SHA="$base" \
        WIP_GITLEAKS="${EXTRA_GITLEAKS:-${WIP_GITLEAKS:-gitleaks}}" \
        WIP_GL_CONFIG="${WIP_GL_CONFIG:-}" \
        WIP_GL_IGNORE="${WIP_GL_IGNORE:-}" \
        WIP_ISA_KEY_FILE="${EXTRA_ISA_KEY_FILE:-${WIP_ISA_KEY_FILE:-}}" \
        bash "$wipsh" once </dev/null
    fi
  done
}

cmd="${1:-}"
case "$cmd" in
  parse) parse ;;
  checkout) checkout ;;
  check) check ;;
  push) push_extras ;;
  pr) pr_extras ;;
  wip-once) wip_once ;;
  *) echo "usage: extra-repos.sh parse|checkout|check|push|pr|wip-once" >&2; exit 2 ;;
esac
