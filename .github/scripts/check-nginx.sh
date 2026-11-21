#!/usr/bin/env bash
# Checks for nginx and base image updates, and flags repo inactivity. Run daily by
# .github/workflows/checkNginx.yml. Outcomes, each idempotent:
#
#  1. A newer patch on the pinned major.minor line, published by *both* nginx and
#     fholzer/nginx-brotli, opens a PR to develop that bumps NGINX_VERSION and adds a CHANGELOG
#     line. Skipped if a PR for that version already exists, whether open, closed or merged. A new
#     bump PR closes older open bump and refresh PRs, which it supersedes.
#  2. Upstream rebuilds its base images for OS and package updates without an nginx version change.
#     If either upstream image is no longer the base of our latest release, a PR to develop adds a
#     CHANGELOG note, to prompt a patch release. The branch is keyed on our released images and
#     the note, so there is at most one open refresh PR, and a PR a person closes stays closed.
#     Skipped while a bump PR is open or a release is already due, as that release builds on the
#     newest base images anyway. Open refresh PRs close once our images are current again.
#  3. A newer major.minor line published by both images opens an issue. Moving lines is a judgment
#     call, so it is never automated.
#  4. No commit on develop for INACTIVITY_WARN_DAYS opens an issue. GitHub disables scheduled
#     workflows in public repos after 60 days without activity, including this one. The issue is
#     closed again once develop is active, so the next idle spell alerts afresh.
#
# Any failed call to Docker Hub, the registry or GitHub fails the run, so it never reads as
# "nothing to do". Only a failed read of the nginx CHANGES does not. The bump PR then says so.
#
# Env: GH_TOKEN (for gh - in CI, an XH Build Bot token so its PRs and issues show as that bot),
# DRY_RUN=1 to print actions instead of taking them. For testing, with DRY_RUN=1:
# PINNED_OVERRIDE (e.g. 1.31.6) overrides the pinned version, COMPARE_RELEASE (e.g. 3.4.0)
# compares upstream against that release's tags instead of latest, and INACTIVITY_WARN_DAYS sets
# the idle threshold. Needs docker with buildx.
set -euo pipefail

INACTIVITY_WARN_DAYS=${INACTIVITY_WARN_DAYS:-45}
DRY_RUN=${DRY_RUN:-0}
COMPARE_RELEASE=${COMPARE_RELEASE:-latest}
REPO=xhio/xh-nginx
# Branches this script opens PRs from. It only ever closes PRs from these, opened by the bot.
BUMP_RE='^nginx-[0-9]+\.[0-9]+\.[0-9]+$'
REFRESH_PREFIX=base-refresh-
REFRESH_RE="^${REFRESH_PREFIX}[0-9a-f]+$"
REFRESH_NOTE="* Rebuilt on the latest upstream base images, with their OS and package updates."
FOOTER="Opened by the Check nginx workflow."

log() { echo "$*" >&2; }
err() { echo "::error::$*" >&2; }
act() { # Run a command, or just print it in a dry run.
    if [ "$DRY_RUN" = "1" ]; then log "DRY_RUN: $*"; else "$@"; fi
}

# All X.Y.Z versions on a major.minor line in a Docker Hub repo, following pagination. Returns 1
# on any error. Args: repo (e.g. library/nginx), tag prefix ("" or "v"), major.minor (e.g. 1.31).
line_versions() {
    local repo=$1 prefix=$2 minor=$3 url page names all=""
    url="https://hub.docker.com/v2/repositories/${repo}/tags?page_size=100&name=${prefix}${minor}."
    while [ -n "$url" ]; do
        page=$(curl -fsS --retry 3 "$url") || { err "Docker Hub request failed: $url"; return 1; }
        names=$(jq -r 'if (.results | type) == "array" then .results[].name else error("no results") end' <<<"$page") \
            || { err "Unexpected Docker Hub response: $url"; return 1; }
        all+="$names"$'\n'
        url=$(jq -r '.next // empty' <<<"$page") || return 1
    done
    { grep -E "^${prefix}${minor//./\\.}\\.[0-9]+$" <<<"$all" || true; } | sed "s/^$prefix//" | sort -u
}

# Newest X.Y.Z on a line that both images publish. fholzer/nginx-brotli can lag the official
# image, and both variants must stay on the same nginx version. Call it as `x=$(newest_common l)`
# at the top level, so a failure fails the run.
newest_common() {
    local official brotli
    official=$(line_versions library/nginx "" "$1") || exit 1
    brotli=$(line_versions fholzer/nginx-brotli v "$1") || exit 1
    comm -12 <(echo "$official") <(echo "$brotli") | { grep . || true; } | sort -V | tail -1
}

