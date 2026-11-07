# The self-wrap rule: every tracked bash script re-runs itself through
# .ci/in-devshell when IN_DEVSHELL is unset, unless it carries a
# `# devshell-exempt: <reason>` comment.
#
# Three layers. A lint over the tracked scripts holds every one to the rule. A
# stub `nix` first on PATH records the command .ci/in-devshell builds, so every
# wrapped script is shown to re-run itself, through a symlink and from a cwd
# outside any repository, without running anything. .ci/testdata/self-wrap-probe,
# a script that follows the rule and prints where it ended up, is run against
# the real devShell for what only a real run shows: IN_DEVSHELL set, the host
# PATH gone, arguments and exit status intact.
#
# Every run that is meant to reach the wrapper unsets IN_DEVSHELL, and
# GIT_CEILING_DIRECTORIES, which common.bash sets to the repo root and which
# would stop `git` from climbing from .ci/ up to the root the wrapper resolves.
# Payloads are inert: the stub records and exits, the probe prints and exits.
#
# setup sets PROBE, the fixture script, HOST_DIR, an empty directory standing
# in for a host PATH entry, and STUB_DIR, the directory holding the stub nix
# and the few host tools a stubbed run is given.

function setup() {
  load 'test_helper/common'
  PROBE="${REPO_DIR}/.ci/testdata/self-wrap-probe"
  HOST_DIR="${BATS_TEST_TMPDIR}/host"
  STUB_DIR="${BATS_TEST_TMPDIR}/stub"
  mkdir -- "${HOST_DIR}" "${STUB_DIR}" "${BATS_TEST_TMPDIR}/tmp"
  # Records its arguments, one per line, and exits with NIX_STUB_STATUS.
  # shellcheck disable=SC2016 # expanded by the stub, not here
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/nix-args"\nexit "${NIX_STUB_STATUS:-0}"\n' \
    "${BATS_TEST_TMPDIR}" > "${STUB_DIR}/nix"
  chmod +x -- "${STUB_DIR}/nix"
}

# Scripts that run where the devShell cannot take them; each carries its reason
# in a `# devshell-exempt:` comment.
readonly EXEMPT=(
  '.ci/activate-githooks'
  '.ci/run-plugin-validate'
)

# @description Print every tracked executable whose shebang names bash or sh,
#              other than .ci/in-devshell itself.
# @stdout one repo-relative path per line
function tracked_scripts() {
  local meta path first_line interpreter
  while IFS=$'\t' read -r meta path; do
    [[ "${meta%% *}" == '100755' && "${path}" != '.ci/in-devshell' ]] || continue
    IFS= read -r first_line < "${REPO_DIR}/${path}" || continue
    [[ "${first_line}" == '#!'* ]] || continue
    interpreter="${first_line#'#!'}"
    interpreter="${interpreter#/usr/bin/env }"
    interpreter="${interpreter%% *}"
    interpreter="${interpreter##*/}"
    if [[ "${interpreter}" == 'bash' || "${interpreter}" == 'sh' ]]; then
      printf '%s\n' "${path}"
    fi
  done < <(git -C "${REPO_DIR}" ls-files --stage)
}

# @description Succeed if the path is in EXEMPT.
# @arg $1 repo-relative path
function is_exempt() {
  local path
  for path in "${EXEMPT[@]}"; do
    [[ "${path}" == "$1" ]] && return 0
  done
  return 1
}

# @description Run a script outside the devShell boundary against the stub nix:
#              IN_DEVSHELL and GIT_CEILING_DIRECTORIES unset, a scratch TMPDIR,
#              stdin from /dev/null, and a PATH of the stub nix plus only the
#              host tools the self-wrap block and the wrapper use. A script
#              that failed to re-run itself would find none of the tools it
#              calls, so it stops at the first one instead of doing its work.
# @arg $@ the script and its arguments
function run_outside() {
  local tool found
  for tool in bash dirname env git mktemp readlink rm; do
    if [[ ! -e "${STUB_DIR}/${tool}" ]]; then
      found="$(command -v "${tool}")"
      ln --symbolic -- "${found}" "${STUB_DIR}/${tool}"
    fi
  done
  env --unset=IN_DEVSHELL --unset=GIT_CEILING_DIRECTORIES \
    PATH="${STUB_DIR}" TMPDIR="${BATS_TEST_TMPDIR}/tmp" "$@" < '/dev/null'
}

# @description Run a script outside the devShell boundary with only HOST_DIR
#              added to PATH, so the real nix enters the real devShell.
# @arg $@ the script and its arguments
function run_real() {
  env --unset=IN_DEVSHELL --unset=GIT_CEILING_DIRECTORIES \
    PATH="${HOST_DIR}:${PATH}" TMPDIR="${BATS_TEST_TMPDIR}/tmp" "$@" < '/dev/null'
}

# @description Fail unless the probe's last output says it ran inside the
#              devShell with HOST_DIR gone from PATH.
function assert_in_devshell() {
  assert_line 'IN_DEVSHELL=1'
  refute_line --regexp "^PATH=(.*:)?${HOST_DIR}(:.*)?$"
}

@test "self-wrap: every tracked bash script re-runs through in-devshell or says why not" {
  local path text failures=''
  while IFS= read -r path; do
    text="$(grep --invert-match '^[[:space:]]*#' -- "${REPO_DIR}/${path}" || true)"
    if is_exempt "${path}"; then
      grep --quiet --extended-regexp '^# devshell-exempt: [^[:space:]]' -- "${REPO_DIR}/${path}" \
        || failures+=" ${path}(no devshell-exempt reason)"
      continue
    fi
    grep --quiet --extended-regexp '\[\[.*IN_DEVSHELL' <<< "${text}" \
      || failures+=" ${path}(no IN_DEVSHELL test)"
    grep --quiet --extended-regexp '^[[:space:]]*exec .*in-devshell' <<< "${text}" \
      || failures+=" ${path}(no exec of in-devshell)"
  done < <(tracked_scripts)
  assert_equal "${failures}" ''
}

