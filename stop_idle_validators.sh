#!/bin/bash

TIME_RANGE="10m"  # 只检查最近 10 分钟的日志
MEMORY_LIMIT=2048  # 内存阈值（MB）
PARALLEL_JOBS=10  # 并行任务数，避免 CPU 过载

# 获取所有运行中的 `leungsino/cysic-verifier:latest` 容器
CONTAINERS=$(docker ps -q --filter "ancestor=leungsino/cysic-verifier:latest")

check_and_stop() {
    CONTAINER=$1

    # 检查最近 10 分钟的日志是否只有 "sync to block"
    if docker logs "$CONTAINER" --since "$TIME_RANGE" 2>&1 | grep -qE "sync to block" && \
       ! docker logs "$CONTAINER" --since "$TIME_RANGE" 2>&1 | grep -vqE "sync to block"; then

        # 获取容器的内存占用（单位：MB）
        MEMORY_USAGE=$(docker stats --no-stream --format "{{.MemUsage}}" "$CONTAINER" | awk '{print $1}' | sed 's/[^0-9.]//g')

        # 判断内存是否超过阈值
        if [ "$(echo "$MEMORY_USAGE > $MEMORY_LIMIT" | bc)" -eq 1 ]; then
            echo "Stopping container $CONTAINER (only syncing & memory > ${MEMORY_LIMIT}MB)"
            docker stop "$CONTAINER"
        fi
    fi
}

export -f check_and_stop  # 让 `xargs` 识别这个函数

# 并行处理所有容器
echo "$CONTAINERS" | xargs -P "$PARALLEL_JOBS" -I {} bash -c 'check_and_stop "$@"' _ {}
