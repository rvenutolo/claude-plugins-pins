# .ci/check-readme-sync, against a fixture root holding a manifest, an upstream
# map and a README in BATS_TEST_TMPDIR.
#
# `run --separate-stderr` is a bats 1.5.0 flag: the check prints every verdict
# on stderr.
bats_require_minimum_version 1.5.0

function setup() {
  load 'test_helper/common'
  CHECK="${REPO_DIR}/.ci/check-readme-sync"
  ROOT="${BATS_TEST_TMPDIR}/root"
  mkdir --parents "${ROOT}/.claude-plugin" "${ROOT}/.ci"
  cat > "${ROOT}/.claude-plugin/marketplace.json" << 'JSON'
{"name": "m", "plugins": [
  {"name": "alpha", "description": "First plugin.",
   "source": {"source": "github", "repo": "acme/alpha", "ref": "v1.2.0", "sha": "0"}},
  {"name": "beta", "description": "Second plugin.",
   "source": {"source": "github", "repo": "acme/beta", "ref": "v1.10.0", "sha": "0"}}
]}
JSON
  cat > "${ROOT}/.ci/upstream-plugins.json" << 'JSON'
{"alpha": {"plugin": "alpha", "track": "tag"},
 "beta": {"plugin": "beta", "track": "tag"},
 "gamma": {"plugin": "gamma", "track": "branch"}}
JSON
  ROW_ALPHA='| [alpha](https://github.com/acme/alpha) | v1.2.0 | First plugin. |'
  ROW_BETA='| [beta](https://github.com/acme/beta) | v1.10.0 | Second plugin. |'
}

