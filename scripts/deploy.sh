#!/bin/bash
#!/bin/bash
# ------------------------------------------------------------------------
# Dual Remote Push Script for MAIASS / AICommit
#
# This script automates the process of pushing the same codebase to two
# differently branded Git remotes: `maiass` (main repo) and `aicommit`
# (commit-only variant). It ensures the correct README is used for each
# brand and maintains a clean working tree throughout the process.
#
# ⚠ This script is intended for maintainers of the project only.
#    It is not part of the functionality of MAIASS or AICommit themselves.
#
# Features:
# - Merges `staging` into `main`
# - Ensures correct `README.md` for each target brand
# - Pushes to `origin` (MAIASS) and `ai` (AICommit) in sequence
# - Stashes local changes and restores original branch after push
#
# Requires:
# - Two configured remotes: `origin` (MAIASS) and `ai` (AICommit)
# - `main` and optionally `staging` branches
# - `docs/README.maiass.md` and `docs/README.aicommit.md`
#
# Usage:
#   bash scripts/push-dual.sh
#
# Do not include this script in AICommit distributions.
# ------------------------------------------------------------------------

set -e

# --- Colors for output ---
BGreen='\033[1;32m'
BYellow='\033[1;33m'
BRed='\033[1;31m'
Color_Off='\033[0m'


# --- Copy correct README before pushing to main ---
prepare_maiass_readme() {
  echo -e "${BGreen}📄 Copying MAIASS README...${Color_Off}"
  cp docs/README.maiass.md README.md
}

# --- Copy correct README before pushing to aicommit ---
prepare_aicommit_readme() {
  echo -e "${BGreen}📄 Copying AICOMMIT README...${Color_Off}"
  cp docs/README.aicommit.md README.md
}

# --- Utility: Ensure clean worktree and stash if needed ---
with_clean_worktree() {
  local orig_branch
  orig_branch=$(git symbolic-ref --short HEAD)

  local stash_needed=false
  if [[ -n "$(git status --porcelain)" ]]; then
    echo -e "${BYellow}🔒 Stashing local changes...${Color_Off}"
    git stash push -u -m "auto-stash for maiass/aicommit push"
    stash_needed=true
  fi

  "$@"  # run the supplied function

  echo -e "${BYellow}🔄 Returning to original branch: ${orig_branch}${Color_Off}"
  git checkout "$orig_branch" >/dev/null 2>&1

  if $stash_needed; then
    echo -e "${BYellow}📦 Restoring stashed changes...${Color_Off}"
    git stash pop
  fi
}

# --- Ensure you're on main or bail ---
ensure_on_main_or_fail() {
  local current_branch
  current_branch=$(git symbolic-ref --short HEAD)
  if [[ "$current_branch" != "main" ]]; then
    echo -e "${BRed}❌ Refusing to push to ai: You must be on the main branch.${Color_Off}"
    exit 1
  fi
}

# --- Switch to main, merge from staging, push to origin ---
merge_staging_to_main_and_push() {
  echo -e "${BGreen}🔁 Switching to main and merging from staging...${Color_Off}"
  git checkout main
  git pull origin main

  if git show-ref --verify --quiet refs/heads/staging; then
    git merge staging --no-edit || {
      echo -e "${BRed}❌ Merge failed. Resolve manually.${Color_Off}"
      exit 1
    }
  else
    echo -e "${BYellow}⚠️  No staging branch found. Skipping merge.${Color_Off}"
  fi

  prepare_maiass_readme
  git add README.md
  git commit -m "Update README for MAIASS" || true
  git push origin main
}

push_to_aicommit() {
  ensure_on_main_or_fail

  prepare_aicommit_readme
  git add README.md
  git commit -m "Temporary: swap README for AICommit push" || true

  echo -e "${BYellow}🧹 Removing push-dual.sh from staged files before AICommit push...${Color_Off}"
  git restore --staged scripts/push-dual.sh || true

  echo -e "${BGreen}🚀 Pushing to AICommit...${Color_Off}"
  git push ai main

  echo -e "${BYellow}🧼 Restoring push-dual.sh to working directory...${Color_Off}"
  git restore scripts/push-dual.sh || true

  echo -e "${BGreen}↩️ Reverting README to MAIASS...${Color_Off}"
  prepare_maiass_readme
  git add README.md
  git commit -m "Revert README to MAIASS" || true
}
# --- Full push workflow ---
full_push_flow() {
  echo -e "${BGreen}🧠 Performing full push: merge, push, dual-brand...${Color_Off}"

  with_clean_worktree merge_staging_to_main_and_push
  with_clean_worktree push_to_aicommit

  echo -e "${BGreen}✅ All done. Both repos updated.${Color_Off}"
}

# --- Execute ---
full_push_flow
