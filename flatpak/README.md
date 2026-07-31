# Unwall — Flatpak (GUI only)

This Flatpak packages **only the GTK4 interface**. Unwall's actual work —
nftables rules, the systemd service, binding to NFQUEUE — cannot happen
inside a Flatpak sandbox, so `unwallctl` and its systemd unit must be
installed natively on the host first:

```bash
sudo ./install.sh          # from the repository root
```

or one of the native packages under [`../packaging`](../packaging).

Once that is done, the Flatpak GUI reaches the host's `unwallctl` (and, when
a privileged action is needed, `pkexec`) through `flatpak-spawn --host`. This
requires `--talk-name=org.freedesktop.Flatpak`, a fairly broad permission —
that is also why this manifest is not intended for Flathub and is meant to be
built and distributed as a standalone `.flatpak` bundle or from your own
Flatpak repo instead.

## Build

```bash
flatpak install flathub org.gnome.Platform//49 org.gnome.Sdk//49
flatpak-builder --force-clean --user --install build-dir \
    io.github.WinTone01.Unwall.yml
```

For local development, edit the `sources:` entry in
`io.github.WinTone01.Unwall.yml` to use `type: dir` / `path: ..` instead of
the `git` source, so it builds from your working tree instead of a tagged
release.

## Run

```bash
flatpak run io.github.WinTone01.Unwall
```

## Bundle for distribution

```bash
flatpak build-bundle ~/.local/share/flatpak/repo unwall.flatpak \
    io.github.WinTone01.Unwall
```

`unwall.flatpak` can then be installed on another machine with
`flatpak install unwall.flatpak` (after step 1, the native backend, is done
there too).
