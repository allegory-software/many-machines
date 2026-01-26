# speedtest.net network speed tester

SPEEDTEST_DIR=/root/mm/tmp/speedtest-cli

install_speedtest() {
	[[ -e $SPEEDTEST_DIR/speedtest ]] && return
	local sys_bit=x86_64
	local url1="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${sys_bit}.tgz"
	local url2="https://dl.lamp.sh/files/ookla-speedtest-1.2.0-linux-${sys_bit}.tgz"
	local get="wget --no-check-certificate -q -T10 -O speedtest.tgz"
	run $get "$url1" || must $get "$url2"
	must mkdir -p $SPEEDTEST_DIR
	must tar zxf speedtest.tgz -C $SPEEDTEST_DIR
	must chmod +x $SPEEDTEST_DIR/speedtest
	must rm -f speedtest.tgz
}

ST_FMT="%-10s %-18s %-18s %-20s %-12s\n"

speedtest1() { # [SERVER_ID|list] [NODE_NAME]
	if ! run $SPEEDTEST_DIR/speedtest --progress=no --accept-license --accept-gdpr ${1:+--server-id="$1"} \
		> $SPEEDTEST_DIR/speedtest.log 2>&1
	then
		cat $SPEEDTEST_DIR/speedtest.log
	fi
	local dl_speed up_speed latency
	dl_speed=$(awk '/Download/{print $3" "$4}' $SPEEDTEST_DIR/speedtest.log)
	up_speed=$(awk '/Upload/{print $3" "$4}'   $SPEEDTEST_DIR/speedtest.log)
	latency=$(awk '/Latency/{print $3" "$4}'   $SPEEDTEST_DIR/speedtest.log)
	printf "$ST_FMT" "$MACHINE" "${2:-$1}" "$up_speed" "$dl_speed" "$latency"
}

_speedtest() { # [SERVER_ID|list]
	install_speedtest
	[[ $1 == list ]] && {
		must $SPEEDTEST_DIR/speedtest -L
		return
	}
	[[ $1 ]] && {
		speedtest1 "$1"
		return
	}
	# server ids at: https://williamyaps.github.io/wlmjavascript/servercli.html
	speedtest1 '' 'Speedtest.net'
	speedtest1 '21001' 'Los Angeles'
	speedtest1 '6027' 'Paris'
	speedtest1 '1536' 'Hong Kong'
}
speedtest() { # [SERVER_ID|list]
	[[ $1 != list && $MACHINES ]] && printf "$WHITE$ST_FMT$ENDCOLOR" MACHINE NODE UPLOAD DOWNLOAD LATENCY
	QUIET=1 NOALL=1 each_machine ssh_script "_speedtest $1"
}
