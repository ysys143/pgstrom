#!/bin/bash

# PG-Strom 성능 실험 실행 스크립트
# 재솔님과 함께 작성

set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 설정 변수
CONTAINER_NAME="pgstrom-test"

# 환경변수 설정
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$PROJECT_ROOT/automation/script"
EXPERIMENT_DIR="$PROJECT_ROOT/experiment_results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULT_DIR="$EXPERIMENT_DIR/results_$TIMESTAMP"

# 실험 설정 환경변수 (기본값 설정)
REPEAT_COUNT=${REPEAT_COUNT:-8}  # 기본 8회 반복
SLEEP_BETWEEN_RUNS=${SLEEP_BETWEEN_RUNS:-1}  # 실행 간 대기 시간 (초)
CLEAR_CACHE=${CLEAR_CACHE:-true}  # 캐시 클리어 여부 (기본: true)
DETAILED_REPORT=${DETAILED_REPORT:-true}  # 상세 Python 보고서 생성 여부 (기본: true)

# 결과 디렉토리 생성
mkdir -p "$RESULT_DIR"

# 캐시 클리어 함수
clear_cache() {
    if [ "$CLEAR_CACHE" = "true" ]; then
        log_info "    캐시 클리어 중..."
        
        # PostgreSQL 캐시 클리어
        docker container exec $CONTAINER_NAME su - postgres -c "
            psql -c \"SELECT pg_stat_reset();\"
            psql -c \"DISCARD ALL;\"
            psql -c \"RESET ALL;\"
            psql -c \"DEALLOCATE ALL;\"
        " > /dev/null 2>&1
        
        # OS 페이지 캐시 클리어 (컨테이너 내부에서)
        docker container exec $CONTAINER_NAME bash -c "
            sync
            echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
        " > /dev/null 2>&1
        
        # 캐시 클리어 후 안정화 대기
        sleep 1
    fi
}

# 테스트 실행 함수 (환경변수 기반 반복)
run_test() {
    local test_name="$1"
    local database="$2"
    local sql_query="$3"
    local gpu_enabled="$4"
    
    log_step "테스트 실행: $test_name (GPU: $gpu_enabled) - ${REPEAT_COUNT}회 반복"
    
    local result_file="$RESULT_DIR/${test_name}_${gpu_enabled}.txt"
    local times_file="$RESULT_DIR/${test_name}_${gpu_enabled}_times.txt"
    
    # GPU 설정
    local gpu_setting="SET pg_strom.enabled = $gpu_enabled;"
    
    # 결과 초기화
    > "$times_file"
    
    # 환경변수 기반 반복 실행
    for i in $(seq 1 $REPEAT_COUNT); do
        log_info "  실행 $i/$REPEAT_COUNT..."
        
        # 캐시 클리어 (매 실행 전)
        clear_cache
        
        # 실행 시간 측정
        local start_time=$(date +%s.%N)
        
        docker container exec $CONTAINER_NAME su - postgres -c "
            psql $database -c \"$gpu_setting EXPLAIN (ANALYZE, VERBOSE, BUFFERS) $sql_query\"
        " > "${result_file}_run${i}.txt" 2>&1
        
        local end_time=$(date +%s.%N)
        local execution_time=$(echo "$end_time - $start_time" | bc)
        
        echo "실행 시간: ${execution_time}초" >> "${result_file}_run${i}.txt"
        
        # 결과에서 실행 시간 추출
        local actual_time=$(grep "Execution Time:" "${result_file}_run${i}.txt" | awk '{print $3}' | sed 's/ms//')
        
        if [ ! -z "$actual_time" ]; then
            echo "$actual_time" >> "$times_file"
            echo "$test_name,$gpu_enabled,$actual_time,run$i" >> "$RESULT_DIR/summary.csv"
        else
            log_error "$test_name (GPU: $gpu_enabled) 실행 $i 시간 추출 실패"
        fi
        
        # 실행 간 대기 (캐시 효과 최소화)
        sleep $SLEEP_BETWEEN_RUNS
    done
    
    # 통계 계산
    if [ -f "$times_file" ] && [ -s "$times_file" ]; then
        local avg_time=$(awk '{sum+=$1; count++} END {print sum/count}' "$times_file")
        local min_time=$(sort -n "$times_file" | head -1)
        local max_time=$(sort -n "$times_file" | tail -1)
        
        # 대표 결과 파일 생성 (첫 번째 실행 결과 사용)
        cp "${result_file}_run1.txt" "$result_file"
        
        # 통계 계산 (분산 포함)
        local std_dev=$(awk -v avg="$avg_time" '{sum+=($1-avg)^2; count++} END {print sqrt(sum/count)}' "$times_file")
        local variance=$(awk -v avg="$avg_time" '{sum+=($1-avg)^2; count++} END {print sum/count}' "$times_file")
        
        # 통계 정보 추가
        {
            echo ""
            echo "=== ${REPEAT_COUNT}회 반복 실행 통계 ==="
            echo "평균 실행 시간: ${avg_time}ms"
            echo "최소 실행 시간: ${min_time}ms"
            echo "최대 실행 시간: ${max_time}ms"
            echo "표준편차: ${std_dev}ms"
            echo "분산: ${variance}ms²"
            echo "변동계수 (CV): $(awk -v std="$std_dev" -v avg="$avg_time" 'BEGIN {printf "%.2f%%", (std/avg)*100}')ms"
            echo "개별 실행 시간:"
            cat "$times_file"
        } >> "$result_file"
        
        log_info "$test_name (GPU: $gpu_enabled) 완료: 평균 ${avg_time}ms (최소: ${min_time}ms, 최대: ${max_time}ms)"
    else
        log_error "$test_name (GPU: $gpu_enabled) 모든 실행 실패"
    fi
}

