#!/bin/bash

THRESHOLD=60
STATUS="healthy"

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
fi

if [ "$MEM_PCT" -gt "$THRESHOLD" ]; then
    echo "WARNING: Memory utilisation (${MEM_PCT}%) exceeds ${THRESHOLD}%"
    STATUS="not healthy"
fi

if [ "$DISK_PCT" -gt "$THRESHOLD" ]; then
    echo "WARNING: Disk utilisation (${DISK_PCT}%) exceeds ${THRESHOLD}%"
    STATUS="not healthy"
fi

echo ""
echo "VM health status: $STATUS"
