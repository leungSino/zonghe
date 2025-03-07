#!/bin/bash

# 设置内存阈值（GB），默认值为 2GB
MEMORY_LIMIT=${MEMORY_LIMIT:-2}

# 获取所有运行中的容器 ID，并获取内存使用情况
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

# 并行执行检测和停止（只有满足条件的才停止）
get_all_memory_usage | while read container_id memory_usage; do
    # 确保 memory_usage 是数值
    if [[ ! "$memory_usage" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        memory_usage=0
    fi

    echo "Container: $container_id | Memory: $memory_usage GB | Threshold: $MEMORY_LIMIT GB"

    # 只有当内存使用超过 MEMORY_LIMIT 才进行日志检查
    if (( $(echo "$memory_usage > $MEMORY_LIMIT" | bc -l) )); then
        logs=$(docker logs "$container_id" --tail 20 2>&1)
        sync_count=$(echo "$logs" | grep -c "sync to block")

        echo "Sync to block count for container $container_id: $sync_count"

        # 确保 sync_count 为数值
        if [[ ! "$sync_count" =~ ^[0-9]+$ ]]; then
            sync_count=0
        fi

        # 只有当 sync_count >= 15 时才停止容器
        if (( sync_count >= 15 )); then
            echo "Stopping container $container_id (sync to block count: $sync_count)..."
            docker stop "$container_id"
        else
            echo "Container $container_id has sync count $sync_count, not stopping."
        fi
    else
        echo "Container $container_id memory usage ($memory_usage GB) does not exceed the threshold. Skipping."
    fi
done

echo "Script execution completed."
