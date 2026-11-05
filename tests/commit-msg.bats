# .githooks/commit-msg, run against the real .commitlintrc.yml: which commit
# messages the hook lets through and which it rejects.
#
# The hook reaches commitlint through .ci/in-devshell, which runs it directly
# when IN_DEVSHELL is set, so these cases need the suite run inside the
# devShell, as run-tests already says. commitlint reads its config from the
# working directory, so every case runs from the repo root.
#
# setup sets HOOK, the hook under test, and MSG_FILE, the message file a case
# writes and hands to it.

function setup() {
  load 'test_helper/common'
  HOOK="${REPO_DIR}/.githooks/commit-msg"
  MSG_FILE="${BATS_TEST_TMPDIR}/COMMIT_EDITMSG"
  cd "${REPO_DIR}" || return 1
}

# @description Write the given message to MSG_FILE and run the hook on it.
# @arg $1 message the full commit message, header first
function run_hook_on() {
  printf '%s\n' "$1" > "${MSG_FILE}"
  run "${HOOK}" "${MSG_FILE}"
}

@test "commit-msg: an ordinary subject passes" {
  run_hook_on 'feat: add a flag'
  assert_success
}

@test "commit-msg: a scoped subject passes" {
  run_hook_on 'feat(api): add a flag'
  assert_success
}

@test "commit-msg: a breaking-change subject passes" {
  run_hook_on 'feat!: drop a flag'
  assert_success
}

@test "commit-msg: a scoped breaking-change subject passes" {
  run_hook_on 'feat(api)!: drop a flag'
  assert_success
}

@test "commit-msg: a revert subject passes" {
  run_hook_on $'revert: feat: add a flag\n\nThis reverts commit 0123456789abcdef0123456789abcdef01234567.'
  assert_success
}

@test "commit-msg: a subject with no type is rejected" {
  run_hook_on 'add a flag'
  assert_failure 1
}

@test "commit-msg: a subject with an unknown type is rejected" {
  run_hook_on 'feature: add a flag'
  assert_failure 1
}

@test "commit-msg: a body citing an issue mid-paragraph passes" {
  run_hook_on $'fix: tighten a check\n\nThe check missed the case\n#12 describes, so it now covers it.'
  assert_success
}

# footer-leading-blank is a warning in config-conventional, not an error, so the
# commit goes through; what the case pins is that the rule still sees the footer.
@test "commit-msg: a BREAKING CHANGE footer with no blank line above it is flagged" {
  run_hook_on $'feat: drop a flag\n\nThe flag is gone.\nBREAKING CHANGE: the flag is gone'
  assert_success
  assert_output --partial '[footer-leading-blank]'
}
