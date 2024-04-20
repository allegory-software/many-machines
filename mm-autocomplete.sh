. mmlib

_mm_completion() {
	pushd /opt/mm
	local names
	active_deploys; names="$R1"
	active_machines; names+=" $R1"
	COMPREPLY=($(compgen -W "$names" -- "$2"))
	popd
}
complete -F _mm_completion mm
