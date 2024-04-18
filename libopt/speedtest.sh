# speedtest.net network speed tester

install_speedtest() {
	[[ -e tmp/speedtest-cli/speedtest ]] && return
	local sys_bit=x86_64
	local url1="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${sys_bit}.tgz"
	local url2="https://dl.lamp.sh/files/ookla-speedtest-1.2.0-linux-${sys_bit}.tgz"
	local get="wget --no-check-certificate -q -T10 -O speedtest.tgz"
	run $get "$url1" || must $get "$url2"
	must mkdir -p tmp/speedtest-cli
	must tar zxf speedtest.tgz -C tmp/speedtest-cli
	must chmod +x tmp/speedtest-cli/speedtest
	must rm -f speedtest.tgz
}

speedtest1() { # [SERVER_ID|list] [NODE_NAME]
	if ! run tmp/speedtest-cli/speedtest --progress=no --accept-license --accept-gdpr ${1:+--server-id="$1"} \
		> tmp/speedtest-cli/speedtest.log 2>&1
	then
		cat tmp/speedtest-cli/speedtest.log
	fi
	local dl_speed up_speed latency
	dl_speed=$(awk '/Download/{print $3" "$4}' tmp/speedtest-cli/speedtest.log)
	up_speed=$(awk '/Upload/{print $3" "$4}'   tmp/speedtest-cli/speedtest.log)
	latency=$(awk '/Latency/{print $3" "$4}'   tmp/speedtest-cli/speedtest.log)
	printf "%-10s %-18s %-18s %-20s %-12s\n" "$MACHINE" "$2" "$up_speed" "$dl_speed" "$latency"
}

speedtest_header() {
	printf "%-10s %-18s %-18s %-20s %-12s\n" MACHINE NODE UPLOAD DOWNLOAD LATENCY
}

speedtest() { # [SERVER_ID|list]
	install_speedtest
	[[ $1 == list ]] && {
		must tmp/speedtest-cli/speedtest -L
		return
	}
	[[ $1 ]] && {
		speedtest1 "$1"
		return
	}
	speedtest1 ''      'Speedtest.net'
	speedtest1 '21541' 'Los Angeles, US'
	#speedtest1 '43860' 'Dallas, US'
	#speedtest1 '40879' 'Montreal, CA'
	speedtest1 '24215' 'Paris, FR'
	#speedtest1 '28922' 'Amsterdam, NL'
	#speedtest1 '24447' 'Shanghai, CN'
	#speedtest1 '5530'  'Chongqing, CN'
	#speedtest1 '60572' 'Guangzhou, CN'
	speedtest1 '32155' 'Hongkong, CN'
	speedtest1 '23647' 'Mumbai, IN'
	#speedtest1 '13623' 'Singapore, SG'
	#speedtest1 '21569' 'Tokyo, JP'
}
