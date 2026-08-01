# Contributing to Unwall

Thanks for considering it. This project is small and mostly one person's
spare time, so anything that lowers the back-and-forth on a PR or issue is
genuinely useful.

## Before you file a bug

- Check the [README's Troubleshooting section](README.md#troubleshooting)
  first — several recurring reports are already covered there.
- Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.yml)
  (it's the default when you click "New issue"). The environment table it
  asks for (Unwall version, install method, distro, engine, strategy,
  hostlist mode) is almost always the first thing needed to make sense of a
  report — filling it in up front saves a round trip.
- `unwallctl version`, `unwallctl doctor`, `journalctl -u unwall -n 50` and,
  for hostlist-auto issues, `/var/log/unwall/hostlist-auto.log` are the
  most useful things to attach.

## Project layout

See the [README's Project layout section](README.md#project-layout) for
what each file/directory is. In short: `bin/unwallctl` is the privileged
CLI backend (bash), `gui/unwall_gui.py` is the GTK4/libadwaita frontend
(Python), and `packaging/` + `flatpak/` hold the four package formats.

## Making a change

- **Shell (`bin/unwallctl`, `install.sh`, `uninstall.sh`,
  `packaging/*.sh`)**: keep `set -euo pipefail` semantics intact — a lot of
  past bugs in this project came from exactly that being violated somewhere
  (a `trap ... RETURN` referencing an already-torn-down local variable, a
  `cmd | tee` pipeline silently killing the script under `pipefail`). Run
  `shellcheck -S warning <file>` and `bash -n <file>` before opening a PR;
  CI runs both, plus a check that `VERSION` in `bin/unwallctl`,
  `gui/unwall_gui.py`, `packaging/PKGBUILD` and `packaging/unwall.spec` all
  agree.
- **Python (`gui/unwall_gui.py`)**: no test suite exists for the GUI (GTK
  needs a real display); at minimum run `python3 -m py_compile
  gui/unwall_gui.py` (CI does this too) and, if you can, actually launch
  `unwall` and click through the change — `UW_NO_UNIQUE=1 unwall` starts an
  isolated instance that won't fight with one you already have running.
  If you add a user-facing string, add its Turkish translation to the `TR`
  dict too (missing entries silently fall back to English even in Turkish
  mode — easy to miss since nothing errors).
- **Changing the GUI's layout**: refresh `docs/screenshots/gui-en.png` and
  `gui-tr.png` (both READMEs embed them) — a real window screenshot, not a
  mockup. `UW_NO_UNIQUE=1 UW_LANG=en unwall` / `UW_LANG=tr unwall` launch an
  isolated instance; redact any real LAN/IP addresses visible in the
  "Gateway mode" section before committing the image.
- **Anything touching `nftables` rules or `--hostlist-auto*` flags**: these
  are easy to get subtly wrong in ways that only show up against real ISP
  DPI, which most contributors (including the maintainer, most of the
  time) don't have direct access to test against. Prefer citing the
  relevant section of zapret2's own
  [`docs/manual.en.md`](https://github.com/bol-van/zapret2/blob/master/docs/manual.en.md)
  over guessing, and say plainly in the PR description what you were and
  weren't able to verify.
- **Packaging (`packaging/`, `flatpak/`)**: if you change anything here,
  actually build the affected format locally
  (`packaging/build-deb.sh`, `packaging/build-rpm.sh`,
  `packaging/build-appimage.sh`, or `flatpak-builder` per
  `flatpak/README.md`) rather than only editing the spec/manifest.

## Commit messages

Plain English, explain the *why* over the *what* where it's not obvious
from the diff. No strict format enforced.

## License

By contributing, you agree your contribution is licensed under this
project's [GPLv3 license](LICENSE).
