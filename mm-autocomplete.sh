_mm_completion() {
	local names
	names+=" $(ls -1 /opt/mm/var/machines)"
	names+=" $(ls -1 /opt/mm/var/deploys)"
	names+=" $(ls /opt/mm/cmd)"
	COMPREPLY=($(compgen -W "$names" -- "$2"))
}
complete -F _mm_completion mm
complete -F _mm_completion mmd
