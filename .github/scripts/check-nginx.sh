#!/usr/bin/env bash
# Checks for nginx updates to the version pinned in the Dockerfile, and flags repo inactivity.
# Run daily by .github/workflows/checkNginx.yml. Three outcomes, each idempotent:
#
#  1. A newer patch on the pinned major.minor line, published by *both* nginx and
#     fholzer/nginx-brotli, opens a PR to develop that bumps NGINX_VERSION and adds a CHANGELOG
#     line. Skipped if a branch for that version already exists.
#  2. A newer major.minor line published by both images opens an issue. Moving lines is a judgment
#     call, so it is never automated.
#  3. No commit on develop for INACTIVITY_WARN_DAYS opens an issue. GitHub disables scheduled
#     workflows in public repos after 60 days without activity, including this one.
#
# Env: GH_TOKEN (for gh - in CI, an XH Build Bot token so its PRs and issues show as that bot),
# DRY_RUN=1 to print actions instead of taking them. For testing,
# PINNED_OVERRIDE and INACTIVITY_WARN_DAYS override the pinned version and the idle threshold.
set -euo pipefail

INACTIVITY_WARN_DAYS=${INACTIVITY_WARN_DAYS:-45}
DRY_RUN=${DRY_RUN:-0}

log() { echo "$*" >&2; }
act() { # Run a command, or just print it in a dry run.
    if [ "$DRY_RUN" = "1" ]; then log "DRY_RUN: $*"; else "$@"; fi
}

# All X.Y.Z versions on a major.minor line in a Docker Hub repo, following pagination.
# Args: repo (e.g. library/nginx), tag prefix ("" or "v"), major.minor (e.g. 1.31).
line_versions() {
    local repo=$1 prefix=$2 minor=$3
    local url="https://hub.docker.com/v2/repositories/${repo}/tags?page_size=100&name=${prefix}${minor}."
    local re="^${prefix}${minor//./\\.}\\.[0-9]+$"
    while [ -n "$url" ] && [ "$url" != "null" ]; do
        local page
        page=$(curl -fsS --retry 3 "$url")
        jq -r --arg re "$re" '.results[].name | select(test($re))' <<<"$page"
        url=$(jq -r '.next' <<<"$page")
    done | sed -E "s/^${prefix}//" | sort -u
}

# Newest X.Y.Z on a line that both images publish. fholzer/nginx-brotli can lag the official
# image, and both variants must stay on the same nginx version.
newest_common() {
    comm -12 <(line_versions library/nginx "" "$1") <(line_versions fholzer/nginx-brotli v "$1") \
        | sort -V | tail -1
}

# Security entries from nginx's CHANGES for versions newer than $1, up to and including $2.
nginx_security_cves() {
    curl -fsS --retry 3 https://nginx.org/en/CHANGES \
        | awk -v to="$2" -v from="$1" '
            /^Changes with nginx / { v = $4; on = (v == to) ? 1 : (v == from ? 0 : on) }
            on' \
        | tr '\n' ' ' | grep -oE 'CVE-[0-9]+-[0-9]+' | sort -u || true
}

open_issue_once() { # Args: title, body. Skips if an open issue already has this title.
    if [ -n "$(gh issue list --state open --search "in:title \"$1\"" --json title \
            --jq ".[] | select(.title == \"$1\") | .title")" ]; then
        log "Issue already open: $1"
    else
        act gh issue create --title "$1" --body "$2"
    fi
}

#-----------------------------------------------------------------------------------------------
if [ -n "${PINNED_OVERRIDE:-}" ] && [ "$DRY_RUN" != "1" ]; then
    echo "::error::PINNED_OVERRIDE is for testing and requires a dry run"
    exit 1
fi
PINNED=${PINNED_OVERRIDE:-$(sed -nE 's/^ARG NGINX_VERSION=([0-9]+\.[0-9]+\.[0-9]+)$/\1/p' Dockerfile)}
if [ -z "$PINNED" ]; then
    echo "::error::Could not read NGINX_VERSION from Dockerfile"
    exit 1
fi
MINOR=${PINNED%.*}
MAJOR=${MINOR%.*}
log "Pinned nginx: $PINNED (line $MINOR)"

