install_speedtest() {
    if [ ! -e "./speedtest-cli/speedtest" ]; then
        sys_bit=""
        local sysarch
        sysarch="$(uname -m)"
        if [ "${sysarch}" = "unknown" ] || [ "${sysarch}" = "" ]; then
            sysarch="$(arch)"
        fi
        if [ "${sysarch}" = "x86_64" ]; then
            sys_bit="x86_64"
        fi
        if [ "${sysarch}" = "i386" ] || [ "${sysarch}" = "i686" ]; then
            sys_bit="i386"
        fi
        if [ "${sysarch}" = "armv8" ] || [ "${sysarch}" = "armv8l" ] || [ "${sysarch}" = "aarch64" ] || [ "${sysarch}" = "arm64" ]; then
            sys_bit="aarch64"
        fi
        if [ "${sysarch}" = "armv7" ] || [ "${sysarch}" = "armv7l" ]; then
            sys_bit="armhf"
        fi
        if [ "${sysarch}" = "armv6" ]; then
            sys_bit="armel"
        fi
        [ -z "${sys_bit}" ] && _red "Error: Unsupported system architecture (${sysarch}).\n" && exit 1
        url1="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${sys_bit}.tgz"
        url2="https://dl.lamp.sh/files/ookla-speedtest-1.2.0-linux-${sys_bit}.tgz"
        if ! wget --no-check-certificate -q -T10 -O speedtest.tgz ${url1}; then
            if ! wget --no-check-certificate -q -T10 -O speedtest.tgz ${url2}; then
                die "Failed to download speedtest-cli."
            fi
        fi
        must mkdir -p speedtest-cli && tar zxf speedtest.tgz -C ./speedtest-cli && chmod +x ./speedtest-cli/speedtest
        must rm -f speedtest.tgz
    fi
}

speedtest() {
    printf "%-18s%-18s%-20s%-12s\n" " Node Name" "Upload Speed" "Download Speed" "Latency"
}
