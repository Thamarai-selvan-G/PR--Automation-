#!/usr/bin/env bash
# Builds the Teams Adaptive Card JSON for a pull_request event.
# Usage: USERS='{"gh-login":{"email":"..","name":".."}}' build-card.sh <event.json>
set -euo pipefail
ev="$1"
action=$(jq -r .action "$ev")

if [ "$action" = review_requested ]; then
  created=$(jq -r .pull_request.created_at "$ev")
  # ponytail: time-window dedupe — CODEOWNERS fires review_requested right after "opened",
  # which already lists those reviewers. Track posted PRs if this ever misfires.
  if [ $(( $(date +%s) - $(date -d "$created" +%s) )) -lt 30 ]; then
    echo "skip: covered by opened message" >&2
    exit 0
  fi
  reviewers=$(jq -c '[.requested_reviewer.login // empty]' "$ev")
  heading="👀 Review requested on PR"
else
  reviewers=$(jq -c '[.pull_request.requested_reviewers[].login]' "$ev")
  heading="🔀 New PR"
fi

jq -n --argjson users "${USERS:-"{}"}" --argjson reviewers "$reviewers" \
      --slurpfile e "$ev" --arg heading "$heading" '
  def who($login): ($users[$login] // null) as $u
    | if $u then {text: "<at>\($u.name)</at>",
                  entity: {type: "mention", text: "<at>\($u.name)</at>",
                           mentioned: {id: $u.email, name: $u.name}}}
      else {text: $login, entity: null} end;

  $e[0].pull_request as $pr
  | who($pr.user.login) as $author
  | [$reviewers[] | who(.)] as $revs
  | {type: "message", attachments: [{
      contentType: "application/vnd.microsoft.card.adaptive",
      content: {
        "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
        type: "AdaptiveCard", version: "1.4",
        body: ([
          {type: "TextBlock", weight: "Bolder", wrap: true,
           text: "\($heading) #\($pr.number) → \($pr.base.ref): \($pr.title)"},
          {type: "TextBlock", wrap: true, text: "**Raised by:** \($author.text)"},
          {type: "TextBlock", wrap: true,
           text: "**Reviewers:** \(if ($revs | length) > 0 then ($revs | map(.text) | join(", ")) else "none assigned" end)"}
        ] + (if ($pr.body // "") != "" then [{type: "TextBlock", wrap: true, text: ($pr.body | .[0:500])}] else [] end)),
        actions: [{type: "Action.OpenUrl", title: "Open PR", url: $pr.html_url}],
        msteams: {width: "Full",
                  entities: ([$author.entity] + ($revs | map(.entity)) | map(select(. != null)) | unique)}
      }}]}'
