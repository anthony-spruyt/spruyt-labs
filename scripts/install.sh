#!/bin/bash
set -euo pipefail

echo "======================="
echo "Talos Cluster Installer"
echo "======================="
echo ""

chmod u+x *.sh

read -rp "Reset cluster? (y/n): " resetanswer
if [[ "$resetanswer" =~ ^[Yy]$ ]]; then
  ./reset-node.sh
elif [[ "$resetanswer" =~ ^[Nn]$ ]]; then
  echo "Skipping reset."
else
  echo "Invalid input. Exiting by default."
  exit 1
fi

echo "!!!WARNING!!! Existing secrets will be overwritten !!!WARNING!!!"
read -rp "Generate cluster secrets? (y/n): " secretanswer
if [[ "$secretanswer" =~ ^[Yy]$ ]]; then
  ./secrets.sh
elif [[ "$secretanswer" =~ ^[Nn]$ ]]; then
  echo "Skipping secrets generation."
else
  echo "Invalid input. Exiting by default."
  exit 1
fi

./generate.sh

read -rp "Apply cluster configuration? (y/n): " applyanswer
if [[ "$applyanswer" =~ ^[Yy]$ ]]; then
  ./apply.sh
elif [[ "$applyanswer" =~ ^[Nn]$ ]]; then
  echo "Skipping configuration application."
else
  echo "Invalid input. Exiting by default."
  exit 1
fi

read -rp "Bootstrap Flux? (y/n): " fluxanswer
if [[ "$fluxanswer" =~ ^[Yy]$ ]]; then
  ./flux-bootstrap.sh
elif [[ "$fluxanswer" =~ ^[Nn]$ ]]; then
  echo "Skipping Flux bootstrap."
else
  echo "Invalid input. Exiting by default."
  exit 1
fi