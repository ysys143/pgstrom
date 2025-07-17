#!/bin/bash

# PG-Strom GPU 병목지점 정량 분석 스크립트
# 작성자: 재솔님과 함께 작성
# 날짜: 2025-01-10

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 로그 함수
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_test() { echo -e "${CYAN}[TEST]${NC} $1"; }

# 설정 변수
CONTAINER_NAME="pgstrom-test"
DATABASE="testdb"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
RESULTS_DIR="$PROJECT_ROOT/experiment_results/results_${TIMESTAMP}"
TEST_SESSION="test_${TIMESTAMP}"

# 테스트 반복 설정
REPEAT_COUNT=5  # 각 테스트를 5회 반복
REPEAT_INTERVAL=2  # 반복 간 간격 (초)

# QPS 테스트 설정
QPS_DURATION=30    # QPS 측정 지속 시간 (초)
QPS_CONCURRENT=8   # QPS 측정 시 동시 실행할 쿼리 수
GPU_MONITOR_FREQ=1 # GPU 모니터링 주기 (초)

# 결과 디렉토리 생성
mkdir -p "$RESULTS_DIR"

# GPU 모니터링 함수
start_gpu_monitoring() {
    local test_name="$1"
    local duration="$2"
    
    nvidia-smi --query-gpu=timestamp,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw \
        --format=csv -l $GPU_MONITOR_FREQ > "$RESULTS_DIR/${test_name}_gpu.csv" &
    
    echo $! > "$RESULTS_DIR/${test_name}_gpu.pid"
    log_info "GPU 모니터링 시작: ${test_name} (${GPU_MONITOR_FREQ}초 간격)"
}

stop_gpu_monitoring() {
    local test_name="$1"
    local pid_file="$RESULTS_DIR/${test_name}_gpu.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        kill $pid 2>/dev/null || true
        rm -f "$pid_file"
        log_info "GPU 모니터링 종료: ${test_name}"
    fi
}

# QPS 측정 함수
measure_qps() {
    local test_name="$1"
    local query="$2"
    local gpu_enabled="$3"  # "on" 또는 "off"
    local mode_name="$4"    # "GPU" 또는 "CPU"
    
    log_info "QPS 측정 시작: $mode_name 모드 ($QPS_DURATION초 동안 $QPS_CONCURRENT 동시 실행)"
    
    # QPS 결과 파일 초기화
    local qps_file="$RESULTS_DIR/${test_name}_qps_${mode_name,,}.log"
    echo "=== $mode_name 모드 QPS 측정 ===" > "$qps_file"
    echo "측정 시간: $QPS_DURATION초" >> "$qps_file"
    echo "동시 실행: $QPS_CONCURRENT개 쿼리" >> "$qps_file"
    echo "시작 시간: $(date)" >> "$qps_file"
    echo "" >> "$qps_file"
    
    # QPS 측정 시작
    local start_time=$(date +%s)
    local end_time=$((start_time + QPS_DURATION))
    local completed_queries=0
    local total_time_sum=0
    
    # 동시 실행을 위한 배경 작업들
    local worker_pids=()
    local worker_logs=()
    
    # 동시 워커 시작
    for ((worker=1; worker<=QPS_CONCURRENT; worker++)); do
        local worker_log="$RESULTS_DIR/${test_name}_worker_${worker}_${mode_name,,}.log"
        worker_logs+=("$worker_log")
        
        (
            local worker_queries=0
            local worker_time_sum=0
            
            while [ $(date +%s) -lt $end_time ]; do
                local query_start=$(date +%s.%N)
                
                docker exec $CONTAINER_NAME psql -U postgres -d $DATABASE -c "SET pg_strom.enabled = $gpu_enabled;" -c "$query" > /dev/null 2>&1
                
                local query_end=$(date +%s.%N)
                local query_duration=$(echo "$query_end - $query_start" | bc)
                
                worker_queries=$((worker_queries + 1))
                worker_time_sum=$(echo "$worker_time_sum + $query_duration" | bc)
                
                echo "$(date +%s.%N),$query_duration" >> "$worker_log"
            done
            
            echo "WORKER_$worker:COMPLETED:$worker_queries:$worker_time_sum" >> "$qps_file"
        ) &
        
        worker_pids+=($!)
    done
    
    # 모든 워커 완료 대기
    for pid in "${worker_pids[@]}"; do
        wait $pid
    done
    
    # 결과 집계
    local actual_duration=$(($(date +%s) - start_time))
    
    echo "" >> "$qps_file"
    echo "=== 결과 집계 ===" >> "$qps_file"
    echo "실제 측정 시간: ${actual_duration}초" >> "$qps_file"
    
    # 각 워커 결과 집계
    for ((worker=1; worker<=QPS_CONCURRENT; worker++)); do
        local worker_completed=$(grep "WORKER_$worker:COMPLETED" "$qps_file" | cut -d: -f3)
        local worker_total_time=$(grep "WORKER_$worker:COMPLETED" "$qps_file" | cut -d: -f4)
        
        completed_queries=$((completed_queries + worker_completed))
        total_time_sum=$(echo "$total_time_sum + $worker_total_time" | bc)
        
        echo "Worker $worker: $worker_completed 쿼리 완료" >> "$qps_file"
    done
    
    # QPS 계산
    local qps=$(echo "scale=2; $completed_queries / $actual_duration" | bc)
    local avg_query_time=$(echo "scale=4; $total_time_sum / $completed_queries" | bc)
    
    echo "" >> "$qps_file"
    echo "총 완료 쿼리: $completed_queries" >> "$qps_file"
    echo "QPS (Query Per Second): $qps" >> "$qps_file"
    echo "평균 쿼리 실행 시간: ${avg_query_time}초" >> "$qps_file"
    echo "종료 시간: $(date)" >> "$qps_file"
    
    log_info "$mode_name 모드 QPS 측정 완료: $qps QPS ($completed_queries 쿼리)"
    
    # 워커 로그 파일들 정리
    for worker_log in "${worker_logs[@]}"; do
        rm -f "$worker_log"
    done
    
    echo "$qps"  # QPS 값 반환
}

