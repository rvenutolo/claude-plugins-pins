# .ci/check-manifest-invariants, against the real manifest and against fixture
# manifests in BATS_TEST_TMPDIR that each break one invariant.
#
# setup writes a valid two-entry manifest to ${ROOT}; `mutate` rewrites it with
# a jq filter so each test states only the one thing it breaks.
#
# `run --separate-stderr` is a bats 1.5.0 flag: the check prints every verdict
# on stderr.
bats_require_minimum_version 1.5.0

function setup() {
  load 'test_helper/common'
  CHECK="${REPO_DIR}/.ci/check-manifest-invariants"
  ROOT="${BATS_TEST_TMPDIR}/root"
  MANIFEST="${ROOT}/.claude-plugin/marketplace.json"
  mkdir --parents "${ROOT}/.claude-plugin"
  cat > "${MANIFEST}" << 'JSON'
{
  "$schema": "https://json.schemastore.org/claude-code-marketplace.json",
  "name": "fixture",
  "owner": {"name": "Fixture Owner", "url": "https://example.invalid/owner"},
  "plugins": [
    {
      "name": "alpha",
      "source": {
        "source": "github",
        "repo": "acme/alpha",
        "ref": "v1.0.0",
        "sha": "0123456789abcdef0123456789abcdef01234567"
      },
      "description": "The first fixture plugin.",
      "homepage": "https://example.invalid/alpha",
      "author": {"name": "Fixture Author", "url": "https://example.invalid/author"}
    },
    {
      "name": "beta",
      "source": {
        "source": "github",
        "repo": "acme/beta",
        "ref": "v2.0.0",
        "sha": "89abcdef0123456789abcdef0123456789abcdef"
      },
      "description": "The second fixture plugin."
    }
  ]
}
JSON
}

# @description Rewrite the fixture manifest with a jq filter.
# @arg $1 filter the jq filter to apply
function mutate() {
  local -r filter="$1"
  local updated
  updated="$(jq "${filter}" "${MANIFEST}")"
  printf '%s\n' "${updated}" > "${MANIFEST}"
}

# @description Run the check on the fixture and assert it fails with one FAIL
#              line naming an invariant.
# @arg $1 needle text the stderr must contain
function assert_fails_with() {
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_failure 1
  [[ "${stderr}" == *'FAIL:'* ]]
  [[ "${stderr}" == *"$1"* ]]
  [[ "${stderr}" != *'ERROR:'* ]]
}

@test "manifest-invariants: the real manifest satisfies every invariant" {
  run --separate-stderr "${CHECK}" "${REPO_DIR}"
  assert_success
  [[ "${stderr}" == *'OK:'* ]]
}

@test "manifest-invariants: passes on the valid fixture" {
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_success
  [[ "${stderr}" == *'OK:'* ]]
}

@test "manifest-invariants: I1 fails when names are not sorted" {
  mutate '.plugins |= reverse'
  assert_fails_with 'I1'
}

@test "manifest-invariants: I2 fails on duplicate names" {
  mutate '.plugins[1].name = "alpha"'
  assert_fails_with 'I2'
}

@test "manifest-invariants: I3 fails on a description shorter than 10 characters" {
  mutate '.plugins[0].description = "too short"'
  assert_fails_with 'I3'
}

@test "manifest-invariants: I3 fails on a description longer than 2000 characters" {
  mutate '.plugins[0].description = ("x" * 2001)'
  assert_fails_with 'I3'
}

@test "manifest-invariants: I3 fails on leading whitespace in a description" {
  mutate '.plugins[0].description = " leading whitespace here"'
  assert_fails_with 'I3'
}

@test "manifest-invariants: I3 fails on trailing whitespace in a description" {
  mutate '.plugins[0].description = "trailing whitespace here\n"'
  assert_fails_with 'I3'
}

@test "manifest-invariants: I4 fails on an http owner url" {
  mutate '.owner.url = "http://example.invalid/owner"'
  assert_fails_with 'I4'
}

@test "manifest-invariants: I4 fails on an http homepage" {
  mutate '.plugins[0].homepage = "http://example.invalid/alpha"'
  assert_fails_with 'I4'
}

