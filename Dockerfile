gsq is a function
gsq () 
{ 
    if ! command -v fzf > /dev/null 2>&1; then
        echo "Γ¥ל fzf is not installed. Please install it first.";
        return 1;
    fi;
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        echo "Γ¥ל Not a git repository";
        return 1;
    fi;
    current_branch=$(git branch --show-current);
    commits=$(git log --color=always --format="%C(yellow)%h%Creset %s %Cgreen(%cr) %C(blue)<%an>%Creset" HEAD);
    if [ -z "$commits" ]; then
        echo "Γ¥ל No commits found in the current branch.";
        return 1;
    fi;
    echo "≡ƒפם Select the commit up to which you want to squash (all commits above will be included)";
    selected=$(echo "$commits" | fzf --height 40% --reverse --ansi --prompt="Select commit > " --preview 'git show --color=always $(echo {} | cut -d" " -f1)' --preview-window right:60%);
    if [ -z "$selected" ]; then
        echo "Γ¥ל No commit selected.";
        return 1;
    fi;
    commit_hash=$(echo "$selected" | cut -d" " -f1);
    commits_to_squash=$(git log --format="%an %h %s%n%b" "${commit_hash}^..HEAD" | while read -r line; do
    if [[ $line =~ ^[[:space:]]*$ ]]; then
        continue;
    fi
if [[ $line =~ ^[A-Za-z] ]]; then
        author=$(echo "$line" | cut -d' ' -f1)
hash=$(echo "$line" | cut -d' ' -f2)
msg=$(echo "$line" | cut -d' ' -f3-)
changes=$(git show --format="" --name-status "$hash" | awk '{
                if ($1 == "M") status="modified"
                else if ($1 == "A") status="added"
                else if ($1 == "D") status="removed"
                else if ($1 == "R") status="renamed"
                else status=$1
                printf "%s %s, ", status, $2
            }' | sed 's/, $//')
if [ ! -z "$changes" ]; then
            changes=" ($changes)";
        fi
echo "$author $hash $msg$changes";
    fi;
done);
    commit_count=$(echo "$commits_to_squash" | wc -l);
    echo -e "\n≡ƒפה The following commits will be squashed:";
    echo "----------------------------------------";
    echo "$commits_to_squash";
    echo "----------------------------------------";
    echo -n "Γ¥ף Are you sure you want to continue? [y/N] ";
    read -n 1 REPLY;
    echo;
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Γ¥ל Operation cancelled.";
        return 1;
    fi;
    echo -e "\n≡ƒף¥ Enter the new commit message:";
    read -r commit_message;
    if [ -z "$commit_message" ]; then
        echo "Γ¥ל Commit message cannot be empty.";
        return 1;
    fi;
    echo -e "\n≡ƒפה Performing squash...";
    current_head=$(git rev-parse HEAD);
    if git reset --soft "${commit_hash}^" && git commit -m "$commit_message"; then
        echo "Γ£ו Successfully squashed $commit_count commits!";
    else
        echo "Γ¥ל Failed to squash commits.";
        echo "≡ƒפה Rolling back to previous state...";
        git reset --hard "$current_head";
        return 1;
    fi
}
