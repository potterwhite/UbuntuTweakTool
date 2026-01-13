# This command block will create the 'git-rewrite-author' command system-wide.
# It requires sudo privileges.

COMMAND_NAME="git-rewrite-author"
INSTALL_PATH="/usr/local/bin/${COMMAND_NAME}"

# Using a quoted 'EOF' delimiter to prevent any variable expansion by the current shell.
# This ensures the script content is written literally to the file.
sudo tee "$INSTALL_PATH" >/dev/null <<'EOF'
#!/bin/bash

# ==============================================================================
# Git Author Rewrite Tool
#
# A script to rewrite author/tagger information for all commits and
# annotated tags in a Git repository, with remote backup and restore.
#
# Author: PotterWhite
# Version: 3.0 (Interactive Remote Restore)
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u

# --- Global Variables ---
CORRECT_NAME=""
CORRECT_EMAIL=""
# Arrays to store backed-up remote names and URLs
declare -a BACKED_UP_REMOTES_NAMES=()
declare -a BACKED_UP_REMOTES_URLS=()


# --- Function Definitions ---

fn_print_usage() {
  echo "Usage: git-rewrite-author <path_to_git_repository>"
  echo
  echo "This script interactively rewrites the author/tagger history of a Git repository."
  echo "It changes all commits and tags, whose author/tagger email does not match"
  echo "the one you provide, to a new name and email."
  echo "It also backs up and offers to restore Git remotes."
  echo
}

fn_check_dependencies() {
  echo "--> Checking for dependencies..."
  if command -v git-filter-repo &> /dev/null; then
    echo "    [✔] git-filter-repo is already installed."
    return 0
  fi

  echo "    [!] 'git-filter-repo' command not found."
  read -p "    Do you want to attempt to install it using 'sudo apt'? (Y/n): " -r INSTALL_CHOICE

  if [[ -z "$INSTALL_CHOICE" || "$INSTALL_CHOICE" =~ ^[Yy]$ ]]; then
    echo "    Attempting installation. You may be asked for your password."
    sudo apt update && sudo apt install -y git-filter-repo
    echo "    [✔] git-filter-repo has been installed."
  else
    echo "    Installation cancelled by user. The script cannot continue."
    exit 1
  fi
}

fn_validate_path() {
  if [ "$#" -ne 1 ]; then
    echo "Error: Invalid number of arguments."
    echo
    fn_print_usage
    exit 1
  fi

  local repo_path="$1"
  echo "--> Validating path: ${repo_path}"

  if [ ! -d "$repo_path" ]; then
    echo "    Error: The provided path '${repo_path}' is not a directory."
    exit 1
  fi

  # Change directory, this is crucial for all subsequent git commands
  cd "$repo_path"

  if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    echo "    Error: The directory '${repo_path}' is not a Git repository."
    exit 1
  fi

  echo "    [✔] Path is a valid Git repository."
}

