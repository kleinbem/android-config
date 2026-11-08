#!/usr/bin/env python3
"""Write an ssh known_hosts file from the ssh_known_hosts section of
nix-config's INFRASTRUCTURE.yaml (the fleet's pinned port-22 host keys).

Usage: gen-known-hosts.py <INFRASTRUCTURE.yaml> <output>
"""

import re
import sys

import yaml

KEY_RE = re.compile(r"^ssh-ed25519 [A-Za-z0-9+/]+={0,2}$")
# A name with a comma or space would split into extra known_hosts patterns.
NAME_RE = re.compile(r"^[A-Za-z0-9.:\[\]-]+$")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    src, out = sys.argv[1], sys.argv[2]
    with open(src, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    hosts = data.get("ssh_known_hosts") if isinstance(data, dict) else None
    if not isinstance(hosts, dict) or not hosts:
        sys.exit(
            f"error: {src} has no ssh_known_hosts section; "
            "pull nix-config and run `just dev::sync-agent` there"
        )

    lines = []
    for name, entry in sorted(hosts.items()):
        entry = entry if isinstance(entry, dict) else {}
        names = entry.get("host_names")
        key = entry.get("public_key")
        if (
            not isinstance(names, list)
            or not names
            or not isinstance(key, str)
            or not KEY_RE.match(key)
        ):
            sys.exit(
                f"error: ssh_known_hosts.{name} has no host names or a malformed key"
            )
        bad = [n for n in names if not isinstance(n, str) or not NAME_RE.match(n)]
        if bad:
            sys.exit(f"error: ssh_known_hosts.{name}: unexpected host name(s) {bad}")
        lines.append(f"{','.join(names)} {key}\n")

    with open(out, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print(f"Wrote {len(lines)} pinned host keys to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
