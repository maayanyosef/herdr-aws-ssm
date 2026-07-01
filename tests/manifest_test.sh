#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/lib/assert.sh"

test_manifest_parses_and_has_fields() {
  python3 - "$ROOT/herdr-plugin.toml" <<'PY' || exit 1
import sys, tomllib
m = tomllib.load(open(sys.argv[1], "rb"))
for f in ("id", "name", "version", "min_herdr_version"):
    assert f in m, f"missing {f}"
assert m["id"] == "herdr-aws-ssm", f"id={m['id']!r}"
acts = {a["id"] for a in m.get("actions", [])}
assert {"connect", "setup", "doctor"} <= acts, f"actions={acts}"
for a in m["actions"]:
    assert a.get("contexts") == ["workspace"], f"bad contexts on {a['id']}"
    assert isinstance(a.get("command"), list) and a["command"], f"bad command on {a['id']}"
# We deliberately do NOT force a keybinding in the manifest (avoid collisions).
assert "command" not in m.get("keys", {}), "manifest must not force a keybinding"
print("ok")
PY
}

test_action_commands_point_to_existing_scripts() {
  for s in connect setup doctor; do
    [ -f "$ROOT/bin/$s.sh" ] || return 1
  done
}

run_tests
