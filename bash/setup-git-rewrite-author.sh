# This command block will create the 'git-rewrite-author' command system-wide.
# It requires sudo privileges.

COMMAND_NAME="git-rewrite-author"
INSTALL_PATH="/usr/local/bin/${COMMAND_NAME}"

# Using a quoted 'EOF' delimiter to prevent any variable expansion by the current shell.
# This ensures the script content is written literally to the file.
sudo tee "$INSTALL_PATH" > /dev/null <<'EOF'
#!/bin/bash

# ==============================================================================
# Git Author Rewrite Tool
#
# A script to rewrite author/tagger information for all commits and
# annotated tags in a Git repository.
#
# Author: PotterWhite
# Version: 2.4 (Corrected Here-Document handling)
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u

# --- Global Variables ---
CORRECT_NAME=""
CORRECT_EMAIL=""


# --- Function Definitions ---

fn_print_usage() {
  echo "Usage: git-rewrite-author <path_to_git_repository>"
  echo
  echo "This script interactively rewrites the author/tagger history of a Git repository."
  echo "It changes all commits and tags, whose author/tagger email does not match"
  echo "the one you provide, to a new name and email."
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

  cd "$repo_path"

  if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    echo "    Error: The directory '${repo_path}' is not a Git repository."
    exit 1
  fi

  echo "    [✔] Path is a valid Git repository."
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
if commit.author_email != b'""$CORRECT_EMAIL""':
  commit.author_name = b'""$CORRECT_NAME""'
  commit.author_email = b'""$CORRECT_EMAIL""'
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

fn_print_next_steps() {
  echo
  echo "✅ History rewrite completed successfully for both commits and tags!"
  echo
  echo "==================== NEXT STEPS ===================="
  echo "1. Review the new history to ensure it is correct:"
  echo "   git log --pretty=fuller"
  echo "   git show <your-tag-name>  # e.g., git show v1.0"
  echo
  echo "2. Re-add your remote and push the changes:"
  echo "   IMPORTANT: As a safety feature, git-filter-repo has REMOVED your remote"
  echo "   configuration (e.g., 'origin') to prevent accidental pushes."
  echo
  echo "   You must re-add it before you can push:"
  echo "   a) Re-add the remote (get the URL from GitHub/GitLab):"
  echo "      git remote add origin <your-repository-url>"
  echo "      # Example: git remote add origin git@github.com:your-user/your-repo.git"
  echo
  echo "   b) Now, force-push your rewritten branches and tags:"
  echo "      git push --force-with-lease --tags origin <your-branch-name>"
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
  fn_get_user_input
  fn_confirm_and_rewrite
  fn_print_next_steps
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
EOF

# Make the new script executable
sudo chmod +x "$INSTALL_PATH"

echo
echo "✅ Success! The command '${COMMAND_NAME}' is now installed."
echo "You can now run it from anywhere, like this:"
echo "   ${COMMAND_NAME} /path/to/your/repo"
echo
echo "If you get 'command not found', try opening a new terminal session."
