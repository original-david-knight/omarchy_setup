#!/usr/bin/env bash
set -euo pipefail

printf 'Updating Omarchy and system packages before any personal setup.\n'
printf 'If Omarchy offers a reboot, defer it until setup finishes.\n'
# Keep this in the interactive preparation phase: some supported Omarchy
# versions still offer restart prompts even with -y. Omarchy requests sudo
# itself, so administrator and SSH configuration can wait until after updating.
omarchy update -y
