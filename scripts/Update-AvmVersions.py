#!/usr/bin/env python3
"""
Check AVM module versions referenced in Bicep files against MCR and update in-place.

Usage:
    python3 scripts/Update-AvmVersions.py [--dry-run]

Exit codes:
    0 — all modules already at latest version
    1 — one or more modules were updated (or would be updated with --dry-run)
    2 — error fetching versions from MCR
"""
import json
import re
import sys
import urllib.request
import urllib.error
from pathlib import Path

DRY_RUN = '--dry-run' in sys.argv
BICEP_FILES = sorted(Path('bicep').rglob('*.bicep'))


def get_latest_version(module_path: str) -> str | None:
    """Return the latest semver tag for an AVM module from MCR, or None on failure."""
    url = f'https://mcr.microsoft.com/v2/bicep/modules/{module_path}/tags/list'
    try:
        with urllib.request.urlopen(url, timeout=15) as resp:
            data = json.loads(resp.read())
        tags = [t for t in data.get('tags', []) if re.fullmatch(r'\d+\.\d+\.\d+', t)]
        if not tags:
            return None
        return sorted(tags, key=lambda v: tuple(int(x) for x in v.split('.')))[-1]
    except urllib.error.URLError as exc:
        print(f'  ERROR fetching {module_path}: {exc}', file=sys.stderr)
        return None


def main() -> int:
    if not BICEP_FILES:
        print('No .bicep files found under bicep/')
        return 0

    # Collect all module refs across all bicep files
    # Pattern: br/public:avm/res/<path>:<version>
    ref_pattern = re.compile(r"br/public:(avm/res/[^':>\s]+):(\d+\.\d+\.\d+)")

    all_refs: dict[str, set[str]] = {}  # module_path -> set of current versions seen
    for f in BICEP_FILES:
        for _, module_path, version in ref_pattern.findall(f.read_text()):
            all_refs.setdefault(module_path, set()).add(version)

    if not all_refs:
        print('No AVM module references found in bicep/ files.')
        return 0

    print(f'Checking {len(all_refs)} AVM module(s) against MCR...\n')

    fetch_error = False
    updates: list[tuple[str, str, str]] = []  # (module_path, current, latest)

    for module_path, current_versions in sorted(all_refs.items()):
        current = sorted(current_versions, key=lambda v: tuple(int(x) for x in v.split('.')))[-1]
        latest = get_latest_version(module_path)
        if latest is None:
            fetch_error = True
            print(f'  ??  {module_path}  (could not fetch latest)')
        elif latest != current:
            updates.append((module_path, current, latest))
            print(f'  UP  {module_path}  {current} -> {latest}')
        else:
            print(f'  OK  {module_path}  {current}')

    print()

    if updates:
        summary_lines = [f'- `{m}`: {c} → {l}' for m, c, l in updates]
        print(f'{"Would update" if DRY_RUN else "Updating"} {len(updates)} module(s):\n' +
              '\n'.join(summary_lines))

        if not DRY_RUN:
            for f in BICEP_FILES:
                content = f.read_text()
                for module_path, current, latest in updates:
                    content = content.replace(
                        f'br/public:{module_path}:{current}',
                        f'br/public:{module_path}:{latest}',
                    )
                f.write_text(content)
            print('\nFiles updated.')

        # Write summary file for GitHub Actions step summary / PR body
        Path('avm-update-summary.md').write_text(
            '## AVM module version updates\n\n' + '\n'.join(summary_lines) + '\n'
        )
        return 1

    print('All AVM modules are up to date.')
    return 2 if fetch_error else 0


if __name__ == '__main__':
    sys.exit(main())
