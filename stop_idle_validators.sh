#!/bin/bash

# 设置内存阈值（GB），默认值为 2GB
MEMORY_LIMIT=${MEMORY_LIMIT:-2}

# 获取所有运行中的容器 ID
CONTAINERS=$(docker ps -q)

# 获取所有容器的内存使用情况一次性
get_all_memory_usage() {
    docker stats --no-stream --format "{{.ID}} {{.MemUsage}}" | while read container_id mem_usage_raw; do
        # 解析内存单位
        if [[ "$mem_usage_raw" =~ ([0-9\.]+)([A-Za-z]+) ]]; then
            local value="${BASH_REMATCH[1]}"
            local unit="${BASH_REMATCH[2]}"

            case "$unit" in
                GiB) echo "$container_id $value" ;;
                MiB) echo "$container_id $(awk "BEGIN {printf \"%.3f\", $value / 1024}")" ;;
                KiB) echo "$container_id $(awk "BEGIN {printf \"%.6f\", $value / 1048576}")" ;;
                B)   echo "$container_id $(awk "BEGIN {printf \"%.9f\", $value / 1073741824}")" ;;
                *)   echo "$container_id 0" ;;  # 未知单位，默认返回 0
            esac
        else
            echo "$container_id 0"
        fi
    done
}

# 检查并停止符合条件的容器
check_and_stop() {
    local container_id="$1"
    local memory_usage="$2"
    local MEMORY_LIMIT="$3"

    echo "Container $container_id memory usage: $memory_usage GB, comparing with threshold $MEMORY_LIMIT GB"

    # 比较内存使用情况
    if (( $(echo "$memory_usage >= $MEMORY_LIMIT" | bc -l) )); then
        echo "Container $container_id memory usage exceeds threshold. Checking logs..."

        # 检查最近 20 行日志
        if docker logs "$container_id" --tail 20 2>&1 | grep -qE "sync to block"; then
            echo "Stopping container $container_id..."
            docker stop "$container_id"
        else
            echo "Container $container_id logs do not match the expected pattern."
        fi
    else
        echo "Container $container_id memory usage: $memory_usage GB, does not meet threshold. Skipping."
    fi
}

# 一次性获取所有容器的内存使用情况并并行检查
get_all_memory_usage | xargs -P10 -I {} bash -c '
check_and_stop() {
    local container_id="$1"
    local memory_usage="$2"
    local MEMORY_LIMIT="$3"

    echo "Container $container_id memory usage: $memory_usage GB, comparing with threshold $MEMORY_LIMIT GB"

    if (( $(echo "$memory_usage >= $MEMORY_LIMIT" | bc -l) )); then
        echo "Container $container_id memory usage exceeds threshold. Checking logs..."

        if docker logs "$container_id" --tail 20 2>&1 | grep -qE "sync to block"; then
            echo "Stopping container $container_id..."
            docker stop "$container_id"
        else
            echo "Container $container_id logs do not match the expected pattern."
        fi
    else
        echo "Container $container_id memory usage: $memory_usage GB, does not meet threshold. Skipping."
    fi
}

container_id=$(echo {} | awk "{print \$1}")
memory_usage=$(echo {} | awk "{print \$2}")
MEMORY_LIMIT="${MEMORY_LIMIT:-2}"

check_and_stop "$container_id" "$memory_usage" "$MEMORY_LIMIT"
'

echo "Script execution completed."
