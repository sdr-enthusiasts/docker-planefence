# Wiki Automation

This page documents how wiki syncing is automated.

## Files

- Workflow: `.github/workflows/wiki-sync.yml`
- Stage script: `scripts/wiki/stage_wiki.sh`
- Publish script: `scripts/wiki/publish_wiki.sh`

## Authentication Notes

The workflow uses `secrets.GITHUB_TOKEN` and requires `permissions: contents: write`.

If your organization policy blocks wiki pushes from `github-actions[bot]`, use a Personal Access Token and run `scripts/wiki/publish_wiki.sh` manually from a trusted environment.

## How It Works

1. The workflow triggers on `workflow_dispatch` and selected `push` events.
2. `stage_wiki.sh` copies top-level pages from `docs/wiki` into `.wiki-dist`.
3. `publish_wiki.sh` clones `${GITHUB_REPOSITORY}.wiki.git`, replaces markdown pages, and pushes only when there are changes.

## Why This Design

- Keeps wiki content in version control with normal PR review.
- Uses simple shell scripts for maintainability.
- Avoids unnecessary wiki commits when content is unchanged.

## Local Dry-Run

```bash
scripts/wiki/stage_wiki.sh docs/wiki .wiki-dist
ls -la .wiki-dist
```

To publish locally (requires token and network access):

```bash
export GITHUB_TOKEN="<token>"
export GITHUB_REPOSITORY="sdr-enthusiasts/docker-planefence"
scripts/wiki/publish_wiki.sh .wiki-dist .wiki-repo
```
