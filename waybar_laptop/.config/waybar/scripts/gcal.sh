#!/bin/bash
# Get the next calendar event for waybar

next=$(gcalcli --cal "david@knight.fm" --cal "zenbulogy@gmail.com" --cal "david.knight@fluxon.com" agenda --nostarted --tsv "$(date '+%Y-%m-%dT%H:%M')" "$(date -d '+24 hours' '+%Y-%m-%dT%H:%M')" 2>/dev/null | tail -n +2 | head -1)

if [[ -z "$next" ]]; then
    echo '{"text": "", "tooltip": "No upcoming meetings", "class": "empty"}'
else
    # Parse TSV: start_date, start_time, end_date, end_time, title
    start_time=$(echo "$next" | cut -f2)
    title=$(echo "$next" | cut -f5)
    short_title=$(echo "$title" | cut -c1-25)

    # Add ellipsis if truncated
    [[ ${#title} -gt 25 ]] && short_title="${short_title}…"

    echo "{\"text\": \"󰃰 ${start_time} ${short_title}\", \"tooltip\": \"${title}\"}"
fi
