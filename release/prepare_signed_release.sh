#!/usr/bin/env bash
set -euo pipefail
DIST="${1:?release artifact directory required}"
BUILD_RUN_ID="${2:?completed build run ID required}"
[[ "$BUILD_RUN_ID" =~ ^[0-9]+$ ]] || { echo 'Invalid build run ID' >&2; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
(cd "$DIST" && sha256sum -c SHA256SUMS)
gh api "repos/$GH_REPO/actions/runs/$BUILD_RUN_ID" > "$RUNNER_TEMP/anmir-build-run.json"
python3 - "$RUNNER_TEMP/anmir-build-run.json" <<'PY'
import json,sys
run=json.load(open(sys.argv[1]))
assert run['status']=='completed' and run['conclusion']=='success', 'Source build must have succeeded'
assert run['head_branch']=='main' and run['event'] in ('push','workflow_dispatch'), 'Only main builds may publish'
assert run['path']=='.github/workflows/anmir-release.yml', 'Unexpected source workflow'
PY
version="$(jq -er '.version | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' "$DIST/update.json")"
tag="v$version"
[[ "$(gh release view "$tag" --json isDraft --jq .isDraft)" == true ]] || {
    echo 'Create a draft with the locally signed APK first; published releases are immutable.' >&2
    exit 1
}
source_sha="$(jq -r .head_sha "$RUNNER_TEMP/anmir-build-run.json")"
tag_sha="$(gh api "repos/$GH_REPO/git/ref/tags/$tag" --jq '.object.sha')"
[[ "$tag_sha" == "$source_sha" ]] || { echo 'Release tag does not match the tested build.' >&2; exit 1; }
gh release download "$tag" --pattern "AnmirConnect-$version.apk" --dir "$DIST" --clobber
python3 "$ROOT/release/verify_companion.py" "$DIST/AnmirConnect-$version-unsigned.apk" "$DIST/AnmirConnect-$version.apk"
rm "$DIST/AnmirConnect-$version-unsigned.apk"
(cd "$DIST" && sha256sum Anmir-*.dmg Anmir-*.zip Anmir-*-source.tar.gz AnmirConnect-*.apk update.json > SHA256SUMS)
echo "source_sha=$source_sha" >> "$GITHUB_OUTPUT"
