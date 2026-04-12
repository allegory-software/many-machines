_mm_completion() {
	local DIR=~/mm
	local names
	names+=" $(ls -1 $DIR/var/machines)"
	names+=" $(ls -1 $DIR/var/deploys)"
	names+=" $(ls $DIR/cmd)"
	COMPREPLY=($(compgen -W "$names" -- "$2"))
}
complete -F _mm_completion mm
complete -F _mm_completion mmd