# 1. Newer patch on the pinned line.
LATEST=$(newest_common "$MINOR")
log "Newest $MINOR.x in both images: ${LATEST:-none}"
if [ -n "$LATEST" ] && [ "$LATEST" != "$PINNED" ] \
    && [ "$(printf '%s\n%s\n' "$PINNED" "$LATEST" | sort -V | tail -1)" = "$LATEST" ]; then
    BRANCH="nginx-$LATEST"
    if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null; then
        log "Branch $BRANCH already exists - PR already opened."
    else
        CVES=$(nginx_security_cves "$PINNED" "$LATEST")
        CVE_COUNT=$(grep -c . <<<"$CVES" || true)
        # Short note for the CHANGELOG, full CVE list for the PR body.
        if [ "$CVE_COUNT" -gt 0 ]; then
            NOTE="with $CVE_COUNT nginx security fixes"
            CVE_LIST="- ${CVES//$'\n'/$'\n'- }"
        else
            NOTE="with no security fixes listed in the nginx CHANGES"
            CVE_LIST=""
        fi
        log "Bumping $PINNED -> $LATEST, $NOTE"

        sed -i.bak -E "s/^ARG NGINX_VERSION=.*/ARG NGINX_VERSION=$LATEST/" Dockerfile && rm Dockerfile.bak
        # Add a bullet at the top of the `## next` section of the CHANGELOG.
        awk -v line="* Pinned nginx \`$LATEST\` (from \`$PINNED\`), $NOTE." '
            done != 1 && /^## next/ { print; getline; print; print line; done = 1; next }
            { print }' CHANGELOG.md >CHANGELOG.md.new && mv CHANGELOG.md.new CHANGELOG.md

        BODY="Bumps the pinned nginx version in the \`Dockerfile\` from \`$PINNED\` to \`$LATEST\`, $NOTE.
${CVE_LIST:+
$CVE_LIST
}
Both \`nginx:$LATEST\` and \`fholzer/nginx-brotli:v$LATEST\` are published. See the [nginx CHANGES](https://nginx.org/en/CHANGES) for details.

Merging rebuilds the \`next\` tags. To publish it, release from \`master\` as usual.

Opened by the Check nginx workflow."
        act git checkout -b "$BRANCH"
        # Commit as the XH Build Bot app's bot user. The email is GitHub's noreply form,
        # <user id>+<login>, which links the commit to that account (id from
        # `gh api 'users/xh-build-bot[bot]'`).
        act git -c user.name="xh-build-bot[bot]" \
            -c user.email="324593885+xh-build-bot[bot]@users.noreply.github.com" \
            commit -am "Bump nginx to $LATEST"
        act git push origin "$BRANCH"
        act gh pr create --base develop --head "$BRANCH" --title "Bump nginx to $LATEST" --body "$BODY"
        if [ "$DRY_RUN" = "1" ]; then
            git --no-pager diff
            git checkout -- Dockerfile CHANGELOG.md
            # Confirm the token can push, without creating anything.
            git push --dry-run origin "HEAD:refs/heads/$BRANCH"
        fi
    fi
fi

# 2. Newer major.minor line. Checks the next two minors (nginx alternates stable and mainline).
for next in "$MAJOR.$((${MINOR#*.} + 1))" "$MAJOR.$((${MINOR#*.} + 2))"; do
    NEW_LINE=$(newest_common "$next")
    if [ -n "$NEW_LINE" ]; then
        log "Newer line available: $next (newest $NEW_LINE)"
        open_issue_once "nginx $next is available" \
            "Both \`nginx\` and \`fholzer/nginx-brotli\` now publish nginx \`$NEW_LINE\`. We pin \`$PINNED\`. Moving to the \`$next\` line is a manual change: bump \`NGINX_VERSION\` in the \`Dockerfile\` and test.

Opened by the Check nginx workflow."
    fi
done

# 3. Inactivity warning.
LAST_COMMIT=$(git log -1 --format=%ct origin/develop 2>/dev/null || git log -1 --format=%ct)
AGE_DAYS=$(( ($(date +%s) - LAST_COMMIT) / 86400 ))
log "Last commit on develop: $AGE_DAYS days ago"
if [ "$AGE_DAYS" -ge "$INACTIVITY_WARN_DAYS" ]; then
    open_issue_once "Scheduled workflows go idle soon" \
        "There has been no commit on \`develop\` for $AGE_DAYS days. GitHub disables scheduled workflows in public repos after 60 days without activity. That would stop the weekly \`next\` rebuild and this check.

To reset the clock, merge or push any commit to \`develop\`. If they were already disabled, re-enable them with \`gh workflow enable buildNext.yml\` and \`gh workflow enable checkNginx.yml\`.

Opened by the Check nginx workflow."
fi
