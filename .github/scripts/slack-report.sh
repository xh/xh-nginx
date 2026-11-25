#!/usr/bin/env bash
# Posts to Slack when updates wait too long, so they are not missed. Run by
# .github/workflows/checkNginx.yml after each successful daily check. Posts only when an open PR
# (not a draft), or an open issue from the XH Build Bot, is STALE_DAYS old or more. Repeats every
# day until each is merged or closed. Quiet otherwise, so every post calls for action.
#
# Failed runs are reported separately, by the "alert" job of each workflow.
#
# Env: GH_TOKEN (for gh), SLACK_WEBHOOK_URL, RUN_URL (link to this run), FORCE_REPORT=1 to post
# even when nothing is stale (to test), DRY_RUN=1 to print the message instead of posting it.
set -euo pipefail

STALE_DAYS=${STALE_DAYS:-3}
DRY_RUN=${DRY_RUN:-0}
FORCE_REPORT=${FORCE_REPORT:-0}
NAME=xh-nginx
WORKFLOW="Check nginx"
# GitHub logins of the XH Build Bot app. Issues from people are not reported.
BOT_RE='^(app/)?xh-build-bot(\[bot\])?$'
# Items listed in one message. Keeps it under Slack's 3000 character section limit.
MAX_ITEMS=15

# Lines of "<age days>\t<draft>\t<kind> #<n>\t<title>\t<url>", oldest first: all open PRs, and
# open issues from the bot.
AGE='((now - (.createdAt | fromdateiso8601)) / 86400 | floor)'
PRS=$(gh pr list --state open --limit 100 --json number,title,url,createdAt,isDraft \
    --jq ".[] | [$AGE, .isDraft, \"PR #\(.number)\", .title, .url] | @tsv")
ISSUES=$(gh issue list --state open --limit 100 --json number,title,url,createdAt,author \
    --jq ".[] | [(.author.login // \"\"), $AGE, false, \"Issue #\(.number)\", .title, .url] | @tsv")
ISSUES=$(BOT_RE=$BOT_RE awk -F'\t' -v OFS='\t' '$1 ~ ENVIRON["BOT_RE"] { $1 = ""; sub(/^\t/, ""); print }' <<<"$ISSUES")
ITEMS=$(printf '%s\n%s\n' "$PRS" "$ISSUES" | grep . | sort -t$'\t' -k1,1nr || true)
STALE=$(awk -F'\t' -v d="$STALE_DAYS" '$1 >= d && $2 == "false"' <<<"$ITEMS" | grep -c . || true)

if [ "$STALE" = 0 ] && [ "$FORCE_REPORT" != 1 ]; then
    echo "Nothing to report: no open PR or bot issue is $STALE_DAYS+ days old."
    exit 0
fi

# Slack link text must not contain these.
esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
days() {
    case $1 in 0) echo "less than a day" ;; 1) echo "1 day" ;; *) echo "$1 days" ;; esac
}

if [ "$STALE" = 0 ]; then
    TITLE=":clipboard: $NAME: test post, nothing is waiting"
elif [ "$STALE" = 1 ]; then
    TITLE=":warning: $NAME: 1 item waiting $STALE_DAYS+ days for action"
else
    TITLE=":warning: $NAME: $STALE items waiting $STALE_DAYS+ days for action"
fi

RELEASE=$(gh release view --json tagName,publishedAt,url \
    --jq '"<\(.url)|\(.tagName | ltrimstr("v"))> · "
          + "\((now - (.publishedAt | fromdateiso8601)) / 86400 | floor)"')
RELEASE="${RELEASE% · *} · $(days "${RELEASE##* · }") ago"
PINNED=$(sed -nE 's/^ARG NGINX_VERSION=([0-9.]+).*/\1/p' Dockerfile)
[ -n "$PINNED" ] || { echo "::error::No NGINX_VERSION in Dockerfile"; exit 1; }

# One line per item. The age is bold once it has waited too long.
LIST=""
n=0
while IFS=$'\t' read -r age draft kind title url; do
    [ -n "$age" ] || continue
    n=$((n + 1))
    [ "$n" -le "$MAX_ITEMS" ] || continue
    open="open $(days "$age")"
    if [ "$draft" = true ]; then
        open="$open · draft"
    elif [ "$age" -ge "$STALE_DAYS" ]; then
        open="*$open*"
    fi
    LIST="${LIST}• <$url|$kind $(esc <<<"$title")> · $open"$'\n'
done <<<"$ITEMS"
[ "$n" -le "$MAX_ITEMS" ] || LIST="${LIST}…and $((n - MAX_ITEMS)) more."$'\n'
LIST=${LIST%$'\n'}
[ -n "$LIST" ] || LIST="None."

PAYLOAD=$(jq -n \
    --arg text "$TITLE" \
    --arg release "*Latest release*"$'\n'"$RELEASE" \
    --arg pinned "*Pinned nginx*"$'\n'"$PINNED" \
    --arg list "*Open PRs and bot issues*"$'\n'"$LIST" \
    --arg footer "From the <$RUN_URL|$WORKFLOW> workflow. Reported once open $STALE_DAYS+ days, and daily until merged or closed." \
    '{text: $text, blocks: [
        {type: "header", text: {type: "plain_text", text: $text, emoji: true}},
        {type: "section", fields: [{type: "mrkdwn", text: $release}, {type: "mrkdwn", text: $pinned}]},
        {type: "section", text: {type: "mrkdwn", text: $list}},
        {type: "context", elements: [{type: "mrkdwn", text: $footer}]}
    ]}')

if [ "$DRY_RUN" = 1 ]; then
    echo "DRY_RUN: would post to Slack:"
    echo "$PAYLOAD"
    exit 0
fi
[ -n "${SLACK_WEBHOOK_URL:-}" ] || { echo "::error::SLACK_WEBHOOK_URL is not set"; exit 1; }
curl -fsS --retry 3 -X POST -H 'Content-Type: application/json' --data "$PAYLOAD" "$SLACK_WEBHOOK_URL"
echo
echo "Posted to Slack."
