# rvenutolo-pins Claude Code marketplace

> [!WARNING]
> This marketplace is for my own use only. It is unsupported, its pins move
> on my schedule, and entries come and go without notice. Do not depend on
> it. If you want one of these plugins, install it from its upstream project.

A [Claude Code](https://claude.com/claude-code) plugin marketplace that
re-lists third-party plugins I use, each pinned to an upstream commit. The
catalogue in [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json)
points at each plugin's own repository; no plugin code lives here.

## Why

An upstream marketplace that lists its plugin as `"source": "./"` hands every
push to its default branch straight to the next update. Pinning puts three
gates in front of each change instead: Renovate proposes the new commit as a
pull request, CI verifies it, and nothing is proposed until the release is at
least 7 days old.

That age is measured from timestamps the upstream controls: a tag's commit or
tagger date, or a branch head's committer date. The gate delays ordinary
releases; it does not prove a commit has been public for 7 days.

## Plugins

Entry names are `<upstream owner>--<plugin>`. The upstream names are not
reused, because Claude Code reserves names containing `claude` for
Anthropic's own plugins.

<!-- plugins:start -->
<!-- The table is single-space cells under the prettier-ignore marker below, so a version of a different length does not make the formatter rewrite it. -->
<!-- prettier-ignore -->
| Plugin | Version | Description |
| --- | --- | --- |
| [forrestchang--andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) | 2c606141936f1eeef17fa3043a72095b4765b9c2 | Behavioral guidelines to reduce common LLM coding mistakes, derived from Andrej Karpathy's observations on LLM coding pitfalls. |
| [jarrodwatts--hud](https://github.com/jarrodwatts/claude-hud) | v0.11.3 | Real-time statusline showing context usage, active tools, running agents, and todo progress. |

<!-- plugins:end -->

A plugin with a release tag in the Version column follows that upstream's
release tags. A plugin with a commit sha there follows the upstream's `main`
branch, because that upstream publishes no releases.

## Install

```text
/plugin marketplace add rvenutolo/claude-plugins-pins
/plugin install <plugin>@rvenutolo-pins
/reload-plugins
```

Replace `<plugin>` with a name from the table above. The last line activates
the newly installed plugin in the running session.

The same steps from the CLI:

```console
claude plugin marketplace add rvenutolo/claude-plugins-pins
claude plugin install <plugin>@rvenutolo-pins
```

Plugins are fetched over SSH from GitHub. Without a GitHub SSH key, set
`CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1` first. Only `claude plugin install` from
the shell falls back to HTTPS on its own; installs and updates through
`/plugin` do not.

## Updates

Renovate bumps each pin. Pick up new pins with
`/plugin marketplace update rvenutolo-pins`, then update the plugin.

Claude Code updates an installed plugin only when its version changes, and
the version comes from the plugin's own `plugin.json`. A branch-pinned plugin
whose upstream never changes that version is not updated by
`claude plugin update` when its pin moves. Reinstall it instead:

```console
claude plugin uninstall <plugin>@rvenutolo-pins
claude plugin install <plugin>@rvenutolo-pins
```

## Uninstall

```text
/plugin uninstall <plugin>@rvenutolo-pins
/plugin marketplace remove rvenutolo-pins
```

From the CLI:

```console
claude plugin uninstall <plugin>@rvenutolo-pins
claude plugin marketplace remove rvenutolo-pins
```

## Development

`./run-all-checks` runs the whole gate: formatting, the governance checks, the
lints and the test suite. The governance checks include `.ci/check-pins`, which
verifies every pin against its upstream repository and so needs network
access, and `.ci/check-readme-sync`, which holds the plugin table to the
manifest. Both read [`.ci/upstream-plugins.json`](.ci/upstream-plugins.json),
which gives each entry its upstream plugin name and whether it tracks a tag or
a branch. The shortcut for the whole gate is `just check`.
