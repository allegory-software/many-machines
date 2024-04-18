# I/O speed tester

io_test() {
	must sync
	must echo 1 > /proc/sys/vm/drop_caches
	(
	LANG=C must dd if=/dev/zero of=benchtest_$$ bs=128k count="$1" conv=fdatasync
	rm -f benchtest_$$
	) 2>&1 | awk -F '[,，]' '{io=$NF} END { print io}' | sed 's/^[ \t]*//;s/[ \t]*$//'
}

get_IO_SPEED() {
	local freespace=`get_FREE_HDD_KB`
	((freespace > 1024*128)) || die "Not enough space for I/O speed test!"
	io_test 1024
}
