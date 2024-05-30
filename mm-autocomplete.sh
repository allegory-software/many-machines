_mm_completion() {
	local names
	names+=" $(ls -1 /root/mm/var/machines)"
	names+=" $(ls -1 /root/mm/var/deploys)"
	names+=" $(ls /root/mm/cmd)"
	COMPREPLY=($(compgen -W "$names" -- "$2"))
}
complete -F _mm_completion mm
complete -F _mm_completion mmd