# Security entries from nginx's CHANGES for versions newer than $1, up to and including $2.
# Returns 1 if the page can't be fetched or has no entry for $2, so an outage or a format change is
# never reported as "no security fixes".
nginx_security_cves() {
    local page
    page=$(curl -fsS --retry 3 https://nginx.org/en/CHANGES) || return 1
    grep -qF "Changes with nginx $2 " <<<"$page" || return 1
    awk -v to="$2" -v from="$1" '
            /^Changes with nginx / { v = $4; on = (v == to) ? 1 : (v == from ? 0 : on) }
            on' <<<"$page" \
        | tr '\n' ' ' | grep -oE 'CVE-[0-9]+-[0-9]+' | sort -u || true
}

# The nginx version, creation date and rootfs layers of an image's linux/amd64 variant, as JSON.
# The nginx version is empty for fholzer/nginx-brotli, which does not set NGINX_VERSION. Returns 1
# on any error, so a registry problem is never read as "no change".
image_info() {
    local out
    out=$(docker buildx imagetools inspect "$1" --format '{{json .Image}}') \
        || { err "Could not inspect $1"; return 1; }
    jq -ce '(if has("rootfs") then . else (.["linux/amd64"] // error("no linux/amd64 image")) end)
        | {nginx: ([.config.Env[]? | select(startswith("NGINX_VERSION="))][0] // "" | ltrimstr("NGINX_VERSION=")),
           created: (.created // ""),
           layers: (.rootfs.diff_ids | arrays // error("no layers"))}' <<<"$out" \
        || { err "Unexpected image config for $1"; return 1; }
}

# Numbers of open issues with this exact title. Call it as `x=$(open_issues t) || exit 1`.
open_issues() {
    gh issue list --state open --search "in:title \"$1\"" --json number,title \
        --jq ".[] | select(.title == \"$1\") | .number" \
        || { err "Could not list issues titled $1"; return 1; }
}

open_issue_once() { # Args: title, body. Skips if an open issue already has this title.
    local found
    found=$(open_issues "$1") || exit 1
    if [ -n "$found" ]; then
        log "Issue already open: $1"
    else
        act gh issue create --title "$1" --body "$2"
    fi
}

# States of the PRs with this head branch, comma-separated, or empty if none. Call it as
# `x=$(pr_states b) || exit 1`, so a gh failure fails the run instead of reading as "no PR".
pr_states() {
    local states
    states=$(gh pr list --state all --head "$1" --json state --jq '.[].state') \
        || { err "Could not list PRs for $1"; return 1; }
    { grep . <<<"$states" || true; } | sort -u | paste -sd, -
}

# Head branches of the bot's open PRs to develop whose branch matches regex $1. Call it as
# `x=$(open_bot_prs re) || exit 1`.
open_bot_prs() {
    local out
    out=$(gh pr list --state open --base develop --limit 200 --json headRefName,author) \
        || { err "Could not list open PRs"; return 1; }
    jq -r --arg re "$1" '.[] | select((.headRefName | test($re))
        and (.author.login | test("^(app/)?xh-build-bot(\\[bot\\])?$"))) | .headRefName' <<<"$out"
}

# Close the bot's open PRs from other branches matching any of the given regexes. The PR from this
# branch is built from develop and supersedes them. Args: branch, regex...
close_superseded() {
    local branch=$1 re old olds
    shift
    for re in "$@"; do
        olds=$(open_bot_prs "$re") || exit 1
        for old in $olds; do
            [ "$old" = "$branch" ] && continue
            act gh pr close "$old" --delete-branch --comment "Superseded by the PR from \`$branch\`."
        done
    done
}

# True if every closed PR from this branch was closed by this script as superseded, not by a person.
only_superseded() {
    local out
    out=$(gh pr list --state closed --head "$1" --json comments \
        --jq 'all(.[]; any(.comments[]; (.body | startswith("Superseded by"))
            and (.author.login | test("^(app/)?xh-build-bot(\\[bot\\])?$"))))') \
        || { err "Could not read PR comments for $1"; exit 1; }
    [ "$out" = true ]
}

# True if the CHANGELOG's `## next` section has this exact line.
next_has_line() {
    awk '/^## / { in_next = ($0 ~ /^## next/) } in_next' CHANGELOG.md | grep -qxF "$1"
}

# Add a line at the top of the CHANGELOG's `## next` section, creating the section if needed.
changelog_add() {
    if ! grep -q '^## next' CHANGELOG.md; then
        awk 'done != 1 && /^## / { print "## next - under development"; print ""; print ""; done = 1 } { print }' \
            CHANGELOG.md >CHANGELOG.md.new
        mv CHANGELOG.md.new CHANGELOG.md
    fi
    # The line goes in via the environment, as `awk -v` would expand backslashes in it.
    LINE=$1 awk '
        done != 1 && /^## next/ { print; print ""; print ENVIRON["LINE"]; done = 1; skip_blank = 1; next }
        skip_blank { skip_blank = 0; if ($0 == "") next }
        { print }' CHANGELOG.md >CHANGELOG.md.new
    mv CHANGELOG.md.new CHANGELOG.md
    next_has_line "$1" || { err "Could not add a line to the CHANGELOG"; exit 1; }
}

# Commit the working tree changes to a new branch as the bot, push it, open a PR to develop, and
# close the open PRs it supersedes. Args: branch, title, body, regex of superseded branches...
open_pr() {
    local branch=$1 title=$2 body=$3 rc=0
    shift 3
    git ls-remote --exit-code --heads origin "$branch" >/dev/null || rc=$?
    [ $rc = 0 ] || [ $rc = 2 ] || { err "Could not list remote branches"; exit 1; }
    act git checkout -b "$branch"
    # Commit as the XH Build Bot app's bot user. The email is GitHub's noreply form,
    # <user id>+<login>, which links the commit to that account (id from
    # `gh api 'users/xh-build-bot[bot]'`).
    act git -c user.name="xh-build-bot[bot]" \
        -c user.email="324593885+xh-build-bot[bot]@users.noreply.github.com" \
        commit -m "$title" -- Dockerfile CHANGELOG.md
    if [ $rc = 0 ]; then
        # A past run pushed the branch but failed to open the PR. It's the bot's own branch,
        # rebuilt from develop, so replace it.
        log "Branch $branch exists with no PR - replacing it."
        act git push --force origin "$branch"
    else
        act git push origin "$branch"
    fi
    act gh pr create --base develop --head "$branch" --title "$title" --body "$body"
    close_superseded "$branch" "$@"

    if [ "$DRY_RUN" = "1" ]; then
        git --no-pager diff -- Dockerfile CHANGELOG.md
        git checkout -- Dockerfile CHANGELOG.md
        # Confirm the token can push, without creating anything.
        git push --dry-run --force origin "HEAD:refs/heads/$branch"
    fi
}

#-----------------------------------------------------------------------------------------------
if { [ -n "${PINNED_OVERRIDE:-}" ] || [ "$COMPARE_RELEASE" != "latest" ]; } && [ "$DRY_RUN" != "1" ]; then
    err "PINNED_OVERRIDE and COMPARE_RELEASE are for testing and require a dry run"
    exit 1
fi
PINNED=${PINNED_OVERRIDE:-$(sed -nE 's/^ARG NGINX_VERSION=([0-9]+\.[0-9]+\.[0-9]+)$/\1/p' Dockerfile)}
if [ -z "$PINNED" ]; then
    err "Could not read NGINX_VERSION from Dockerfile"
    exit 1
fi
MINOR=${PINNED%.*}
MAJOR=${MINOR%.*}
log "Pinned nginx: $PINNED (line $MINOR)"

if [ "$DRY_RUN" = "1" ]; then
    # A dry run edits these files to show the diff, then restores them from HEAD. Refuse to run on
    # local changes to them, which the restore would lose.
    git diff --quiet HEAD -- Dockerfile CHANGELOG.md \
        || { err "Dry run needs Dockerfile and CHANGELOG.md unchanged from HEAD"; exit 1; }
    trap 'git checkout -q -- Dockerfile CHANGELOG.md' EXIT
fi

# 1. Newer patch on the pinned line.
BUMP_PENDING=0
LATEST=$(newest_common "$MINOR")
log "Newest $MINOR.x in both images: ${LATEST:-none}"
if [ -z "$LATEST" ]; then
    # At least the pinned version should be there.
    err "No $MINOR.x version found in both nginx and fholzer/nginx-brotli. Check Docker Hub."
    exit 1
fi
if [ "$LATEST" != "$PINNED" ] \
    && [ "$(printf '%s\n%s\n' "$PINNED" "$LATEST" | sort -V | tail -1)" = "$LATEST" ]; then
    BRANCH="nginx-$LATEST"
    # Key off the PR, not the branch, so a run that pushed the branch but failed to open the PR is
    # retried. Open: nothing to do. Closed or merged: someone decided, so don't reopen it daily.
    STATES=$(pr_states "$BRANCH") || exit 1
    if [ -n "$STATES" ]; then
        log "PR for $BRANCH already exists ($STATES)."
        case $STATES in *OPEN*)
            BUMP_PENDING=1
            # In case a past run opened it but failed to close the PRs it supersedes.
            close_superseded "$BRANCH" "$BUMP_RE" "$REFRESH_RE" ;;
        esac
    else
        BUMP_PENDING=1
        # Short note for the CHANGELOG, full CVE list for the PR body.
        CVE_LIST=""
        if CVES=$(nginx_security_cves "$PINNED" "$LATEST"); then
            CVE_COUNT=$(grep -c . <<<"$CVES" || true)
            if [ "$CVE_COUNT" -gt 0 ]; then
                NOTE="with $CVE_COUNT nginx security fix$([ "$CVE_COUNT" = 1 ] || echo es)"
                CVE_LIST="- ${CVES//$'\n'/$'\n'- }"
            else
                NOTE="with no security fixes listed in the nginx CHANGES"
            fi
        else
            echo "::warning::Could not read security fixes for $LATEST from the nginx CHANGES" >&2
            NOTE="but the nginx CHANGES could not be read to list its security fixes"
        fi
        log "Bumping $PINNED -> $LATEST, $NOTE"

        sed -i.bak -E "s/^ARG NGINX_VERSION=.*/ARG NGINX_VERSION=$LATEST/" Dockerfile && rm Dockerfile.bak
        grep -qx "ARG NGINX_VERSION=$LATEST" Dockerfile || { err "Could not bump NGINX_VERSION in Dockerfile"; exit 1; }
        changelog_add "* Pinned nginx \`$LATEST\` (from \`$PINNED\`), $NOTE."

        BODY="Bumps the pinned nginx version in the \`Dockerfile\` from \`$PINNED\` to \`$LATEST\`, $NOTE.
${CVE_LIST:+
$CVE_LIST
}
Both \`nginx:$LATEST\` and \`fholzer/nginx-brotli:v$LATEST\` are published. See the [nginx CHANGES](https://nginx.org/en/CHANGES) for details.

Merging rebuilds the \`next\` tags. To publish it, release from \`master\` as usual. The release also picks up any upstream OS and package updates.

$FOOTER"
        # A bump release also builds on the newest base images, so it supersedes refresh PRs too.
        open_pr "$BRANCH" "Bump nginx to $LATEST" "$BODY" "$BUMP_RE" "$REFRESH_RE"
    fi
fi

# Any open bot bump PR holds back refresh PRs, even one for a version Docker Hub no longer lists.
if [ $BUMP_PENDING = 0 ]; then
    OPEN_BUMPS=$(open_bot_prs "$BUMP_RE") || exit 1
    if [ -n "$OPEN_BUMPS" ]; then BUMP_PENDING=1; fi
fi

# 2. Base images. Our images are built FROM upstream, so while upstream is unchanged our layers
# start with its layers. Both variants are released together on the same nginx version, so the
# standard image's NGINX_VERSION stands for both.
OURS=$(image_info "$REPO:$COMPARE_RELEASE") || exit 1
OUR_NGINX=$(jq -r .nginx <<<"$OURS")
[ -n "$OUR_NGINX" ] || { err "No NGINX_VERSION in $REPO:$COMPARE_RELEASE"; exit 1; }
STALE_ROWS=""  # One PR body table row per variant whose upstream was rebuilt.
OUR_LAYERS=""  # Layers of each of our images, to key the refresh branch.
if [ "$OUR_NGINX" != "$PINNED" ]; then
    # E.g. a merged bump PR. The next release builds on the newest base images anyway.
    log "$REPO:$COMPARE_RELEASE has nginx $OUR_NGINX, develop pins $PINNED. A release is due."
    RELEASE_DUE=1
else
    RELEASE_DUE=0
    for variant in "|nginx:$PINNED" "-brotli|fholzer/nginx-brotli:v$PINNED"; do
        ours="$COMPARE_RELEASE${variant%%|*}"
        upstream=${variant#*|}
        if [ "$ours" != "$COMPARE_RELEASE" ]; then OURS=$(image_info "$REPO:$ours") || exit 1; fi
        OUR_LAYERS+="$(jq -c .layers <<<"$OURS")"$'\n'
        UP=$(image_info "$upstream") || exit 1
        if jq -en --argjson u "$UP" --argjson o "$OURS" '$o.layers[0:($u.layers | length)] == $u.layers' >/dev/null; then
            log "$ours is built on the current $upstream"
        else
            created=$(jq -r '.created[0:10]' <<<"$UP")
            log "$upstream has been rebuilt since $ours (upstream built ${created:-unknown})"
            STALE_ROWS+="| \`$ours\` | \`$upstream\` | ${created:-unknown} |"$'\n'
        fi
    done
fi

if [ $RELEASE_DUE = 1 ]; then
    : # Logged above.
elif [ -z "$STALE_ROWS" ]; then
    # Our images are current, e.g. after a release, so an open refresh PR's note is now wrong.
    OLDS=$(open_bot_prs "$REFRESH_RE") || exit 1
    for old in $OLDS; do
        act gh pr close "$old" --delete-branch --comment "Our \`$COMPARE_RELEASE\` images are built on the current upstream images. Closing."
    done
elif [ $BUMP_PENDING = 1 ]; then
    log "Upstream base images were rebuilt, but a bump PR is open. Its release will pick them up."
else
    # Keyed on our images and the note. A new release gets a new PR, while more upstream rebuilds
    # before a release, on either variant, don't churn the open one.
    BRANCH=$REFRESH_PREFIX$(printf '%s\n%s\n' "$OUR_LAYERS" "$REFRESH_NOTE" | git hash-object --stdin | cut -c1-10)
    STATES=$(pr_states "$BRANCH") || exit 1
    if [ "$STATES" = CLOSED ] && only_superseded "$BRANCH"; then
        # Closed by a bump PR that was then closed without merging. Nobody declined this refresh.
        log "PR for $BRANCH was superseded by a PR that is now closed. Opening it again."
        STATES=""
    fi
    if [ -n "$STATES" ]; then
        log "PR for $BRANCH already exists ($STATES)."
        case $STATES in *OPEN*) close_superseded "$BRANCH" "$REFRESH_RE" ;; esac
    elif next_has_line "$REFRESH_NOTE"; then
        # E.g. a merged refresh PR is waiting for a release, which will build on the newest images.
        log "The CHANGELOG already has the refresh note. A release is due."
    else
        changelog_add "$REFRESH_NOTE"
        BODY="Upstream has rebuilt the base images of our \`$COMPARE_RELEASE\` release, for OS and package updates. Our next release builds on the new ones:

| Our image | Upstream base | Upstream built |
|-----------|---------------|----------------|
$STALE_ROWS
Merging adds a CHANGELOG note. To ship the update, merge \`develop\` to \`master\` and release a new patch version as usual. A release rebuilds both variants on the newest upstream images.

$FOOTER"
        open_pr "$BRANCH" "Refresh base images: upstream OS and package updates" "$BODY" "$REFRESH_RE"
    fi
fi

# 3. Newer major.minor line. Checks the next two minors (nginx alternates stable and mainline).
for next in "$MAJOR.$((${MINOR#*.} + 1))" "$MAJOR.$((${MINOR#*.} + 2))"; do
    NEW_LINE=$(newest_common "$next")
    if [ -n "$NEW_LINE" ]; then
        log "Newer line available: $next (newest $NEW_LINE)"
        open_issue_once "nginx $next is available" \
            "Both \`nginx\` and \`fholzer/nginx-brotli\` now publish nginx \`$NEW_LINE\`. We pin \`$PINNED\`. Moving to the \`$next\` line is a manual change: bump \`NGINX_VERSION\` in the \`Dockerfile\` and test.

$FOOTER"
    fi
done

# 4. Inactivity warning.
LAST_COMMIT=$(git log -1 --format=%ct origin/develop 2>/dev/null || git log -1 --format=%ct)
AGE_DAYS=$(( ($(date +%s) - LAST_COMMIT) / 86400 ))
log "Last commit on develop: $AGE_DAYS days ago"
IDLE_TITLE="Scheduled workflows go idle soon"
if [ "$AGE_DAYS" -lt "$INACTIVITY_WARN_DAYS" ]; then
    # Close a past warning once develop is active again, so the next idle spell alerts afresh.
    IDLE_ISSUES=$(open_issues "$IDLE_TITLE") || exit 1
    for n in $IDLE_ISSUES; do
        act gh issue close "$n" --comment "\`develop\` has a commit from $AGE_DAYS days ago. Closing."
    done
else
    open_issue_once "$IDLE_TITLE" \
        "There has been no commit on \`develop\` for $AGE_DAYS days. GitHub disables scheduled workflows in public repos after 60 days without activity. That would stop the weekly \`next\` rebuild and this check.

To reset the clock, merge or push any commit to \`develop\`. If they were already disabled, re-enable them with \`gh workflow enable buildNext.yml\` and \`gh workflow enable checkNginx.yml\`.

$FOOTER"
fi