# @description Write the fixture README: prose, the markers, and the given
#              table rows between them under the standard header.
# @arg $@ rows the table rows, one argument per row
function write_readme() {
  {
    printf '# Title\n\nSome prose.\n\n<!-- plugins:start -->\n<!-- prettier-ignore -->\n'
    printf '| Plugin | Version | Description |\n| --- | --- | --- |\n'
    if (($# > 0)); then
      printf '%s\n' "$@"
    fi
    printf '\n<!-- plugins:end -->\n\nMore prose.\n'
  } > "${ROOT}/README.md"
}

@test "readme-sync: passes when table matches" {
  write_readme "${ROW_ALPHA}" "${ROW_BETA}"
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_success
  [[ "${stderr}" == *'OK:'* ]]
}

@test "readme-sync: fails on a missing row" {
  write_readme "${ROW_ALPHA}"
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_failure 1
  [[ "${stderr}" == *'FAIL: beta:'* ]]
}

@test "readme-sync: fails on an extra row" {
  write_readme "${ROW_ALPHA}" "${ROW_BETA}" '| [gamma](https://github.com/acme/gamma) | v1.0.0 | Third. |'
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_failure 1
  [[ "${stderr}" == *'FAIL:'*'gamma'* ]]
}

@test "readme-sync: fails on rows out of order" {
  write_readme "${ROW_BETA}" "${ROW_ALPHA}"
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_failure 1
  [[ "${stderr}" == *'FAIL: alpha:'* ]]
  [[ "${stderr}" == *'FAIL: beta:'* ]]
}

@test "readme-sync: fails when version differs from ref" {
  write_readme "${ROW_ALPHA}" '| [beta](https://github.com/acme/beta) | v1.9.0 | Second plugin. |'
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_failure 1
  [[ "${stderr}" == *'FAIL: beta:'* ]]
  [[ "${stderr}" == *'v1.9.0'* ]]
  [[ "${stderr}" == *'v1.10.0'* ]]
}

@test "readme-sync: fails when description differs" {
  write_readme "${ROW_ALPHA}" '| [beta](https://github.com/acme/beta) | v1.10.0 | Stale text. |'
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_failure 1
  [[ "${stderr}" == *'FAIL: beta:'* ]]
  [[ "${stderr}" == *'Stale text.'* ]]
}

@test "readme-sync: fails when the repo link differs" {
  write_readme "${ROW_ALPHA}" '| [beta](https://github.com/acme/other) | v1.10.0 | Second plugin. |'
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_failure 1
  [[ "${stderr}" == *'FAIL: beta:'* ]]
}

@test "readme-sync: fails when markers are missing" {
  printf '# Title\n\n%s\n%s\n' "${ROW_ALPHA}" "${ROW_BETA}" > "${ROOT}/README.md"
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_failure 1
  [[ "${stderr}" == *'FAIL:'*'plugins:start'* ]]
  [[ "${stderr}" != *'ERROR:'* ]]
}

@test "readme-sync: fails when the README is missing" {
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_failure 1
  [[ "${stderr}" == *'FAIL:'* ]]
  [[ "${stderr}" != *'ERROR:'* ]]
}

@test "readme-sync: passes for a row with v1.10.0" {
  write_readme "${ROW_ALPHA}" "${ROW_BETA}"
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_success
}

@test "readme-sync: escapes a pipe in a description" {
  cat > "${ROOT}/.claude-plugin/marketplace.json" << 'JSON'
{"name": "m", "plugins": [
  {"name": "alpha", "description": "Blocks a | b.",
   "source": {"source": "github", "repo": "acme/alpha", "ref": "v1.2.0", "sha": "0"}}
]}
JSON
  write_readme '| [alpha](https://github.com/acme/alpha) | v1.2.0 | Blocks a \| b. |'
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_success
}

@test "readme-sync: exits 2 on a surplus argument" {
  run --separate-stderr "${CHECK}" "${ROOT}" extra
  assert_failure 2
  [[ "${stderr}" == *'usage:'* ]]
}

@test "readme-sync: fails on an unreadable manifest" {
  printf 'not json\n' > "${ROOT}/.claude-plugin/marketplace.json"
  write_readme
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_failure 1
  [[ "${stderr}" == *'FAIL:'* ]]
  [[ "${stderr}" != *'ERROR:'* ]]
}

@test "readme-sync: branch entry row shows the full sha" {
  local -r sha='2c606141936f1eeef17fa3043a72095b4765b9c2'
  cat > "${ROOT}/.claude-plugin/marketplace.json" << JSON
{"name": "m", "plugins": [
  {"name": "gamma", "description": "Third plugin.",
   "source": {"source": "github", "repo": "acme/gamma", "ref": "main", "sha": "${sha}"}}
]}
JSON
  write_readme "| [gamma](https://github.com/acme/gamma) | ${sha} | Third plugin. |"
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_success
}

@test "readme-sync: fails when a branch entry row shows the ref" {
  local -r sha='2c606141936f1eeef17fa3043a72095b4765b9c2'
  cat > "${ROOT}/.claude-plugin/marketplace.json" << JSON
{"name": "m", "plugins": [
  {"name": "gamma", "description": "Third plugin.",
   "source": {"source": "github", "repo": "acme/gamma", "ref": "main", "sha": "${sha}"}}
]}
JSON
  write_readme '| [gamma](https://github.com/acme/gamma) | main | Third plugin. |'
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_failure 1
  [[ "${stderr}" == *'FAIL: gamma:'*"${sha}"* ]]
}

@test "readme-sync: fails when a branch entry row shows a short sha" {
  local -r sha='2c606141936f1eeef17fa3043a72095b4765b9c2'
  cat > "${ROOT}/.claude-plugin/marketplace.json" << JSON
{"name": "m", "plugins": [
  {"name": "gamma", "description": "Third plugin.",
   "source": {"source": "github", "repo": "acme/gamma", "ref": "main", "sha": "${sha}"}}
]}
JSON
  write_readme '| [gamma](https://github.com/acme/gamma) | 2c60614 | Third plugin. |'
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_failure 1
}

@test "readme-sync: fails when the map lacks an entry" {
  printf '{"alpha": {"plugin": "alpha", "track": "tag"}}\n' > "${ROOT}/.ci/upstream-plugins.json"
  write_readme "${ROW_ALPHA}" "${ROW_BETA}"
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_failure 1
  [[ "${stderr}" == *'FAIL: beta:'*'upstream-plugins.json'* ]]
  [[ "${stderr}" != *'ERROR:'* ]]
}

@test "readme-sync: fails when the map is missing" {
  rm "${ROOT}/.ci/upstream-plugins.json"
  write_readme "${ROW_ALPHA}" "${ROW_BETA}"
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_failure 1
  [[ "${stderr}" == *'FAIL:'*'upstream-plugins.json'* ]]
  [[ "${stderr}" != *'ERROR:'* ]]
}
