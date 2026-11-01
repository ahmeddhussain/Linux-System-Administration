#!/usr/bin/env bash
# Runs on control01 (piped over SSH by scripts/lab.sh). Safe to re-run.
set -eo pipefail

main() {
  local repo_url="https://github.com/ahmeddhussain/Linux-System-Administration.git"
  local repo_dir="$HOME/ahmed-infra"
  local venv="$HOME/ansible-venv"

  retry() {
    local n=0
    until "$@"; do
      n=$((n + 1))
      if [ "$n" -ge 6 ]; then return 1; fi
      echo "Attempt $n failed, retrying in 15s: $*"
      sleep 15
    done
  }

  # The OS repositories can take a minute to become usable after first boot.
  retry sudo dnf install -y git python3 python3-pip

  if [ -d "$repo_dir/.git" ]; then
    git -C "$repo_dir" pull --ff-only
  else
    git clone "$repo_url" "$repo_dir"
  fi

  if [ ! -d "$venv" ]; then python3 -m venv "$venv"; fi
  # shellcheck disable=SC1091
  source "$venv/bin/activate"
  pip install --quiet --upgrade pip
  pip install --quiet -r "$repo_dir/ansible/requirements.txt"
  ansible-galaxy collection install -r "$repo_dir/ansible/requirements.yml"

  if [ ! -f "$HOME/.ssh/ansible_ed25519" ]; then
    ssh-keygen -t ed25519 -N "" -C "ansible@control01" -f "$HOME/.ssh/ansible_ed25519"
  fi

  grep -qF 'ansible-venv/bin/activate' "$HOME/.bashrc" \
    || echo 'source ~/ansible-venv/bin/activate' >> "$HOME/.bashrc"

  echo "control01 is ready."
}

# The function is read in full before it runs, and stdin is closed, so no
# command in it can swallow the rest of a script piped over SSH.
main < /dev/null