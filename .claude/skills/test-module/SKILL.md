---
name: test-module
description: Test a .knrc module (or several) end-to-end in a disposable Docker container for a target distro, checking idempotency with a second run in the same container. Use whenever a module in modules/ or scripts/lib/ was added or changed, before considering it done.
---

# Testing a .knrc module

This project's modules are only "done" once they've been proven to work
in a real container of the target distro — see "Как работать над этим
проектом" in [CLAUDE.md](../../../CLAUDE.md). This skill makes that a
repeatable command instead of an ad hoc container each time.

## Steps

1. Confirm Docker is available: `docker info` (if not, tell the user
   testing must happen manually / stop here — do not skip the test).
2. Pick the distro(s) to test against based on what the module touches:
   - Package-manager logic that branches on `OS_FAMILY` (apt vs
     dnf/yum) → test at least one `debian` family (`ubuntu24` or
     `debian12`) and one `rhel` family (`fedora` or `centos9`) distro.
   - Anything CentOS-specific (EPEL, CRB, `yum` fallback) → include
     `centos9`, and `centos7` if the change touches the yum branch.
   - A single self-contained module with no OS-branching → `ubuntu24`
     is enough for a first pass.
3. Run the test script for each module/distro combination:
   ```bash
   scripts/test-module.sh <module-name> <distro>
   ```
   `<module-name>` matches the value used in `DOTFILES_MODULES` (the
   filename in `modules/` without `.sh`, e.g. `nvim`, `cli-tools`).
   Comma-separate multiple modules that depend on each other, e.g.
   `base,cli-tools` — the script itself converts commas to the spaces
   `DOTFILES_MODULES` actually expects, so pass commas here even if
   reproducing manually in step 5 (where you must use spaces yourself).

   **Almost every module other than `base` assumes `curl`/`git`/etc. are
   already on the image** — those come from `base`, not from the module
   under test. A bare distro image (`ubuntu:24.04`, `fedora:latest`, …)
   has none of them. Testing a non-`base` module alone typically fails
   with `command not found: curl` or similar — that failure is an
   artifact of the isolated test, not a real bug in the module. Test
   `base,<module-name>` together unless you've confirmed the module has
   zero external-command dependencies.
4. The script runs `install.sh` twice inside the *same* container and
   fails loudly (non-zero exit, `set -e`) on any error from either run.
   A clean second run is the idempotency check — do not consider the
   module done if only the first run was tested.
5. If a run fails, reproduce interactively to debug rather than staring
   at the log:
   ```bash
   docker run --rm -it -v "$PWD:/repo:ro" ubuntu:24.04 bash
   cp -r /repo /tmp/knrc && cd /tmp/knrc
   DOTFILES_MODULES="base <module-name>" NONINTERACTIVE=1 ./install.sh
   ```
6. Once the module passes, add a short **Тестирование** note to its
   file in `docs/modules/<module>.md` naming the distro(s) covered —
   that file is the persistent record scripts/test-module.sh output
   (which disappears when the container exits) turns into.

## Distro → image reference

| distro flag | image |
|---|---|
| `ubuntu24` | `ubuntu:24.04` |
| `debian12` | `debian:12` |
| `fedora` | `fedora:latest` |
| `centos9` | `quay.io/centos/centos:stream9` |
| `centos7` | `centos:7` |
