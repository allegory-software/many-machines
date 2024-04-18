checkargs() { # NAME1[-] ... - ARG1 ...
	local i=1
	while (($i <= $#)); do
		local arg=${!i}
		[[ $arg == - ]] && break
		((i++))
	done
	local n=$((i-1))
	local j=$((i+1))
	local i=1
	while ((i <= n)); do
		local k=${!j}
		local v=${!i}
		if [[ ${k::-1}- == $k ]]; then # spaces allowed
			k=${k::-1}
			[[ $v ]] || die "${FUNCNAME[1]}: $k required"
		else
			[[ $v ]] || die "${FUNCNAME[1]}: $k required"
			[[ $v =~ ( |\') ]] && die "${FUNCNAME[1]}: $k contains spaces"
		fi
		declare "$k=$v"
		((i++))
		((j++))
	done
	shift $((j-1))
}

