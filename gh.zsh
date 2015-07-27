
gh_my_branch() {
    echo $(git rev-parse --abbrev-ref HEAD)
}

gh_from_json() {
    echo $1|jq -r $2
}

gh_base_sha() {
    gh_from_json "$1" '.base.sha'
}

gh_fetch_pr() {
    git fetch origin pull/$1/head:PR-$1
}

gh_checkout() {
    git checkout $1
}

gh_diff() {
    git diff $1 $2
}

gh_user() {
    [[ $(git config --get remote.origin.url) =~ "^.*github.com/|:(.*)/(.*).git$" ]] && echo $match[1]
}

gh_repo() {
    [[ $(git config --get remote.origin.url) =~ "^.*github.com/|:(.*)/(.*).git$" ]] && echo $match[2]
}

gh_get_prs() {
    RES=$(curl --silent -n https://api.github.com/repos/$(gh_user)/$(gh_repo)/pulls)
    if [ $(echo $RES|jq '. | length') = "0" ]; then
	echo "No PRs found"
    else
	TABLE=$(echo $RES|jq -r '.[] | "\(.number):\(.user.login)|\(.title)|(\(._links.html.href))"')
	column -t -s \| <<< $TABLE
	
    fi
}

gh_read_pr() {
    PRNO=$1
    RES=$(curl --silent -n https://api.github.com/repos/$(gh_user)/$(gh_repo)/pulls/$PRNO)
    if [ $(echo $RES|jq '.message') = "Not Found" ]; then
	echo "No such PR found"
    else
	FORMATTED=$(<<EOF
\(.number):\(.user.login): \(.title)
\(.body)

(o)pen, (c)heckout, (d)iff
EOF
		 )
	echo $RES|jq -r '"'$FORMATTED'"'
	read -rs -k 1 ANS
	case "${ANS}" in
	    o)
		open $(gh_from_json $RES '._links.html.href')
		;;
	    c)
		echo ".."
		gh_fetch_pr "$PRNO"
		gh_checkout "PR-$PRNO"
		;;
	    d)
		echo ".."
		BASE=$(gh_base_sha $RES)
		gh_fetch_pr "$PRNO"
		gh_diff "PR-$PRNO" "$BASE"
		;;
	    *)
		
	esac
    fi
}

gh_create_pr() {
    printf "Base (default master): "
    read -r BASE
    BASE=${BASE:-master}
    printf "Head (default $(gh_my_branch)): "
    read -r HEAD
    HEAD=${HEAD:-$(gh_my_branch)}
    if [ "$BASE" = "$HEAD" ]; then
	echo "Base and head cannot be the same branch"
    else
	TMPFILE=$(mktemp -t ghpr)
	TEMPLATE=$(<<EOF
Title: (Replace with PR title)
Enter description below:
EOF
		)
	echo $TEMPLATE > $TMPFILE
	$EDITOR $TMPFILE
	gh_pr_handle_draft $TMPFILE
	CREATE=$?
	if [[ "$CREATE" = "1" ]]; then
	    BODY=$(gh_parse_pr_description $TMPFILE|python -c 'import json,sys; print json.dumps(sys.stdin.read())')
	    TITLE=$(gh_parse_pr_title $TMPFILE|python -c 'import json,sys; print json.dumps(sys.stdin.read())')
	    JSON=$(<<EOF
{"title":$TITLE,"body":$BODY,"head":"$HEAD","base":"$BASE"}
EOF
		)
	    echo $(curl -n -X POST --data $JSON https://api.github.com/repos/$(gh_user)/$(gh_repo)/pulls)
	else
	    rm $TMPFILE
	fi
    fi
}

gh_pr_handle_draft() {
    $TMPFILE=$1
    gh_show_pr_draft $TMPFILE
    echo "(c)reate, (e)dit, (q)uit"
    read -rs -k 1 ANS
    case "${ANS}" in
	c)
	    return 1
	    ;;
	e)
	    $EDITOR $TMPFILE
	    gh_show_pr_draft $TMPFILE
	    gh_pr_handle_draft $TMPFILE
	    ;;
	*)
	    return 0
    esac
}

gh_show_pr_draft() {
    TMPFILE=$1
    echo "--------"
    echo "Title: $(gh_parse_pr_title $TMPFILE)"
    echo "Description:"
    gh_parse_pr_description $TMPFILE
    echo "--------"
}

gh_parse_pr_description() {
    echo "$(tail -n+3 $1)"
}

gh_parse_pr_title() {
    TITLELINE=$(head -n 1 $1)
    if [[ $(head -n 1 $1) =~ "^Title: (.*)$" ]]; then
	echo $match[1]
    else
	echo ""
    fi
}
