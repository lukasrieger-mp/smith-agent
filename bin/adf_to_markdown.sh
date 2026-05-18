#!/usr/bin/env bash
# Flatten an Atlassian Document Format (ADF) JSON document on stdin to a
# minimal Markdown rendering on stdout.
#
# Supports the node types Smith encounters in JIRA ticket descriptions:
#   doc, paragraph, text (with strong/em/code marks), heading (level 1-6),
#   bulletList/orderedList + listItem, hardBreak.
#
# Unsupported nodes are silently dropped — the brief is a best-effort
# rendering, not a faithful one.
#
# Usage: cat adf.json | adf_to_markdown.sh
set -euo pipefail

# Validate JSON.
input=$(cat)
echo "$input" | jq -e 'type == "object"' >/dev/null

# jq walks the tree node-by-node. Output is plain text with newlines.
echo "$input" | jq -r '
  def render_text:
    if .marks then
      reduce .marks[] as $m (.text;
        if $m.type == "strong" then "**" + . + "**"
        elif $m.type == "em" then "*" + . + "*"
        elif $m.type == "code" then "`" + . + "`"
        else . end)
    else .text end;

  def render_inline:
    if .type == "text" then render_text
    elif .type == "hardBreak" then "\n"
    else "" end;

  def render_block:
    if .type == "heading" then
      "\n" + ("#" * (.attrs.level // 2)) + " " +
        ([.content[]? | render_inline] | join("")) + "\n"
    elif .type == "paragraph" then
      "\n" + ([.content[]? | render_inline] | join("")) + "\n"
    elif .type == "bulletList" then
      ([.content[]? |
         "- " + ([.content[]? | select(.type=="paragraph") |
                   ([.content[]? | render_inline] | join(""))] | join(" ")) +
         "\n"] | join(""))
    elif .type == "orderedList" then
      ([.content[]? |
         "1. " + ([.content[]? | select(.type=="paragraph") |
                    ([.content[]? | render_inline] | join(""))] | join(" ")) +
         "\n"] | join(""))
    else "" end;

  [.content[]? | render_block] | join("")
' | sed -E 's/^ +$//' | awk 'NF || prev {print; prev=NF} !NF && !prev {prev=0}'