fn_backup_remotes() {
    echo
    echo "--> Backing up existing remote configurations..."

    # Read remote names into an array
    local remote_names
    mapfile -t remote_names < <(git remote)

    if [ ${#remote_names[@]} -eq 0 ]; then
        echo "    No remotes found to back up. Skipping."
        return
    fi

    for name in "${remote_names[@]}"; do
        local url
        url=$(git remote get-url "$name")
        BACKED_UP_REMOTES_NAMES+=("$name")
        BACKED_UP_REMOTES_URLS+=("$url")
        echo "    [✔] Backed up remote: '${name}' -> '${url}'"
    done
}

fn_get_user_input() {
  echo
  echo "--> Please provide your correct author and tagger information."

  read -p "    Enter your correct full name: " CORRECT_NAME
  read -p "    Enter your correct email (this is the unique identifier): " CORRECT_EMAIL

  while [[ -z "$CORRECT_EMAIL" ]]; do
    echo "    Email cannot be empty. It is required to identify your commits and tags."
    read -p "    Please enter your correct email: " CORRECT_EMAIL
  done

  echo "    [✔] User info captured."
}

fn_confirm_and_rewrite() {
  echo
  echo "--------------------------------------------------------"
  echo "                FINAL CONFIRMATION"
  echo "--------------------------------------------------------"
  echo "The script is ready to rewrite the history of the repository at: $(pwd)"
  echo
  echo "LOGIC: For every COMMIT and every ANNOTATED TAG, if the email is NOT '${CORRECT_EMAIL}',"
  echo "it will be changed to:"
  echo "  - Name:  '${CORRECT_NAME}'"
  echo "  - Email: '${CORRECT_EMAIL}'"
  echo
  echo "NOTE: Your remotes have been backed up and can be restored after this step."
  echo
  echo "WARNING: This operation is destructive and cannot be undone."
  echo "It is HIGHLY recommended to have a backup of this repository."
  echo "--------------------------------------------------------"

  read -p "Are you absolutely sure you want to proceed? (Y/n): " -r

  if [[ -n "$REPLY" && ! "$REPLY" =~ ^[Yy]$ ]]; then
    echo
    echo "Operation cancelled."
    exit 0
  fi

  echo
  echo "--> Rewriting history for commits and tags... This may take a while."

  local commit_callback_code="
name=b'""$CORRECT_NAME""'
email=b'""$CORRECT_EMAIL""'

if commit.author_email != name:
  commit.author_name = name 
  commit.author_email = email 
  commit.committer_name = name
  commit.committer_email = email
"
  local tag_callback_code="
if tag.tagger_email != b'""$CORRECT_EMAIL""':
  tag.tagger_name = b'""$CORRECT_NAME""'
  tag.tagger_email = b'""$CORRECT_EMAIL""'
"

  git filter-repo \
    --commit-callback "$commit_callback_code" \
    --tag-callback "$tag_callback_code" \
    --force
}

fn_restore_remotes_interactively() {
    if [ ${#BACKED_UP_REMOTES_NAMES[@]} -eq 0 ]; then
        return # No remotes were backed up, so nothing to restore.
    fi

    echo
    echo "--------------------------------------------------------"
    echo "             RESTORE REMOTE CONFIGURATIONS"
    echo "--------------------------------------------------------"
    echo "The following remotes were backed up before the history rewrite:"
    echo

    for i in "${!BACKED_UP_REMOTES_NAMES[@]}"; do
        printf "  %d) %s (%s)\n" "$((i+1))" "${BACKED_UP_REMOTES_NAMES[i]}" "${BACKED_UP_REMOTES_URLS[i]}"
    done

    echo
    echo "  a) All of the above"
    echo
    read -p "Enter numbers to restore (e.g., '1 3'), 'a' for all, or press Enter to skip: " -r -a SELECTIONS

    if [ ${#SELECTIONS[@]} -eq 0 ]; then
        echo "--> No selection made. Skipping remote restore."
        return
    fi

    echo "--> Restoring selected remotes..."
    local choices_to_restore=()

    if [[ " ${SELECTIONS[@]} " =~ " a " ]] || [[ " ${SELECTIONS[@]} " =~ " A " ]]; then
        # If 'a' or 'A' is present, restore all
        for i in "${!BACKED_UP_REMOTES_NAMES[@]}"; do
            choices_to_restore+=("$((i+1))")
        done
    else
        choices_to_restore=("${SELECTIONS[@]}")
    fi

    local restored_count=0
    for choice in "${choices_to_restore[@]}"; do
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#BACKED_UP_REMOTES_NAMES[@]} ]; then
            local index=$((choice-1))
            local name="${BACKED_UP_REMOTES_NAMES[index]}"
            local url="${BACKED_UP_REMOTES_URLS[index]}"
            git remote add "$name" "$url"
            echo "    [✔] Restored remote: '${name}'"
            ((restored_count++))
        else
            if [[ "$choice" != "a" && "$choice" != "A" ]]; then
                echo "    [!] Invalid selection '${choice}', skipping."
            fi
        fi
    done

    if [ "$restored_count" -gt 0 ]; then
        echo "    [✔] Remote restoration complete."
    else
        echo "    No valid remotes were restored."
    fi
}


fn_print_next_steps() {
  echo
  echo "✅ History rewrite completed successfully for both commits and tags!"
  echo
  echo "==================== NEXT STEPS ===================="
  echo "1. Review the new history to ensure it is correct:"
  echo "   git log --pretty=fuller"
  echo "   git show <your-tag-name>  # e.g., git show v1.0"
  echo

  # Check if any remotes exist now
  if [ -n "$(git remote)" ]; then
    echo "2. Your remotes have been restored. You can now push the changes:"
    echo "   IMPORTANT: This is a force-push. It will overwrite the remote history."
    echo
    echo "   Force-push your rewritten branches and tags:"
    echo "   git push --force-with-lease --tags <remote-name> <your-branch-name>"
    echo "   # Example: git push --force-with-lease --tags origin main"
  else
    echo "2. Re-add your remote and push the changes:"
    echo "   IMPORTANT: As a safety feature, git-filter-repo has REMOVED your remote"
    echo "   configuration and you chose not to restore them."
    echo
    echo "   You must re-add it before you can push:"
    echo "   a) Re-add the remote (get the URL from GitHub/GitLab):"
    echo "      git remote add origin <your-repository-url>"
    echo "      # Example: git remote add origin git@github.com:your-user/your-repo.git"
    echo
    echo "   b) Now, force-push your rewritten branches and tags:"
    echo "      git push --force-with-lease --tags origin <your-branch-name>"
  fi

  echo
  echo "3. Update your global Git config to prevent future errors:"
  echo "   git config --global user.name \"${CORRECT_NAME}\""
  echo "   git config --global user.email \"${CORRECT_EMAIL}\""
  echo "===================================================="
  echo
}

# --- Main Execution Logic ---

main() {
  fn_validate_path "$@"
  fn_check_dependencies
  fn_backup_remotes
  fn_get_user_input
  fn_confirm_and_rewrite
  fn_restore_remotes_interactively
  fn_print_next_steps
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
EOF

# Make the new script executable
sudo chmod +x "$INSTALL_PATH"

echo
echo "✅ Success! The command '${COMMAND_NAME}' is now installed with remote backup/restore functionality."
echo "You can now run it from anywhere, like this:"
echo "   ${COMMAND_NAME} /path/to/your/repo"
echo
echo "If you get 'command not found', try opening a new terminal session."
