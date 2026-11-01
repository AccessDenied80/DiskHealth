# Third-party software

DiskHealth's own source code is licensed under the MIT License (see `LICENSE`).

## smartmontools — smartctl

The DiskHealth application bundle includes an unmodified `smartctl` executable
(`DiskHealth.app/Contents/Resources/smartctl`) built from **smartmontools 7.5**.
It runs as a separate program; DiskHealth only executes it and reads its JSON output.

- Copyright (C) 2002–2025 Bruce Allen, Christian Franke and the smartmontools developers
- License: GNU General Public License, version 2 or later
  (full text: `smartmontools-COPYING` in the application bundle, or
  <https://www.gnu.org/licenses/old-licenses/gpl-2.0.html>)
- Project: <https://www.smartmontools.org/>
- Corresponding source code: <https://github.com/smartmontools/smartmontools/releases/download/RELEASE_7_5/smartmontools-7.5.tar.gz>
  (SHA-256 `690b83ca331378da9ea0d9d61008c4b22dde391387b9bbad7f29387f2595f76e`).
  The exact build steps are in `scripts/build-smartctl.sh` of the DiskHealth repository.
