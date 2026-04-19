#!/bin/bash

THRESHOLD=60
STATUS="healthy"
EXPLAIN=false

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        explain) EXPLAIN=true ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [explain]"
            exit 1
            ;;
    esac
done

# CPU utilisation (percentage used) — sampled over 1 second from /proc/stat
read -r cpu user nice system idle iowait irq softirq steal _ < /proc/stat
sleep 1
read -r cpu2 user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 _ < /proc/stat
IDLE_DELTA=$(( (idle2 + iowait2) - (idle + iowait) ))
TOTAL_DELTA=$(( (user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + steal2) - (user + nice + system + idle + iowait + irq + softirq + steal) ))
CPU_USED=$(( 100 * (TOTAL_DELTA - IDLE_DELTA) / TOTAL_DELTA ))

# Memory utilisation (percentage used)
MEM_TOTAL=$(free | awk '/^Mem:/{print $2}')
MEM_USED=$(free | awk '/^Mem:/{print $3}')
MEM_PCT=$(echo "scale=0; $MEM_USED * 100 / $MEM_TOTAL" | bc)

# Disk utilisation (percentage used on root filesystem)
DISK_PCT=$(df / | awk 'NR==2{gsub(/%/,""); print $5}')

echo "===== VM Health Check ====="
echo "CPU  used : ${CPU_USED}%"
echo "Memory used : ${MEM_PCT}%"
echo "Disk used : ${DISK_PCT}%"
echo ""

if [ "$CPU_USED" -gt "$THRESHOLD" ]; then
    echo "WARNING: CPU utilisation (${CPU_USED}%) exceeds ${THRESHOLD}%"
    STATUS="not healthy"
    if $EXPLAIN; then
        echo ""
        echo "  [CPU Explanation]"
        echo "  The CPU is under heavy load. This can slow down all running applications"
        echo "  and services on the VM. Consider stopping unnecessary processes or"
        echo "  scaling up the VM's vCPU count."
        echo "  Top 5 CPU-consuming processes:"
        ps -eo pid,comm,%cpu --sort=-%cpu | head -6 | tail -5 | awk '{printf "    PID: %-8s Name: %-20s CPU: %s%%\n", $1, $2, $3}'
        echo ""
    fi
fi

if [ "$MEM_PCT" -gt "$THRESHOLD" ]; then
    echo "WARNING: Memory utilisation (${MEM_PCT}%) exceeds ${THRESHOLD}%"
    STATUS="not healthy"
    if $EXPLAIN; then
        MEM_FREE_MB=$(free -m | awk '/^Mem:/{print $4}')
        MEM_CACHED_MB=$(free -m | awk '/^Mem:/{print $6}')
        echo ""
        echo "  [Memory Explanation]"
        echo "  High memory usage can cause the kernel to start swapping, which severely"
        echo "  degrades performance. Free RAM: ${MEM_FREE_MB} MiB, Cached: ${MEM_CACHED_MB} MiB."
        echo "  Consider terminating memory-hungry processes or adding more RAM to the VM."
        echo "  Top 5 memory-consuming processes:"
        ps -eo pid,comm,%mem --sort=-%mem | head -6 | tail -5 | awk '{printf "    PID: %-8s Name: %-20s MEM: %s%%\n", $1, $2, $3}'
        echo ""
    fi
fi

if [ "$DISK_PCT" -gt "$THRESHOLD" ]; then
    echo "WARNING: Disk utilisation (${DISK_PCT}%) exceeds ${THRESHOLD}%"
    STATUS="not healthy"
    if $EXPLAIN; then
        DISK_FREE=$(df -h / | awk 'NR==2{print $4}')
        echo ""
        echo "  [Disk Explanation]"
        echo "  Low disk space can cause application crashes, failed writes, and an"
        echo "  unbootable system if the root filesystem fills completely."
        echo "  Free space on /: ${DISK_FREE}. Consider cleaning up logs, old packages,"
        echo "  or temporary files. Ubuntu-specific tips:"
        echo "    - Run: sudo apt-get autoremove && sudo apt-get clean"
        echo "    - Remove old kernels: sudo dpkg --list | grep linux-image"
        echo "    - Clear systemd journal: sudo journalctl --vacuum-size=100M"
        echo "  Largest directories under / (top 5):"
        du -x --max-depth=2 / 2>/dev/null | sort -rn | head -5 | awk '{printf "    %s\t%s\n", $1, $2}'
        echo ""
    fi
fi

echo ""
if [ "$STATUS" = "healthy" ]; then
    echo "VM health status: $STATUS"
    if $EXPLAIN; then
        echo ""
        echo "  [Health Explanation]"
        echo "  All monitored resources (CPU, memory, disk) are below the ${THRESHOLD}% threshold."
        echo "  The VM is operating within normal parameters and no immediate action is required."
    fi
else
    echo "VM health status: $STATUS"
    if $EXPLAIN; then
        echo ""
        echo "  [Action Recommendation]"
        echo "  One or more resources have exceeded the ${THRESHOLD}% threshold (see warnings above)."
        echo "  Review the affected metrics and take corrective action to prevent service degradation."
    fi
fi
