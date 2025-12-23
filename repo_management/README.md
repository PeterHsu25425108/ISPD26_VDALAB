# Repo Management Scripts
Usage guide for scripts in /repo_management.

## update_repo.sh
Updates the repository with the latest contest information from https://github.com/ABKGroup/ISPD26-Contest.git. Automatically adds the remote if needed.

**Usage:**
```bash
bash update_repo.sh [pull|fetch]
```
- `pull` - Update local files directly
- `fetch` - Download updates without applying