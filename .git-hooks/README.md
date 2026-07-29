# Git Hooks

## Pre-Push Hook — review-loop gate

`pre-push` chains two checks: the foreign-branch force-push warning, and the **review-loop gate** (`review-gate.sh`).

The gate blocks a push that would newly publish commits **you authored** whose tip sha isn't recorded as reviewed. review-loop records the sha on a clean exit (`~/.claude/skills/review-loop/record-reviewed.sh` → `~/.claude/review-loop/reviewed-shas`). Pushes containing only foreign-authored commits (dependabot, teammates, upstream merges) pass untouched.

- **Bypass one push:** `REVIEW_GATE_BYPASS=1 git push`
- **Husky repos:** husky's local `core.hooksPath` shadows this global hook, so those repos need a `.husky/pre-push` delegator (`[ -x "$HOME/.git-hooks/review-gate.sh" ] && "$HOME/.git-hooks/review-gate.sh" "$@"`), kept untracked via `.git/info/exclude`.
- **Self-test:** `~/.git-hooks/review-gate.test.sh`

## Pre-Commit Hook

The `pre-commit` hook performs multiple checks before allowing a commit:

1. **GitButler Workspace Branch Warning** - Warns before committing to `gitbutler/workspace` branch
2. **Blacklist String Checker** - Checks staged files for sensitive strings

### Setup

1. **Symlink the hook** (if not already done):
   ```bash
   ln -sf ~/.git-hooks/pre-commit ~/.git/hooks/pre-commit
   ```

2. **Create your blacklist file** at `~/.gitblacklist.txt`:
   ```bash
   cat > ~/.gitblacklist.txt << 'EOF'
   # Git Commit Blacklist
   # Add sensitive strings that should not be committed (one per line)
   # Lines starting with # are comments
   # Matching is case-insensitive - no need to add case variations

   # Add your sensitive strings here
   # Examples (matches any case):
   # mycompany
   # secretproject
   # myusername
   EOF
   ```

3. **Make the hook executable** (if needed):
   ```bash
   chmod +x ~/.git-hooks/pre-commit
   ```

### How It Works

- Reads patterns from `~/.gitblacklist.txt`
- **Case-insensitive matching** - no need to add case variations (e.g., just add "myproject", matches "MyProject", "MYPROJECT", etc.)
- Checks all staged files for any blacklisted strings
- Shows violations with file names and line numbers
- Asks for confirmation before allowing the commit
- Blocks commits automatically in non-interactive environments (CI/CD)

### Adding Blacklist Entries

Edit `~/.gitblacklist.txt` and add one pattern per line:

```
# Project names
secretproject
companyname

# Personal info
myusername
myemail
```

The hook will automatically use the updated blacklist on the next commit attempt.
