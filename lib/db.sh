machine_of() {
	checknosp "$1" "required: machine or deployment name"
	if [ -d var/deploys/$1 ]; then
		checkfile var/deploys/$1/machine
		R1=$(cat $R1)
	elif [ -d var/machines/$1 ]; then
		R1=$1
	else
		die "No machine or deploy named: $1"
	fi
}

ip_of() {
	machine_of "$1"; R2=$R1
	checkfile var/machines/$R2/public_ip
	R1=$(cat $R1)
}