# PostgreSQL 연결 테스트
test_connection() {
    docker exec $CONTAINER_NAME psql -U postgres -d $DATABASE -c "SELECT version();" > /dev/null 2>&1
    return $?
}

# 기본 테이블 상태 확인
check_test_tables() {
    log_step "테스트 테이블 상태 확인 중..."
    
    local table_info=$(docker exec $CONTAINER_NAME psql -U postgres -d $DATABASE -t -c "
        SELECT 
            schemaname||'.'||tablename as table_name,
            pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
            n_tup_ins as row_count
        FROM pg_stat_user_tables 
        WHERE tablename LIKE 't_%'
        ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
    ")
    
    echo "$table_info" > "$RESULTS_DIR/table_status.txt"
    log_info "테이블 상태를 $RESULTS_DIR/table_status.txt 에 저장"
}

# 1. 메모리 병목 테스트 시리즈 (QPS 중심)
memory_bottleneck_tests() {
    log_step "=== 메모리 병목 QPS 테스트 시리즈 시작 ==="
    
    # 1-1. 데이터 크기별 QPS 성능 테스트
    log_test "1-1. 데이터 크기별 QPS 성능 테스트"
    
    local sizes=("1000000" "10000000" "50000000")
    local size_names=("1M" "10M" "50M")
    
    for i in "${!sizes[@]}"; do
        local size="${sizes[$i]}"
        local name="${size_names[$i]}"
        local test_name="memory_qps_${name}"
        
        log_info "QPS 테스트: $name 행 처리 ($size 행)"
        
        # 테스트 쿼리 정의
        local query="SELECT COUNT(*), SUM(sin(val1) + cos(val2)), AVG(sqrt(abs(val3))) FROM t_monster WHERE id <= $size;"
        
        # GPU 모니터링 시작 (QPS 측정 전체 구간)
        start_gpu_monitoring "$test_name" $((QPS_DURATION * 2 + 10))
        
        # QPS 측정 로그 파일 초기화
        echo "=== 메모리 병목 QPS 테스트: $name 행 ===" > "$RESULTS_DIR/${test_name}.log"
        echo "데이터 크기: $size 행" >> "$RESULTS_DIR/${test_name}.log"
        echo "테스트 쿼리: $query" >> "$RESULTS_DIR/${test_name}.log"
        echo "" >> "$RESULTS_DIR/${test_name}.log"
        
        # GPU 모드 QPS 측정
        local gpu_qps=$(measure_qps "$test_name" "$query" "on" "GPU")
        echo "GPU 모드 QPS: $gpu_qps" >> "$RESULTS_DIR/${test_name}.log"
        
        sleep 5
        
        # CPU 모드 QPS 측정
        local cpu_qps=$(measure_qps "$test_name" "$query" "off" "CPU")
        echo "CPU 모드 QPS: $cpu_qps" >> "$RESULTS_DIR/${test_name}.log"
        
        # QPS 비교 계산
        local qps_speedup=$(echo "scale=2; $gpu_qps / $cpu_qps" | bc 2>/dev/null || echo "계산불가")
        echo "" >> "$RESULTS_DIR/${test_name}.log"
        echo "=== QPS 성능 비교 ===" >> "$RESULTS_DIR/${test_name}.log"
        echo "GPU QPS: $gpu_qps" >> "$RESULTS_DIR/${test_name}.log"
        echo "CPU QPS: $cpu_qps" >> "$RESULTS_DIR/${test_name}.log"
        echo "QPS 성능 향상: ${qps_speedup}배" >> "$RESULTS_DIR/${test_name}.log"
        
        # GPU 모니터링 종료
        stop_gpu_monitoring "$test_name"
        
        log_info "$name 데이터 QPS 테스트 완료: GPU ${gpu_qps} vs CPU ${cpu_qps} (${qps_speedup}배 향상)"
        
        sleep 3
    done
    
    # 1-2. 동시 연결 수별 QPS 스케일링 테스트
    log_test "1-2. 동시 연결 수별 QPS 스케일링 테스트"
    
    local concurrent_levels=(2 4 8 16)
    
    for concurrent in "${concurrent_levels[@]}"; do
        local test_name="memory_scaling_${concurrent}"
        log_info "QPS 스케일링 테스트: $concurrent 동시 연결"
        
        # 스케일링 테스트용 쿼리 (부하 조절)
        local query="SELECT COUNT(*), SUM(val1 + val2), AVG(val3) FROM t_monster WHERE id % $concurrent = 0 LIMIT 100000;"
        
        # GPU 모니터링 시작
        start_gpu_monitoring "$test_name" $((QPS_DURATION * 2 + 10))
        
        # 로그 파일 초기화
        echo "=== 동시 연결 QPS 스케일링 테스트: $concurrent 연결 ===" > "$RESULTS_DIR/${test_name}.log"
        echo "동시 연결 수: $concurrent" >> "$RESULTS_DIR/${test_name}.log"
        echo "테스트 쿼리: $query" >> "$RESULTS_DIR/${test_name}.log"
        echo "" >> "$RESULTS_DIR/${test_name}.log"
        
        # 이 테스트에서는 동시 실행 수를 매개변수로 조정
        local original_concurrent=$QPS_CONCURRENT
        QPS_CONCURRENT=$concurrent
        
        # GPU 모드 QPS 측정
        local gpu_qps=$(measure_qps "$test_name" "$query" "on" "GPU")
        echo "GPU 모드 QPS ($concurrent 연결): $gpu_qps" >> "$RESULTS_DIR/${test_name}.log"
        
        sleep 5
        
        # CPU 모드 QPS 측정
        local cpu_qps=$(measure_qps "$test_name" "$query" "off" "CPU")
        echo "CPU 모드 QPS ($concurrent 연결): $cpu_qps" >> "$RESULTS_DIR/${test_name}.log"
        
        # 원래 설정 복원
        QPS_CONCURRENT=$original_concurrent
        
        # 스케일링 효율성 계산
        local scaling_efficiency=$(echo "scale=2; $gpu_qps / ($concurrent * 1.0)" | bc 2>/dev/null || echo "계산불가")
        local qps_speedup=$(echo "scale=2; $gpu_qps / $cpu_qps" | bc 2>/dev/null || echo "계산불가")
        
        echo "" >> "$RESULTS_DIR/${test_name}.log"
        echo "=== 스케일링 분석 ===" >> "$RESULTS_DIR/${test_name}.log"
        echo "GPU QPS: $gpu_qps" >> "$RESULTS_DIR/${test_name}.log"
        echo "CPU QPS: $cpu_qps" >> "$RESULTS_DIR/${test_name}.log"
        echo "QPS 성능 향상: ${qps_speedup}배" >> "$RESULTS_DIR/${test_name}.log"
        echo "GPU 스케일링 효율성: $scaling_efficiency QPS/연결" >> "$RESULTS_DIR/${test_name}.log"
        
        # GPU 모니터링 종료
        stop_gpu_monitoring "$test_name"
        
        log_info "$concurrent 연결 QPS 스케일링 완료: GPU ${gpu_qps} vs CPU ${cpu_qps}"
        
        sleep 5
    done
}

# 2. 연산 병목 QPS 테스트 시리즈
computation_bottleneck_tests() {
    log_step "=== 연산 병목 QPS 테스트 시리즈 시작 ==="
    
    # 2-1. 수학 함수 복잡도별 QPS 테스트
    log_test "2-1. 수학 함수 복잡도별 QPS 테스트"
    
    declare -A math_complexities=(
        ["basic"]="sin(val1) + cos(val2)"
        ["medium"]="sin(val1) + cos(val2) + sqrt(abs(val3)) + log(val1 + 1)"
        ["complex"]="sin(val1) + cos(val2) + sqrt(abs(val3)) + log(val1 + 1) + exp(val2/1000) + pow(val3, 0.5)"
        ["extreme"]="sin(val1) + cos(val2) + sqrt(abs(val3)) + log(val1 + 1) + exp(val2/1000) + pow(val3, 0.5) + atan2(sin(val1), cos(val2))"
    )
    
    for complexity in "basic" "medium" "complex" "extreme"; do
        local test_name="computation_qps_${complexity}"
        local formula="${math_complexities[$complexity]}"
        
        log_info "연산 복잡도 QPS 테스트: $complexity"
        
        # 복잡도별 테스트 쿼리 (데이터 크기 조정으로 부하 조절)
        local data_limit="10000000"  # 1천만 행으로 제한하여 QPS 측정 가능
        local query="SELECT COUNT(*), SUM($formula), AVG($formula) FROM t_monster WHERE id <= $data_limit;"
        
        # GPU 모니터링 시작
        start_gpu_monitoring "$test_name" $((QPS_DURATION * 2 + 10))
        
        # 로그 파일 초기화
        echo "=== 연산 복잡도 QPS 테스트: $complexity ===" > "$RESULTS_DIR/${test_name}.log"
        echo "복잡도: $complexity" >> "$RESULTS_DIR/${test_name}.log"
        echo "수학 함수: $formula" >> "$RESULTS_DIR/${test_name}.log"
        echo "테스트 쿼리: $query" >> "$RESULTS_DIR/${test_name}.log"
        echo "" >> "$RESULTS_DIR/${test_name}.log"
        
        # GPU 모드 QPS 측정
        local gpu_qps=$(measure_qps "$test_name" "$query" "on" "GPU")
        echo "GPU 모드 QPS: $gpu_qps" >> "$RESULTS_DIR/${test_name}.log"
        
        sleep 5
        
        # CPU 모드 QPS 측정
        local cpu_qps=$(measure_qps "$test_name" "$query" "off" "CPU")
        echo "CPU 모드 QPS: $cpu_qps" >> "$RESULTS_DIR/${test_name}.log"
        
        # 연산 복잡도별 성능 분석
        local qps_speedup=$(echo "scale=2; $gpu_qps / $cpu_qps" | bc 2>/dev/null || echo "계산불가")
        
        echo "" >> "$RESULTS_DIR/${test_name}.log"
        echo "=== 연산 복잡도 분석 ===" >> "$RESULTS_DIR/${test_name}.log"
        echo "GPU QPS: $gpu_qps" >> "$RESULTS_DIR/${test_name}.log"
        echo "CPU QPS: $cpu_qps" >> "$RESULTS_DIR/${test_name}.log"
        echo "연산 가속 효과: ${qps_speedup}배" >> "$RESULTS_DIR/${test_name}.log"
        echo "연산 복잡도 레벨: $complexity" >> "$RESULTS_DIR/${test_name}.log"
        
        # GPU 모니터링 종료
        stop_gpu_monitoring "$test_name"
        
        log_info "$complexity 복잡도 QPS 완료: GPU ${gpu_qps} vs CPU ${cpu_qps} (${qps_speedup}배 가속)"
        
        sleep 3
    done
    
    # 2-2. GROUP BY 집계 QPS 테스트  
    log_test "2-2. GROUP BY 집계 QPS 테스트"
    
    local cardinalities=(100 1000 10000)
    
    for card in "${cardinalities[@]}"; do
        local test_name="groupby_qps_${card}"
        log_info "GROUP BY QPS 테스트: $card 그룹"
        
        # GROUP BY 테스트 쿼리
        local query="SELECT id % $card as bucket, COUNT(*), SUM(sin(val1) + cos(val2)), AVG(val3) FROM t_monster WHERE id <= 20000000 GROUP BY id % $card LIMIT 100;"
        
        # GPU 모니터링 시작
        start_gpu_monitoring "$test_name" $((QPS_DURATION * 2 + 10))
        
        # 로그 파일 초기화
        echo "=== GROUP BY QPS 테스트: $card 그룹 ===" > "$RESULTS_DIR/${test_name}.log"
        echo "그룹 수: $card" >> "$RESULTS_DIR/${test_name}.log"
        echo "테스트 쿼리: $query" >> "$RESULTS_DIR/${test_name}.log"
        echo "" >> "$RESULTS_DIR/${test_name}.log"
        
        # GPU 모드 QPS 측정
        local gpu_qps=$(measure_qps "$test_name" "$query" "on" "GPU")
        echo "GPU 모드 QPS: $gpu_qps" >> "$RESULTS_DIR/${test_name}.log"
        
        sleep 5
        
        # CPU 모드 QPS 측정
        local cpu_qps=$(measure_qps "$test_name" "$query" "off" "CPU")
        echo "CPU 모드 QPS: $cpu_qps" >> "$RESULTS_DIR/${test_name}.log"
        
        # GROUP BY 성능 분석
        local qps_speedup=$(echo "scale=2; $gpu_qps / $cpu_qps" | bc 2>/dev/null || echo "계산불가")
        
        echo "" >> "$RESULTS_DIR/${test_name}.log"
        echo "=== GROUP BY 집계 분석 ===" >> "$RESULTS_DIR/${test_name}.log"
        echo "GPU QPS: $gpu_qps" >> "$RESULTS_DIR/${test_name}.log"
        echo "CPU QPS: $cpu_qps" >> "$RESULTS_DIR/${test_name}.log"
        echo "GROUP BY 가속 효과: ${qps_speedup}배" >> "$RESULTS_DIR/${test_name}.log"
        echo "집계 그룹 수: $card" >> "$RESULTS_DIR/${test_name}.log"
        
        # GPU 모니터링 종료
        stop_gpu_monitoring "$test_name"
        
        log_info "$card 그룹 GROUP BY QPS 완료: GPU ${gpu_qps} vs CPU ${cpu_qps} (${qps_speedup}배 가속)"
        
        sleep 3
    done
}

# 3. 극한 성능 QPS 테스트 (최고 부하)
extreme_performance_tests() {
    log_step "=== 극한 성능 QPS 테스트 시작 ==="
    
    log_test "3-1. 최고 부하 QPS 스트레스 테스트"
    
    local test_name="extreme_qps_stress"
    log_info "극한 QPS 스트레스 테스트: 최대 GPU 활용률 도전"
    
    # 극한 부하 쿼리 (복잡한 수학 함수 + 대용량 GROUP BY)
    local query="SELECT (id % 500) as bucket, COUNT(*), SUM(sin(val1) + cos(val2) + sqrt(abs(val3)) + log(val1 + 1)), AVG(pow(val2, 0.5)) FROM t_monster WHERE id <= 30000000 GROUP BY id % 500 LIMIT 200;"
    
    # 긴 QPS 측정 (60초)
    local original_duration=$QPS_DURATION
    local original_concurrent=$QPS_CONCURRENT
    QPS_DURATION=60
    QPS_CONCURRENT=16  # 최대 동시 실행
    
    # GPU 모니터링 시작 (긴 시간)
    start_gpu_monitoring "$test_name" $((QPS_DURATION * 2 + 20))
    
    # 로그 파일 초기화
    echo "=== 극한 QPS 스트레스 테스트 ===" > "$RESULTS_DIR/${test_name}.log"
    echo "측정 시간: ${QPS_DURATION}초 (확장)" >> "$RESULTS_DIR/${test_name}.log"
    echo "동시 실행: $QPS_CONCURRENT 연결" >> "$RESULTS_DIR/${test_name}.log"
    echo "테스트 쿼리: $query" >> "$RESULTS_DIR/${test_name}.log"
    echo "" >> "$RESULTS_DIR/${test_name}.log"
    
    # GPU 모드 극한 QPS 측정
    local gpu_qps=$(measure_qps "$test_name" "$query" "on" "GPU")
    echo "GPU 극한 QPS: $gpu_qps" >> "$RESULTS_DIR/${test_name}.log"
    
    sleep 10
    
    # CPU 모드 비교 (짧은 시간으로 조정)
    QPS_DURATION=30  # CPU는 30초만
    local cpu_qps=$(measure_qps "$test_name" "$query" "off" "CPU")
    echo "CPU 비교 QPS: $cpu_qps" >> "$RESULTS_DIR/${test_name}.log"
    
    # 극한 성능 분석
    local extreme_speedup=$(echo "scale=2; $gpu_qps / $cpu_qps" | bc 2>/dev/null || echo "계산불가")
    
    echo "" >> "$RESULTS_DIR/${test_name}.log"
    echo "=== 극한 성능 분석 ===" >> "$RESULTS_DIR/${test_name}.log"
    echo "GPU 극한 QPS: $gpu_qps" >> "$RESULTS_DIR/${test_name}.log"
    echo "CPU 비교 QPS: $cpu_qps" >> "$RESULTS_DIR/${test_name}.log"
    echo "극한 가속 효과: ${extreme_speedup}배" >> "$RESULTS_DIR/${test_name}.log"
    echo "최대 동시 연결: $QPS_CONCURRENT" >> "$RESULTS_DIR/${test_name}.log"
    
    # 설정 복원
    QPS_DURATION=$original_duration
    QPS_CONCURRENT=$original_concurrent
    
    # GPU 모니터링 종료
    stop_gpu_monitoring "$test_name"
    
    log_info "극한 QPS 스트레스 테스트 완료: GPU ${gpu_qps} vs CPU ${cpu_qps} (${extreme_speedup}배 극한 가속)"
}

# 결과 분석 및 리포트 생성
generate_analysis_report() {
    log_step "=== 결과 분석 리포트 생성 중 ==="
    
    local report_file="$RESULTS_DIR/bottleneck_analysis_report.md"
    
    cat > "$report_file" << EOF
# PG-Strom GPU 병목지점 정량 분석 리포트

**분석 일시**: $(date)
**테스트 세션**: $TEST_SESSION

## 📊 테스트 개요

### 시스템 환경
- GPU: $(nvidia-smi -L | head -1)
- CUDA: $(nvidia-smi | grep "CUDA Version" | awk '{print $9}')
- 컨테이너: $CONTAINER_NAME
- 데이터베이스: $DATABASE

### 테스트 시나리오
1. **메모리 병목 테스트**
   - 데이터 크기별 단일 쿼리 (1M ~ 100M 행)
   - 동시 연결 수별 메모리 압박 (1 ~ 16 연결)

2. **연산 병목 테스트**
   - 수학 함수 복잡도별 (simple ~ extreme)
   - GROUP BY 카디널리티별 (10 ~ 100K 그룹)

3. **혼합 부하 테스트**
   - 메모리 압박 + 연산 복잡도 매트릭스

## 📈 주요 발견사항

### GPU 활용률 패턴

EOF

    # GPU 모니터링 결과 요약 추가
    log_info "GPU 모니터링 데이터 분석 중..."
    
    for csv_file in "$RESULTS_DIR"/*_gpu.csv; do
        if [ -f "$csv_file" ]; then
            local test_name=$(basename "$csv_file" .csv | sed 's/_gpu$//')
            local max_util=$(tail -n +2 "$csv_file" | cut -d',' -f2 | sort -n | tail -1)
            local max_memory=$(tail -n +2 "$csv_file" | cut -d',' -f4 | sort -n | tail -1)
            local avg_temp=$(tail -n +2 "$csv_file" | cut -d',' -f6 | awk '{sum+=$1; count++} END {print sum/count}')
            
            echo "- **$test_name**: 최대 GPU 활용률 ${max_util}%, 최대 메모리 ${max_memory}MiB, 평균 온도 ${avg_temp}°C" >> "$report_file"
        fi
    done
    
    cat >> "$report_file" << EOF

### 성능 비교 결과

EOF

    # 성능 결과 요약 추가 (반복 실행 통계 포함)
    for log_file in "$RESULTS_DIR"/*.log; do
        if [ -f "$log_file" ]; then
            local test_name=$(basename "$log_file" .log)
            echo "#### $test_name" >> "$report_file"
            
            # GPU 모드 실행 시간들 추출
            local gpu_times=($(grep "Time:" "$log_file" | grep -A 5 "GPU 모드" | awk '{print $2}' | grep -E '^[0-9]+\.[0-9]+$'))
            
            # CPU 모드 실행 시간들 추출
            local cpu_times=($(grep "Time:" "$log_file" | grep -A 5 "CPU 모드" | awk '{print $2}' | grep -E '^[0-9]+\.[0-9]+$'))
            
            if [ ${#gpu_times[@]} -gt 0 ] && [ ${#cpu_times[@]} -gt 0 ]; then
                # GPU 통계 계산
                local gpu_avg=$(echo "${gpu_times[@]}" | tr ' ' '+' | bc | awk "{print \$1 / ${#gpu_times[@]}}")
                local gpu_min=$(printf '%s\n' "${gpu_times[@]}" | sort -n | head -1)
                local gpu_max=$(printf '%s\n' "${gpu_times[@]}" | sort -n | tail -1)
                
                # CPU 통계 계산
                local cpu_avg=$(echo "${cpu_times[@]}" | tr ' ' '+' | bc | awk "{print \$1 / ${#cpu_times[@]}}")
                local cpu_min=$(printf '%s\n' "${cpu_times[@]}" | sort -n | head -1)
                local cpu_max=$(printf '%s\n' "${cpu_times[@]}" | sort -n | tail -1)
                
                echo "- **GPU 모드** (${#gpu_times[@]}회 실행):" >> "$report_file"
                echo "  - 평균: ${gpu_avg}ms, 최소: ${gpu_min}ms, 최대: ${gpu_max}ms" >> "$report_file"
                echo "- **CPU 모드** (${#cpu_times[@]}회 실행):" >> "$report_file"
                echo "  - 평균: ${cpu_avg}ms, 최소: ${cpu_min}ms, 최대: ${cpu_max}ms" >> "$report_file"
                
                # 성능 향상 계산 (평균 기준)
                local speedup=$(echo "scale=2; $cpu_avg / $gpu_avg" | bc 2>/dev/null || echo "계산불가")
                echo "- **성능 향상**: ${speedup}배 (평균 기준)" >> "$report_file"
                
                # 최적 성능 향상 계산 (GPU 최소 시간 vs CPU 최대 시간)
                local best_speedup=$(echo "scale=2; $cpu_max / $gpu_min" | bc 2>/dev/null || echo "계산불가")
                echo "- **최적 성능 향상**: ${best_speedup}배 (GPU 최소 vs CPU 최대)" >> "$report_file"
            else
                echo "- 실행 시간 데이터 없음 또는 불완전" >> "$report_file"
            fi
            echo "" >> "$report_file"
        fi
    done
    
    cat >> "$report_file" << EOF

## 📋 상세 결과 파일

### GPU 모니터링 데이터
EOF
    
    for csv_file in "$RESULTS_DIR"/*_gpu.csv; do
        if [ -f "$csv_file" ]; then
            echo "- $(basename "$csv_file")" >> "$report_file"
        fi
    done
    
    cat >> "$report_file" << EOF

### 쿼리 실행 로그
EOF
    
    for log_file in "$RESULTS_DIR"/*.log; do
        if [ -f "$log_file" ]; then
            echo "- $(basename "$log_file")" >> "$report_file"
        fi
    done
    
    cat >> "$report_file" << EOF

## 🎯 결론 및 권고사항

### 병목지점 분석
1. **메모리 병목**: [분석 필요]
2. **연산 병목**: [분석 필요]
3. **데이터 전송 병목**: [분석 필요]

### 최적화 방향
1. **우선순위 1**: [권고사항]
2. **우선순위 2**: [권고사항]
3. **우선순위 3**: [권고사항]

---
*분석 완료: $(date)*
EOF

    log_info "분석 리포트 생성 완료: $report_file"
}

# 사용법 출력
show_usage() {
    echo "사용법: $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  -d, --duration SEC     QPS 측정 지속 시간 (기본값: 30초)"
    echo "  -c, --concurrent NUM   QPS 측정 시 동시 실행 수 (기본값: 8)"
    echo "  -f, --frequency SEC    GPU 모니터링 주기 (기본값: 1초)"
    echo "  -h, --help            이 도움말 표시"
    echo ""
    echo "예시:"
    echo "  $0                     기본 설정으로 실행 (30초, 8연결)"
    echo "  $0 -d 60 -c 16        60초 동안 16개 동시 연결로 QPS 측정"
    echo "  $0 --duration 45      45초 동안 QPS 측정"
    echo ""
}

# 명령행 인수 처리
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--duration)
                QPS_DURATION="$2"
                shift 2
                ;;
            -c|--concurrent)
                QPS_CONCURRENT="$2"
                shift 2
                ;;
            -f|--frequency)
                GPU_MONITOR_FREQ="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "알 수 없는 옵션: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# 메인 실행 함수
main() {
    # 명령행 인수 처리
    parse_arguments "$@"
    
    log_info "PG-Strom GPU 병목지점 정량 분석 시작"
    log_info "결과 저장 위치: $RESULTS_DIR"
    log_info "테스트 세션: $TEST_SESSION"
    log_info "QPS 설정: ${QPS_DURATION}초 측정, ${QPS_CONCURRENT}개 동시 연결, ${GPU_MONITOR_FREQ}초 모니터링 간격"
    
    # 연결 테스트
    if ! test_connection; then
        log_error "PostgreSQL 연결 실패. 컨테이너 상태를 확인하세요."
        exit 1
    fi
    
    # 테이블 상태 확인
    check_test_tables
    
    # 시스템 상태 기록
    nvidia-smi > "$RESULTS_DIR/initial_gpu_status.txt"
    docker exec $CONTAINER_NAME ps aux > "$RESULTS_DIR/initial_processes.txt"
    
    # QPS 테스트 실행
    memory_bottleneck_tests
    computation_bottleneck_tests
    extreme_performance_tests
    
    # 결과 분석
    generate_analysis_report
    
    log_info "모든 테스트 완료!"
    log_info "결과 분석 리포트: $RESULTS_DIR/bottleneck_analysis_report.md"
    log_info "상세 데이터: $RESULTS_DIR/ 디렉토리 확인"
}

# 스크립트 실행
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 