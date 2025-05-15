# real-time monitoring

checkvars MACHINE \
	MIN_FREE_RAM_MB \
	MIN_FREE_HDD_MB \
	MAX_CPU \
	MAXT_FREE_RAM \
	MAXT_FREE_HDD \
	MAXT_CPU

# config ---------------------------------------------------------------------

# probing intervals
PROBE_TICK=${PROBE_TICK:-60}
# these are multiples of PROBE_TICK
SAMPLE_TICK=1
NOTIFY_TICK=1

# sample logging & alerts ----------------------------------------------------

# change the log file when today becomes tomorrow.
set_file() {
	T0=`date -d '00:00' +%s`
	T1=`date -d 'tomorrow 00:00' +%s`
	FILE=`date +%F`
}
set_file

# count consecutive times when value was out of range.
# we only report values that were out of range more than MAXT times.
declare -A COUNTS # k->n

log() { # K= V= MIN= MAX= [MAXT=] N= P= T= T0= DIR= FILE=

	# log the value in samples file to show in a graph
	[[ -d mon/samples/$K ]] || {
		must mkdir -p mon/samples/$K
		printf "%d\n" $MIN > mon/samples/$K/min
		printf "%d\n" $MAX > mon/samples/$K/max
	}
	printf "%05d %s\n" $((T - T0)) $V >> mon/samples/$K/$FILE.sam

	# check alert thresholds
	local ALERT
	if ((V < MIN || V > MAX)); then
		((COUNTS[$K]++))
		local C=${COUNTS[$K]}
		local MAXT=${MAXT:-1}
		if ((C >= MAXT)); then
			ALERT=!
		fi
	else
		COUNTS[$K]=0
	fi

	# show the value when running mon in foreground.
	printf "%15s %1s %s\n" $K "$ALERT" $V

	# record alert
	[[ $ALERT != "" ]] && {
		local file=mon/alerts/$K
		must mkdir -p mon/alerts
		printf "%s\n" $V > $file
	}
}

notify() {
	must mkdir -p mon/notified
	must mkdir -p mon/alerts
	must pushd mon/alerts
	local f s=
	set +f # enable globbing
	for f in *; do
		[[ -f ../notified/$f && $(find ../notified/$f -mmin -1440) ]] && continue
		touch ../notified/$f
		s="$s$f: $(cat "$f")"$'\n'
	done
	set -f # disable globbing
	must popd
	[[ $s ]] || return
	mm ntfy -H "Tags: warning" -H "Title: MM @ $MACHINE ALERT" -d "$s"
}

# probing modules ------------------------------------------------------------

RAM_KB=`get_RAM_KB`
HDD_KB=`get_HDD_KB`
MIN_FREE_RAM_KB=$((MIN_FREE_RAM_MB * 1024))
MIN_FREE_HDD_KB=$((MIN_FREE_HDD_MB * 1024))
probe_free() {
	K=RAM V=`get_FREE_RAM_KB` MAX=$RAM_KB MIN=$MIN_FREE_RAM_KB MAXT=$MAXT_FREE_RAM log
	K=HDD V=`get_FREE_HDD_KB` MAX=$HDD_KB MIN=$MIN_FREE_HDD_KB MAXT=$MAXT_FREE_HDD log
}

unset CPU_STATS1
unset CPU_STATS2
probe_cpu() {
	CPU_STATS2=()
	local line
	while IFS= read -r line; do
		[[ $line == cpu[0-9]* ]] && CPU_STATS2+=("$line")
	done < /proc/stat

	if declare -p CPU_STATS1 &>/dev/null; then # we have at least 2 samples
		local i
		for i in "${!CPU_STATS1[@]}"; do # go through all cpu cores
			local -a f1; read -a f1 <<<"${CPU_STATS1[i]}"
			local -a f2; read -a f2 <<<"${CPU_STATS2[i]}"

			local idle1=${f1[4]}
			local idle2=${f2[4]}

			local total1=0 total2=0
			local n; for n in "${f1[@]:1}"; do ((total1+=n)); done
			local n; for n in "${f2[@]:1}"; do ((total2+=n)); done

			local total=$((total2 - total1))
			local idle=$((idle2 - idle1))
			local usage=$((100 * (total - idle) / total))
			K=CPU$i V=$usage MAX=$MAX_CPU MIN=0 MAXT=$MAXT_CPU log
		done
	fi
	CPU_STATS1=("${CPU_STATS2[@]}")
}

probe_deploy_services() {
	active_deploys; local DEPLOYS=$R1
	local DEPLOY
	for DEPLOY in $DEPLOYS; do
		machine_of_deploy $DEPLOY; [[ $R1 != $MACHINE ]] && continue
		md_var DEPLOY_SERVICES; local DEPLOY_SERVICES=$R1
		md_var APP; local APP=$R1
		for SERVICE in $DEPLOY_SERVICES; do
			local V; md_is_running $SERVICE && V=1 || V=0
			K=d-${DEPLOY}-${SERVICE} MAX=1 MIN=1 log
		done
	done
}

probe_services() {
	md_var SERVICES; local SERVICES=$R1
	for SERVICE in $SERVICES; do
		local V; md_is_running $SERVICE && V=1 || V=0
		K=s-$SERVICE MAX=1 MIN=1 log
	done
}

# main loop ------------------------------------------------------------------

# trap Ctrl+C to stop the loop cleanly.
STOP=
trap 'STOP=1' SIGTERM SIGINT

N=0
on_tick() { ((N % $1 == 0)); }
next_tick() {
	N=$((N+1))
	sleep $PROBE_TICK  # returns immediately on Ctrl+C
}
while [[ ! $STOP ]]; do

	[[ -f mon/paused ]] && {
		next_tick
		continue
	}

	on_tick $SAMPLE_TICK && {

		echo

		T=`date +%s`
		((T1 > T)) || set_file

		printf "%15s %1s %s\n" @ "" "$(date '+%F %T')"

		probe_free
		probe_cpu
		probe_deploy_services
		probe_services

		echo

	}

	on_tick $NOTIFY_TICK && notify

	next_tick
done
say "Stopped."
