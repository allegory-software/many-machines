
ddns_update_ip() {
	must machine_var public_ip; local IP=$R1
	must deploy_var .ddns_password; local DDNS_PASS=$R1
	say -n "Updating IP for domain '$DOMAIN' to '$IP' at namecheap.com ... "
	local s
	s=$(must curl -s "https://dynamicdns.park-your-domain.com/update?host=@&domain=$DOMAIN&password=$DDNS_PASS&ip=$IP") \
		|| die "curl: [$?]"
	if ! grep -q '<Done>true</Done>' <<< "$s"; then
		say "Failed. Response:"
		say "$s"
		exit 1
	fi
	say "OK"
}