@test "manifest-invariants: I4 fails on an http author url" {
  mutate '.plugins[0].author.url = "http://example.invalid/author"'
  assert_fails_with 'I4'
}

@test "manifest-invariants: I5 fails when sha is missing" {
  mutate 'del(.plugins[0].source.sha)'
  assert_fails_with 'I5'
}

@test "manifest-invariants: I5 fails when sha is not 40 hex characters" {
  mutate '.plugins[0].source.sha = "0123abc"'
  assert_fails_with 'I5'
}

@test "manifest-invariants: I5 fails when sha has uppercase hex" {
  mutate '.plugins[0].source.sha = "0123456789ABCDEF0123456789ABCDEF01234567"'
  assert_fails_with 'I5'
}

@test "manifest-invariants: fails when ref is missing" {
  mutate 'del(.plugins[0].source.ref)'
  assert_fails_with 'ref'
}

@test "manifest-invariants: fails when ref is empty" {
  mutate '.plugins[0].source.ref = ""'
  assert_fails_with 'ref'
}

@test "manifest-invariants: fails when a source is a string" {
  mutate '.plugins[0].source = "./alpha"'
  assert_fails_with 'source'
}

@test "manifest-invariants: I9 fails when repo has no owner" {
  mutate '.plugins[0].source.repo = "alpha"'
  assert_fails_with 'I9'
}

@test "manifest-invariants: I9 fails when repo has a disallowed character" {
  mutate '.plugins[0].source.repo = "acme/alpha;PAYLOAD_RAN"'
  assert_fails_with 'I9'
}

@test "manifest-invariants: I9 fails when repo contains a path traversal" {
  mutate '.plugins[0].source.repo = "acme/.."'
  assert_fails_with 'I9'
}

@test "manifest-invariants: I10 fails on a zero-width space in a name" {
  mutate '.plugins[0].name = "alp\u200bha"'
  assert_fails_with 'I10'
}

@test "manifest-invariants: I10 fails on a bidi control in a description" {
  mutate '.plugins[0].description = "The first \u202efixture plugin."'
  assert_fails_with 'I10'
}

@test "manifest-invariants: I11 fails on an uppercase name" {
  mutate '.plugins[0].name = "Alpha"'
  assert_fails_with 'I11'
}

@test "manifest-invariants: fails on a wrong \$schema" {
  # shellcheck disable=SC2016 # `$schema` is a jq key, not a shell expansion
  mutate '."$schema" = "https://example.invalid/schema.json"'
  assert_fails_with 'schema'
}

@test "manifest-invariants: fails when \$schema is missing" {
  # shellcheck disable=SC2016 # `$schema` is a jq key, not a shell expansion
  mutate 'del(."$schema")'
  assert_fails_with 'schema'
}

@test "manifest-invariants: fails when owner.name is missing" {
  mutate 'del(.owner.name)'
  assert_fails_with 'owner.name'
}

@test "manifest-invariants: fails when the marketplace name is missing" {
  mutate 'del(.name)'
  assert_fails_with 'name'
}

@test "manifest-invariants: fails when plugins is empty" {
  mutate '.plugins = []'
  assert_fails_with 'plugins'
}

@test "manifest-invariants: fails when plugins is not an array" {
  mutate '.plugins = "none"'
  assert_fails_with 'plugins'
}

@test "manifest-invariants: reports every violation, not only the first" {
  mutate '.plugins[0].source.sha = "bad" | .owner.url = "http://example.invalid"'
  run --separate-stderr "${CHECK}" "${ROOT}"
  assert_failure 1
  [[ "${stderr}" == *'I4'* ]]
  [[ "${stderr}" == *'I5'* ]]
}

@test "manifest-invariants: fails on an unparsable manifest" {
  printf 'not json\n' > "${MANIFEST}"
  assert_fails_with 'marketplace.json'
}

@test "manifest-invariants: fails on a missing manifest" {
  rm "${MANIFEST}"
  assert_fails_with 'marketplace.json'
}

@test "manifest-invariants: exits 2 on a surplus argument" {
  run --separate-stderr "${CHECK}" "${ROOT}" extra
  assert_failure 2
  [[ "${stderr}" == *'usage:'* ]]
}
