#!/usr/bin/env python3
"""Keep a server's Home rollback material bounded.

Each upgrade leaves /root/openstrudel-upgrade-<release>-<UTC stamp> with a full
state snapshot, plus image tags and a staging folder. Keep the two newest
snapshots from healthy deployments (they contain healthy.json) and anything
newer, which may belong to a deployment in progress. Older snapshots are
superseded by two later healthy deployments and are removed, together with
image tags and staging folders that nothing kept still needs. User data in
the Docker volume is never touched. Run as root on the server; --dry-run
prints the plan without changing anything.
"""
import argparse, datetime, json, pathlib, re, shutil, subprocess

STAMP = re.compile(r'(\d{8}T\d{6}Z)$')

def stamp(path):
    match = STAMP.search(path.name)
    return match.group(1) if match else ''

def plan(snapshots, keep=2):
    """Return (kept, removed) snapshot paths. Ordered by their UTC stamp."""
    ordered = sorted((s for s in snapshots if stamp(s)), key=stamp)
    healthy = [s for s in ordered if (s / 'healthy.json').is_file()]
    if len(healthy) < keep:
        return ordered, []
    oldest_kept = stamp(healthy[-keep])
    removed = [s for s in ordered if stamp(s) < oldest_kept]
    return [s for s in ordered if s not in removed], removed

def cutoff(kept):
    """Anything created after the oldest kept snapshot may belong to a deployment in progress."""
    return datetime.datetime.strptime(min(stamp(s) for s in kept), '%Y%m%dT%H%M%SZ').replace(tzinfo=datetime.timezone.utc).timestamp()

def stale_stages(stages, kept, running_tag):
    """Staging folders older than the oldest kept snapshot, except the running release's."""
    if not kept: return []
    return [p for p in stages if not p.name.endswith(running_tag) and p.stat().st_mtime < cutoff(kept)]

def stale_images(created, needed, kept):
    """Image tags older than the oldest kept snapshot that nothing kept can roll back to.
    A before-* tag marks the image an upgrade replaced; it stays while its snapshot exists."""
    if not kept: return []
    stamps = {stamp(s) for s in kept}
    return [t for t, at in created.items() if t not in needed and at < cutoff(kept)
            and not (t.split(':', 1)[1].startswith('before') and stamp(pathlib.Path(t)) in stamps)]

def docker(*args):
    return subprocess.run(['docker', *args], check=True, capture_output=True, text=True).stdout

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=pathlib.Path, default=pathlib.Path('/root'))
    parser.add_argument('--stages', type=pathlib.Path, default=pathlib.Path('/opt'))
    parser.add_argument('--container', default='openstrudel-home-1')
    parser.add_argument('--keep', type=int, default=2)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    if args.keep < 2: parser.error('Keep at least two healthy snapshots')
    snapshots = [p for p in args.root.glob('openstrudel-upgrade-*') if p.is_dir() and not p.is_symlink()]
    kept, removed = plan(snapshots, args.keep)
    # Images a kept snapshot can roll back to, and the one running now.
    current = json.loads(docker('inspect', args.container))[0]['Config']['Image']
    needed = {current}
    for snapshot in kept:
        try: needed.add(json.loads((snapshot / 'container.json').read_text())['Config']['Image'])
        except (OSError, ValueError, KeyError): pass
    tags = [t for t in docker('images', '--format', '{{.Repository}}:{{.Tag}}', 'openstrudel').split() if t.startswith('openstrudel:')]
    created = {t: datetime.datetime.fromisoformat(docker('image', 'inspect', '--format', '{{.Created}}', t).strip()[:19] + '+00:00').timestamp() for t in tags}
    stale_tags = stale_images(created, needed, kept)
    stages = [p for p in args.stages.glob('openstrudel-stage-*') if p.is_dir() and not p.is_symlink()]
    old_stages = stale_stages(stages, kept, current.split(':', 1)[1]) if removed else []
    result = {'keep': [str(p) for p in kept], 'remove': [str(p) for p in removed], 'removeTags': stale_tags,
              'removeStages': [str(p) for p in old_stages], 'dryRun': args.dry_run}
    if not args.dry_run:
        for path in removed + old_stages: shutil.rmtree(path)
        for tag in stale_tags:
            # A tag still used by any container is left alone.
            subprocess.run(['docker', 'rmi', tag], capture_output=True, text=True)
        subprocess.run(['docker', 'builder', 'prune', '-f'], capture_output=True, text=True)
    print(json.dumps(result))

if __name__ == '__main__':
    main()
