#!/bin/bash
# ------------------------------------------------------------------------
# Dual Remote Push Script for MAIASS / committhis
#
# This script automates the process of pushing the same codebase to two
# differently branded Git remotes: `maiass` (main repo) and `committhis`
# (commit-only variant). It ensures the correct README is used for each
# brand and maintains a clean working tree throughout the process.
#
# ⚠ This script is intended for maintainers of the project only.
#    It is not part of the functionality of MAIASS or committhis themselves.
#
# Features:
# - Merges `staging` into `main`
# - Ensures correct `README.md` for each target brand
# - Pushes to `origin` (MAIASS) and `ai` (committhis) in sequence
# - Stashes local changes and restores original branch after push
#
# Requires:
# - Two configured remotes: `origin` (MAIASS) and `ai` (committhis)
# - `main` and optionally `staging` branches
# - `docs/README.maiass.md` and `docs/README.committhis.md`
#
# Usage:
#   bash scripts/dply.sh
#
# Do not include this script in committhis distributions.
# ------------------------------------------------------------------------

set -e

# --- Colors for output ---
BGreen='\033[1;32m'
BYellow='\033[1;33m'
BRed='\033[1;31m'
Color_Off='\033[0m'

print_info() { echo -e "${BLUE}ℹ $1${Color_Off}"; }
print_success() { echo -e "${GREEN}✔ $1${Color_Off}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${Color_Off}"; }
print_error() { echo -e "${RED}✗ $1${Color_Off}"; }
# --- Copy correct README before pushing to main ---
prepare_maiass_readme() {
  echo -e "${BGreen}📄 Copying MAIASS README...${Color_Off}"
  cp docs/README.maiass.md README.md
  if ! git diff --quiet README.md; then
    git add README.md
    git commit -m "Revert README to MAIASS"
  else
    echo -e "${BYellow}ℹ️ MAIASS README unchanged. No commit needed.${Color_Off}"
  fi
}

# --- Copy correct README before pushing to committhis ---
prepare_committhis_readme() {
  echo -e "${BGreen}📄 Copying committhis README...${Color_Off}"
  cp docs/README.committhis.md README.md
  if ! git diff --quiet README.md; then
    git add README.md
    git commit -m "Temporary: swap README for committhis push"
  else
    echo -e "${BYellow}ℹ️ committhis README already in place. No commit needed.${Color_Off}"
  fi
}

# --- Utility: Ensure clean worktree and stash if needed ---
with_clean_worktree () {
  local orig_branch
  orig_branch=$(git symbolic-ref --short HEAD)

  local stash_needed=false
  if [[ -n "$(git status --porcelain)" ]]; then
    echo -e "${BYellow}🔒 Stashing local changes...${Color_Off}"
    git stash push -u -m "auto-stash for maiass/committhis push"
    stash_needed=true
  fi

  "$@"  # run the supplied function

  echo -e "${BYellow}🔄 Returning to original branch: ${orig_branch}${Color_Off}"
  git checkout "$orig_branch" >/dev/null 2>&1

  # merge main into original branch, if needed
  if [[ "$orig_branch" != "main" ]]; then
    echo -e "${BYellow}🔄 Merging latest main into ${orig_branch}...${Color_Off}"
    git merge main --no-edit || {
      echo -e "${BRed}❌ Merge failed on return to ${orig_branch}. Please resolve manually.${Color_Off}"
      exit 1
    }
  fi

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
  version_tag=$(git tag | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)

    printf "Create GitHub release for v$version_tag? (y/N): "
    read CONFIRM_RELEASE
    if [[ "$CONFIRM_RELEASE" =~ ^[Yy]$ ]]; then
      if ! command -v gh >/dev/null 2>&1; then
        print_error "GitHub CLI (gh) not found. Run: brew install gh"
        exit 1
      fi
      gh repo set-default vsmash/maiass
      gh release create "$version_tag" \
        --title "$version_tag" \
        --notes "Automated release for version $version_tag" \
        --repo "vsmash/maiass" && print_success "Release created." || print_error "Release failed."
    else
      print_info "Skipped release."
    fi
}

push_to_committhis() {
  ensure_on_main_or_fail

  prepare_committhis_readme
  git add README.md
  git commit -m "Temporary: swap README for committhis push" || true

  echo -e "${BYellow}🧹 Removing scripts/dply.sh from staged files before committhis push...${Color_Off}"
  git restore --staged scripts/dply.sh || true

  echo -e "${BGreen}🚀 Pushing to committhis...${Color_Off}"
  git push committhis main

  echo -e "${BYellow}🧼 Restoring dply.sh to working directory...${Color_Off}"
  git restore scripts/dply.sh || true
  push_version_tag_to_committhis
  version_tag=$(git tag | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)

    printf "Create GitHub release for v$version_tag? (y/N): "
    read CONFIRM_RELEASE
    if [[ "$CONFIRM_RELEASE" =~ ^[Yy]$ ]]; then
      if ! command -v gh >/dev/null 2>&1; then
        print_error "GitHub CLI (gh) not found. Run: brew install gh"
        exit 1
      fi
      gh repo set-default vsmash/committhis
      gh release create "$version_tag" \
        --title "$version_tag" \
        --notes "Automated release for version $version_tag" \
        --repo "vsmash/committhis" && print_success "Release created." || print_error "Release failed."
    else
      print_info "Skipped release."
    fi

  echo -e "${BGreen}↩️ Reverting README to MAIASS...${Color_Off}"
  prepare_maiass_readme
  git add README.md
  git commit -m "Revert README to MAIASS" || true
}

push_version_tag_to_committhis() {
  echo -e "${BGreen}🏷️  Finding latest version tag...${Color_Off}"
  version_tag=$(git tag | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)

  if [[ -z "$version_tag" ]]; then
    echo -e "${BRed}❌ No suitable version tag found.${Color_Off}"
    return 1
  fi

  if git rev-parse "$version_tag" >/dev/null 2>&1; then
    echo -e "${BGreen}🚀 Pushing tag ${version_tag} to committhis...${Color_Off}"
    git push committhis "$version_tag"
  else
    echo -e "${BRed}❌ Tag ${version_tag} not found locally. Has it been created yet?${Color_Off}"
    return 1
  fi
}

# --- Full push workflow ---
full_push_flow() {
  echo -e "${BGreen}🧠 Performing full push: merge, push, dual-brand...${Color_Off}"

  with_clean_worktree () {
    local orig_branch
    orig_branch=$(git symbolic-ref --short HEAD)

    local stash_needed=false
    if [[ -n "$(git status --porcelain)" ]]; then
      echo -e "${BYellow}🔒 Stashing local changes...${Color_Off}"
      git stash push -u -m "auto-stash for maiass/committhis push"
      stash_needed=true
    fi

    git checkout main
    merge_staging_to_main_and_push
    push_to_committhis

    echo -e "${BYellow}🔄 Returning to original branch: ${orig_branch}${Color_Off}"
    git checkout "$orig_branch" >/dev/null 2>&1

    if [[ "$orig_branch" != "main" ]]; then
      echo -e "${BYellow}🔄 Merging latest main into ${orig_branch}...${Color_Off}"
      git merge main --no-edit || {
        echo -e "${BRed}❌ Merge failed on return to ${orig_branch}. Please resolve manually.${Color_Off}"
        exit 1
      }
    fi

    if $stash_needed; then
      echo -e "${BYellow}📦 Restoring stashed changes...${Color_Off}"
      git stash pop
    fi
  }

  with_clean_worktree

  echo -e "${BGreen}✅ All done. Both repos updated.${Color_Off}"
}
# --- Execute ---
full_push_flow
