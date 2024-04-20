. mmlib

_mm_completion() {
	set -f
	set -o pipefail
	pushd /opt/mm
	local names
	active_deploys; names="$R1"
	active_machines; names+=" $R1"
	COMPREPLY=($(compgen -W "$names" -- "$2"))
	popd
	set +f
	set +o pipefail
}
complete -F _mm_completion mm

set +f
set +o pipefail