# 1. 단순 스캔 테스트 (GPU 친화적 쿼리)
test_simple_scan() {
    log_step "=== 1. 단순 스캔 테스트 ==="
    
    local sql="SELECT sum(id), avg(ten), count(*) FROM t_test WHERE ten > 50;"
    
    run_test "simple_scan" "testdb" "$sql" "on"
    sleep 2
    run_test "simple_scan" "testdb" "$sql" "off"
    sleep 2
}

# 2. 조인 테스트 (부분집합)
test_subset_join() {
    log_step "=== 2. 조인 테스트 (부분집합) ==="
    
    local sql="SELECT count(*), avg(a.ten + b.ten) FROM t_test a JOIN t_join b ON a.id = b.id;"
    
    run_test "subset_join" "testdb" "$sql" "on"
    sleep 2
    run_test "subset_join" "testdb" "$sql" "off"
    sleep 2
}

# 3. 대용량 독립 조인 테스트
test_large_join() {
    log_step "=== 3. 대용량 독립 조인 테스트 ==="
    
    local sql="SELECT count(*), avg(a.val + b.val) FROM t_large1 a JOIN t_large2 b ON a.id = b.id;"
    
    run_test "large_join" "testdb2" "$sql" "on"
    sleep 2
    run_test "large_join" "testdb2" "$sql" "off"
    sleep 2
}

# 4. 수학 함수 테스트 (단순)
test_simple_math() {
    log_step "=== 4. 수학 함수 테스트 (단순) ==="
    
    local sql="SELECT count(*), sum(pow(val, 2)), avg(sin(val)) FROM t_huge WHERE val > 0;"
    
    run_test "simple_math" "testdb2" "$sql" "on"
    sleep 2
    run_test "simple_math" "testdb2" "$sql" "off"
    sleep 2
}

# 5. 수학 함수 테스트 (복합)
test_complex_math() {
    log_step "=== 5. 수학 함수 테스트 (복합) ==="
    
    local sql="SELECT count(*), sum(sqrt(abs(val)) + log(val + 2)), avg(atan2(val, id % 100)) FROM t_huge WHERE val > 0;"
    
    run_test "complex_math" "testdb2" "$sql" "on"
    sleep 2
    run_test "complex_math" "testdb2" "$sql" "off"
    sleep 2
}

# 6. 단순 연산 테스트 (GPU 친화적)
test_simple_ops() {
    log_step "=== 6. 단순 연산 테스트 ==="
    
    local sql="SELECT count(*), sum(val * val), avg(val + val) FROM t_huge WHERE val > 0;"
    
    run_test "simple_ops" "testdb2" "$sql" "on"
    sleep 2
    run_test "simple_ops" "testdb2" "$sql" "off"
    sleep 2
}

