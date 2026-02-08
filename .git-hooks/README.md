# Git Hooks

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