@test "self-wrap: every wrapped script, run through a symlink from outside the repo, hands itself to the devShell" {
  local path link rc head_args failures=''
  mkdir -- "${BATS_TEST_TMPDIR}/elsewhere"
  cd "${BATS_TEST_TMPDIR}/elsewhere"
  while IFS= read -r path; do
    is_exempt "${path}" && continue
    link="${BATS_TEST_TMPDIR}/elsewhere/${path//\//_}"
    ln --symbolic -- "${REPO_DIR}/${path}" "${link}"
    rm --force -- "${BATS_TEST_TMPDIR}/nix-args"
    rc=0
    NIX_STUB_STATUS=7 run_outside "${link}" > "${BATS_TEST_TMPDIR}/out" 2>&1 || rc="$?"
    if [[ "${rc}" != 7 ]]; then
      failures+=" ${path}(exit ${rc}: $(< "${BATS_TEST_TMPDIR}/out"))"
      continue
    fi
    # develop <repo> --ignore-environment ... --command <the script's real path>
    head_args="$(sed --quiet '1p;2p;3p' "${BATS_TEST_TMPDIR}/nix-args" | paste --serial --delimiters=' ')"
    if [[ "${head_args}" != "develop ${REPO_DIR} --ignore-environment" ]] \
      || [[ "$(sed --quiet '/^--command$/{n;p;q}' "${BATS_TEST_TMPDIR}/nix-args")" != "${REPO_DIR}/${path}" ]]; then
      failures+=" ${path}(nix got: $(paste --serial --delimiters=' ' "${BATS_TEST_TMPDIR}/nix-args"))"
    fi
  done < <(tracked_scripts)
  assert_equal "${failures}" ''
  assert_equal "$(find "${BATS_TEST_TMPDIR}/tmp" -mindepth 1 -maxdepth 1)" ''
}

@test "self-wrap: arguments reach the re-run unchanged" {
  local -a got=()
  run run_outside "${REPO_DIR}/run-tests" 'a b' '' '*' 'c'
  assert_success
  mapfile -t got < <(sed --quiet '/^--command$/,$p' "${BATS_TEST_TMPDIR}/nix-args")
  assert_equal "${#got[@]}" 6
  assert_equal "${got[1]}" "${REPO_DIR}/run-tests"
  assert_equal "${got[2]}" 'a b'
  assert_equal "${got[3]}" ''
  assert_equal "${got[4]}" '*'
  assert_equal "${got[5]}" 'c'
}

@test "self-wrap: a hook started by git, with GIT_DIR set, hands itself to its repo's devShell" {
  # Git exports GIT_DIR to the hooks it runs. With GIT_DIR set and no
  # GIT_WORK_TREE, `git rev-parse --show-toplevel` answers with the current
  # directory, whatever directory that is.
  local git_dir
  git_dir="$(git -C "${REPO_DIR}" rev-parse --absolute-git-dir)"
  cd "${REPO_DIR}"
  run run_outside env GIT_DIR="${git_dir}" "${REPO_DIR}/.githooks/pre-push" 'origin' 'url'
  assert_success
  assert_equal "$(sed --quiet '2p' "${BATS_TEST_TMPDIR}/nix-args")" "${REPO_DIR}"
}

@test "self-wrap: a direct run ends inside the devShell with the host PATH gone" {
  cd "${REPO_DIR}"
  run run_real "${PROBE}"
  assert_success
  assert_in_devshell
}

@test "self-wrap: arguments and exit status survive the real re-run" {
  cd "${REPO_DIR}"
  run run_real "${PROBE}" --exit=3 'a b' '' '*'
  assert_failure 3
  assert_in_devshell
  assert_equal "$(grep '^ARG=' <<< "${output}" | paste --serial --delimiters='|')" 'ARG=a b|ARG=|ARG=*'
}

@test "self-wrap: a run through a symlink from the repo root ends inside the devShell" {
  ln --symbolic -- "${PROBE}" "${BATS_TEST_TMPDIR}/link"
  cd "${REPO_DIR}"
  run run_real "${BATS_TEST_TMPDIR}/link" --exit=5 'x'
  assert_failure 5
  assert_in_devshell
  assert_line 'ARG=x'
}

@test "self-wrap: a run through a symlink from outside any repo ends inside the devShell" {
  mkdir -- "${BATS_TEST_TMPDIR}/elsewhere"
  ln --symbolic -- "${PROBE}" "${BATS_TEST_TMPDIR}/elsewhere/link"
  cd "${BATS_TEST_TMPDIR}/elsewhere"
  run run_real "${BATS_TEST_TMPDIR}/elsewhere/link" --exit=6 'y'
  assert_failure 6
  assert_in_devshell
  assert_line 'ARG=y'
}

@test "self-wrap: with IN_DEVSHELL already set there is no re-run" {
  cd "${REPO_DIR}"
  run env IN_DEVSHELL=1 PATH="${STUB_DIR}:${HOST_DIR}:${PATH}" "${PROBE}" 'z'
  assert_success
  assert_line 'ARG=z'
  assert_line --regexp "^PATH=(.*:)?${HOST_DIR}(:.*)?$"
  assert [ ! -e "${BATS_TEST_TMPDIR}/nix-args" ]
}