# 시스템 정보 수집
collect_system_info() {
    log_step "시스템 정보 수집 중..."
    
    {
        echo "=== 실험 실행 정보 ==="
        echo "날짜: $(date)"
        echo "실헑 ID: $TIMESTAMP"
        echo "CUDA 버전: $(nvidia-smi | grep "CUDA Version" | awk '{print $9}')"
        echo "GPU 개수: $(nvidia-smi -L | wc -l)"
        echo ""
        
        echo "=== GPU 정보 ==="
        nvidia-smi -L
        echo ""
        docker container exec $CONTAINER_NAME nvidia-smi
        echo ""
        
        echo "=== PG-Strom 정보 ==="
        docker container exec $CONTAINER_NAME su - postgres -c "
            psql testdb -c \"SELECT name, setting FROM pg_settings WHERE name LIKE 'pg_strom%';\"
        "
        echo ""
        
        echo "=== PostgreSQL 설정 ==="
        docker container exec $CONTAINER_NAME su - postgres -c "
            psql testdb -c \"SHOW shared_preload_libraries;\"
            psql testdb -c \"SHOW max_worker_processes;\"
            psql testdb -c \"SHOW shared_buffers;\"
            psql testdb -c \"SHOW work_mem;\"
        "
        
    } > "$RESULT_DIR/system_info.txt"
    
    log_info "시스템 정보 수집 완료"
}

# 결과 분석
analyze_results() {
    log_step "결과 분석 중..."
    
    if [ ! -f "$RESULT_DIR/summary.csv" ]; then
        log_error "결과 파일이 없습니다."
        return 1
    fi
    
    # CSV 헤더 추가 (중복 방지)
    if [ ! -f "$RESULT_DIR/summary.csv" ] || [ ! -s "$RESULT_DIR/summary.csv" ]; then
        echo "test_name,gpu_enabled,execution_time_ms,run_number" > "$RESULT_DIR/summary.csv"
    else
        # 기존 파일이 있으면 헤더가 있는지 확인
        if ! head -1 "$RESULT_DIR/summary.csv" | grep -q "test_name"; then
            sed -i '1i test_name,gpu_enabled,execution_time_ms,run_number' "$RESULT_DIR/summary.csv"
        fi
    fi
    
    # Shell 기본 분석 우선 실행
    log_info "Shell 기본 분석 실행 중..."
    if [ -x "$SCRIPT_DIR/analyze_simple.sh" ]; then
        "$SCRIPT_DIR/analyze_simple.sh" "$RESULT_DIR/summary.csv" > "$RESULT_DIR/analysis.txt"
        cat "$RESULT_DIR/analysis.txt"
    else
        log_warn "analyze_simple.sh를 찾을 수 없습니다."
    fi
    
    # 상세 보고서 (옵션)
    if [ "$DETAILED_REPORT" = "true" ] && command -v python3 >/dev/null 2>&1; then
        log_info "상세 Python 보고서 생성 중..."
        python3 "$SCRIPT_DIR/generate_report.py" "$RESULT_DIR"
    elif [ "$DETAILED_REPORT" = "true" ]; then
        log_warn "DETAILED_REPORT=true이지만 Python3이 없어 상세 보고서를 건너뜁니다."
    fi
    
    # Shell 분석 결과 확인
    if [ -f "$RESULT_DIR/analysis.txt" ]; then
        log_info "Shell 분석 완료: $RESULT_DIR/analysis.txt"
    else
        log_error "Shell 분석 실패"
    fi
}

# 메인 실행 함수
main() {
    log_info "PG-Strom 성능 실험 시작"
    log_info "결과 저장 위치: $RESULT_DIR"
    log_info "실험 설정: ${REPEAT_COUNT}회 반복, ${SLEEP_BETWEEN_RUNS}초 간격"
    log_info "캐시 클리어: $CLEAR_CACHE"
    
    # 컨테이너 실행 상태 확인
    if ! docker ps --format 'table {{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        log_error "컨테이너가 실행되지 않았습니다. setup_pgstrom_experiment.sh를 먼저 실행하세요."
        exit 1
    fi
    
    # CSV 헤더 생성
    echo "test_name,gpu_enabled,execution_time_ms" > "$RESULT_DIR/summary.csv"
    
    # 시스템 정보 수집
    collect_system_info
    
    # 실험 실행
    test_simple_scan
    test_subset_join
    test_large_join
    test_simple_math
    test_complex_math
    test_simple_ops
    
    # 결과 분석
    analyze_results
    
    log_info "모든 실험 완료!"
    log_info "결과 확인: ls -la $RESULT_DIR"
}

# 스크립트 실행
main "$@" 