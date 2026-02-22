# A bash script that:
# 1. Check if Contest_remote/main is one of the git remotes.
# 2. If it is, fetch or pull the latest changes from Contest_remote/main, whether
#    to perform a fetch or a pull is determined by the first argument passed to the script.
#    (Perform pull by default if no argument is given, otherwise perform fetch if the argument is "fetch".)
# 3. If it is not, print a message indicating that Contest_remote/main is not found, and add it 
#    as a new remote with:
#    git remote add -t main upstream https://github.com/ABKGroup/ISPD26-Contest.git
#   After adding the remote, first print messages with: cat .git/config
#   Then fetch/pull the latest changes from Contest_remote/main as per the first argument.

#!/bin/bash
umask 000
REMOTE_NAME="Contest_remote"
REMOTE_URL="https://github.com/ABKGroup/ISPD26-Contest.git"
BRANCH_NAME="main"
# Usage: ./update_repo.sh [fetch or pull]
ACTION=${1:-pull}
# Check if the remote exists
if git remote | grep -q "^${REMOTE_NAME}$"; then
    echo "${REMOTE_NAME} found. Performing ${ACTION} from ${REMOTE_NAME}/${BRANCH_NAME}..."
    if [ "$ACTION" == "fetch" ]; then
        git fetch ${REMOTE_NAME} ${BRANCH_NAME}
    else
        git pull ${REMOTE_NAME} ${BRANCH_NAME}
    fi
else
    echo "${REMOTE_NAME} not found. Adding it as a new remote..."
    git remote add -t ${BRANCH_NAME} ${REMOTE_NAME} ${REMOTE_URL}
    echo "Current git configuration:"
    cat .git/config
    echo "Performing ${ACTION} from ${REMOTE_NAME}/${BRANCH_NAME}..."
    if [ "$ACTION" == "fetch" ]; then
        git fetch ${REMOTE_NAME} ${BRANCH_NAME}
    else
        git pull ${REMOTE_NAME} ${BRANCH_NAME}
    fi
fi

echo "Operation completed. Now your repo should be up to date with the main branch of https://github.com/ABKGroup/ISPD26-Contest.git."