#!/usr/bin/env python3
"""Refresh the generated contributor blocks in the project READMEs."""

import argparse
import json
import os
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


START_MARKER = '<!-- anmir-contributors:start -->'
END_MARKER = '<!-- anmir-contributors:end -->'
README_NAMES = ('README.md', 'README.zh-CN.md')
PER_PAGE = 100
PER_ROW = 8


class GitHubAPI:
    def __init__(self, base_url, token=None):
        self.base_url = base_url.rstrip('/')
        self.token = token

    def get(self, path, **parameters):
        url = self.base_url + path
        if parameters:
            url += '?' + urlencode(parameters)
        headers = {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'Anmir-contributors-updater',
            'X-GitHub-Api-Version': '2022-11-28',
        }
        if self.token:
            headers['Authorization'] = 'Bearer ' + self.token
        try:
            with urlopen(Request(url, headers=headers), timeout=30) as response:
                return json.load(response)
        except HTTPError as error:
            detail = error.read().decode('utf-8', 'replace')
            raise RuntimeError(f'GitHub API returned HTTP {error.code} for {url}: {detail}') from error
        except (URLError, TimeoutError) as error:
            raise RuntimeError(f'Could not contact GitHub API at {url}: {error}') from error
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise RuntimeError(f'GitHub API returned invalid JSON for {url}') from error


def repository_parts(value):
    parts = value.split('/')
    if len(parts) != 2 or not all(parts):
        raise ValueError('Repository must use the OWNER/NAME format.')
    return parts


def repo_path(repository):
    owner, name = repository_parts(repository)
    return '/repos/' + quote(owner, safe='') + '/' + quote(name, safe='')


def upstream_repository(metadata):
    upstream = metadata.get('source') or metadata.get('parent')
    if not isinstance(upstream, dict) or not upstream.get('full_name'):
        raise RuntimeError('The repository has no source or parent fork to compare against.')
    return upstream['full_name']


def commit_pages(api, repository, ref=None):
    metadata = api.get(repo_path(repository))
    target_ref = ref or metadata.get('default_branch')
    if not target_ref:
        raise RuntimeError(f'{repository} has no default branch.')

    upstream = upstream_repository(metadata)
    upstream_metadata = api.get(repo_path(upstream))
    upstream_ref = upstream_metadata.get('default_branch')
    if not upstream_ref:
        raise RuntimeError(f'{upstream} has no default branch.')

    upstream_owner, _ = repository_parts(upstream)
    target_owner, _ = repository_parts(repository)
    comparison = quote(
        f'{upstream_owner}:{upstream_ref}...{target_owner}:{target_ref}',
        safe=':.',
    )
    path = repo_path(repository) + '/compare/' + comparison

    page = 1
    received = 0
    total = None
    while True:
        payload = api.get(path, per_page=PER_PAGE, page=page)
        commits = payload.get('commits')
        if not isinstance(commits, list):
            raise RuntimeError('GitHub compare response has no commit list.')
        if total is None:
            total = payload.get('total_commits')
            if not isinstance(total, int) or total < 0:
                raise RuntimeError('GitHub compare response has no valid total_commits value.')
        received += len(commits)
        yield commits
        if received >= total:
            break
        if not commits:
            raise RuntimeError(f'GitHub compare response ended after {received} of {total} commits.')
        page += 1


def contributor_logins(api, repository, ref=None):
    contributors = []
    seen = set()
    for commits in commit_pages(api, repository, ref):
        for commit in commits:
            author = commit.get('author')
            if not isinstance(author, dict):
                continue
            login = author.get('login')
            account_type = author.get('type')
            if not isinstance(login, str) or not login:
                continue
            if account_type == 'Bot' or login.casefold().endswith('[bot]'):
                continue
            key = login.casefold()
            if key not in seen:
                seen.add(key)
                contributors.append(login)
    if not contributors:
        raise RuntimeError('No linked GitHub contributors were found in Anmir commits.')
    return contributors


def contributor_link(login):
    profile = 'https://github.com/' + login
    image = profile + '.png?size=120'
    return (f'[<img src="{image}" width="60" height="60" alt="@{login}">]'
            f'({profile})')


def render_contributors(logins):
    if not logins:
        raise ValueError('At least one contributor is required.')
    lines = []
    for index, login in enumerate(logins):
        row_position = index % PER_ROW
        row_ends = row_position == PER_ROW - 1 or index == len(logins) - 1
        line = contributor_link(login)
        if not row_ends:
            line += '&nbsp;'
        lines.append(line)
        if row_position == PER_ROW - 1 and index != len(logins) - 1:
            lines.append('<br>')
    return '\n'.join(lines)


def replace_generated_block(text, rendered, name):
    if text.count(START_MARKER) != 1 or text.count(END_MARKER) != 1:
        raise ValueError(f'{name} must contain exactly one contributor marker pair.')
    start = text.index(START_MARKER)
    end = text.index(END_MARKER)
    if start >= end:
        raise ValueError(f'{name} contributor markers are out of order.')
    prefix_end = start + len(START_MARKER)
    return text[:prefix_end] + '\n' + rendered + '\n' + text[end:]


def prepare_updates(root, rendered):
    updates = {}
    for name in README_NAMES:
        path = root / name
        original = path.read_text(encoding='utf-8')
        updated = replace_generated_block(original, rendered, name)
        updates[path] = (original, updated)
    return updates


def apply_updates(updates, check=False):
    changed = {path: updated for path, (original, updated) in updates.items()
               if original != updated}
    if check or not changed:
        return bool(changed)

    temporary = []
    try:
        for path, updated in changed.items():
            candidate = path.with_name('.' + path.name + '.contributors.tmp')
            candidate.write_text(updated, encoding='utf-8')
            temporary.append((candidate, path))
        for candidate, path in temporary:
            candidate.replace(path)
    finally:
        for candidate, _ in temporary:
            candidate.unlink(missing_ok=True)
    return True


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', default=os.environ.get('GITHUB_REPOSITORY'))
    parser.add_argument('--ref', help='Target branch or ref; defaults to the repository default branch.')
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--check', action='store_true', help='Fail if the README blocks are out of date.')
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    if not args.repository:
        raise SystemExit('Set GITHUB_REPOSITORY or pass --repository OWNER/NAME.')
    try:
        repository_parts(args.repository)
        api = GitHubAPI(
            os.environ.get('GITHUB_API_URL', 'https://api.github.com'),
            os.environ.get('GITHUB_TOKEN'),
        )
        logins = contributor_logins(api, args.repository, args.ref)
        rendered = render_contributors(logins)
        updates = prepare_updates(args.root, rendered)
        changed = apply_updates(updates, check=args.check)
    except (OSError, RuntimeError, ValueError) as error:
        raise SystemExit(str(error)) from error
    if args.check and changed:
        print('Contributor blocks are out of date.', file=sys.stderr)
        return 1
    if changed:
        print('Updated contributors: ' + ', '.join(logins))
    else:
        print('Contributor blocks are already up to date.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
