#!/usr/bin/env python3
"""Add a published GitHub release (JSON from gh release view) to both READMEs."""

import argparse
from datetime import datetime
from html import escape
import json
from pathlib import Path
import re
import sys
from zoneinfo import ZoneInfo


VERSION = r'[0-9]+\.[0-9]+\.[0-9]+'
RELEASE_ROW = re.compile(rf'^  <tr>\n    <td nowrap>v({VERSION})</td>\n', re.MULTILINE)


def first_summary_line(text):
    lines = (re.sub(r'^[-*+](?:\s+|$)', '', line.strip()) for line in text.splitlines())
    return next((line for line in lines if line), '')


def render_row(version, date, url, summary):
    return (
        '  <tr>\n'
        f'    <td nowrap>v{version}</td>\n'
        f'    <td nowrap>{date}</td>\n'
        f'    <td>{escape(summary)}</td>\n'
        f'    <td><a href="{escape(url)}">Release</a></td>\n'
        '  </tr>\n'
    )


def insert_row(text, heading, version, row):
    opening = f'{heading}\n\n<table>\n'
    start = text.index(opening) + len(opening)
    end = text.index('</table>', start)
    rows = list(RELEASE_ROW.finditer(text, start, end))
    if any(match[1] == version for match in rows):
        return text

    version_parts = tuple(map(int, version.split('.')))
    for match in rows:
        if tuple(map(int, match[1].split('.'))) < version_parts:
            end = match.start()
            break
    return text[:end] + row + text[end:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version')
    parser.add_argument('--chinese-summary', default='')
    parser.add_argument('--english-summary', default='')
    args = parser.parse_args()
    release = json.load(sys.stdin)
    if (not re.fullmatch(VERSION, args.version) or release['tagName'] != f'v{args.version}'
            or release['isDraft'] or release['isPrerelease'] or not release['publishedAt']):
        parser.error(f'Expected a published stable release for v{args.version}.')

    published = datetime.fromisoformat(release['publishedAt'].replace('Z', '+00:00'))
    date = published.astimezone(ZoneInfo('Asia/Shanghai')).date()
    root = Path(__file__).resolve().parents[1]
    readmes = (
        ('README.md', '## Release history', args.english_summary, 'Fixed some bugs.'),
        ('README.zh-CN.md', '## 更新记录', args.chinese_summary, '修复了一些 Bug。'),
    )
    updates = {}
    for name, heading, summary_input, default_summary in readmes:
        path = root / name
        original = path.read_text(encoding='utf-8')
        summary = first_summary_line(summary_input) or default_summary
        row = render_row(args.version, date, release['url'], summary)
        updated = insert_row(original, heading, args.version, row)
        if updated != original:
            updates[path] = updated

    for path, text in updates.items():
        path.write_text(text, encoding='utf-8')


if __name__ == '__main__':
    main()
