install_speedtest() {
    if [ ! -e "tmp/speedtest-cli/speedtest" ]; then
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
        must mkdir -p tmp/speedtest-cli
        must tar zxf speedtest.tgz -C tmp/speedtest-cli
        must chmod +x tmp/speedtest-cli/speedtest
        must rm -f speedtest.tgz
    fi
}

speedtest() {
    printf "%-18s%-18s%-20s%-12s\n" " Node Name" "Upload Speed" "Download Speed" "Latency"
}
speed_test() {
    local nodeName="$2"
    if [ -z "$1" ];then
        tmp/speedtest-cli/speedtest --progress=no --accept-license --accept-gdpr >tmp/speedtest-cli/speedtest.log 2>&1
    else
        tmp/speedtest-cli/speedtest --progress=no --server-id="$1" --accept-license --accept-gdpr >tmp/speedtest-cli/speedtest.log 2>&1
    fi
    if [[ $? == 0 ]]; then
        local dl_speed up_speed latency
        dl_speed=$(awk '/Download/{print $3" "$4}' ./speedtest-cli/speedtest.log)
        up_speed=$(awk '/Upload/{print $3" "$4}' ./speedtest-cli/speedtest.log)
        latency=$(awk '/Latency/{print $3" "$4}' ./speedtest-cli/speedtest.log)
        if [[ -n "${dl_speed}" && -n "${up_speed}" && -n "${latency}" ]]; then
            printf "\033[0;33m%-18s\033[0;32m%-18s\033[0;31m%-20s\033[0;36m%-12s\033[0m\n" " ${nodeName}" "${up_speed}" "${dl_speed}" "${latency}"
        fi
    fi
}
