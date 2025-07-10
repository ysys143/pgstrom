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
EXPERIMENT_DIR="/home/jaesol/Projects/pgstrom/experiment_results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULT_DIR="$EXPERIMENT_DIR/results_$TIMESTAMP"

# 결과 디렉토리 생성
mkdir -p "$RESULT_DIR"

# 테스트 실행 함수
run_test() {
    local test_name="$1"
    local database="$2"
    local sql_query="$3"
    local gpu_enabled="$4"
    
    log_step "테스트 실행: $test_name (GPU: $gpu_enabled)"
    
    local result_file="$RESULT_DIR/${test_name}_${gpu_enabled}.txt"
    
    # GPU 설정
    local gpu_setting="SET pg_strom.enabled = $gpu_enabled;"
    
    # 실행 시간 측정
    local start_time=$(date +%s.%N)
    
    docker container exec $CONTAINER_NAME su - postgres -c "
        psql $database -c \"$gpu_setting EXPLAIN (ANALYZE, VERBOSE, BUFFERS) $sql_query\"
    " > "$result_file" 2>&1
    
    local end_time=$(date +%s.%N)
    local execution_time=$(echo "$end_time - $start_time" | bc)
    
    echo "실행 시간: ${execution_time}초" >> "$result_file"
    
    # 결과에서 실행 시간 추출
    local actual_time=$(grep "Execution Time:" "$result_file" | awk '{print $3}' | sed 's/ms//')
    
    if [ ! -z "$actual_time" ]; then
        echo "$test_name,$gpu_enabled,$actual_time" >> "$RESULT_DIR/summary.csv"
        log_info "$test_name (GPU: $gpu_enabled) 완료: ${actual_time}ms"
    else
        log_error "$test_name (GPU: $gpu_enabled) 실행 시간 추출 실패"
    fi
}

# 1. 단순 스캔 테스트
test_simple_scan() {
    log_step "=== 1. 단순 스캔 테스트 ==="
    
    local sql="SELECT sum(id * ten), avg(twenty) FROM t_test WHERE id > 1000000;"
    
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
    
    local sql="SELECT count(*), sum(pow(val, 2)), avg(sin(val)) FROM t_huge WHERE val = 1;"
    
    run_test "simple_math" "testdb2" "$sql" "on"
    sleep 2
    run_test "simple_math" "testdb2" "$sql" "off"
    sleep 2
}

# 5. 수학 함수 테스트 (복합)
test_complex_math() {
    log_step "=== 5. 수학 함수 테스트 (복합) ==="
    
    local sql="SELECT count(*), sum(sqrt(abs(val)) + log(val + 2) + exp(val)), avg(atan2(val, id % 100)) FROM t_huge WHERE val = 1;"
    
    run_test "complex_math" "testdb2" "$sql" "on"
    sleep 2
    run_test "complex_math" "testdb2" "$sql" "off"
    sleep 2
}

# 6. 단순 연산 테스트
test_simple_ops() {
    log_step "=== 6. 단순 연산 테스트 ==="
    
    local sql="SELECT count(*), sum(val * val), avg(val + val) FROM t_huge WHERE val = 1;"
    
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
        echo ""
        
        echo "=== GPU 정보 ==="
        docker container exec $CONTAINER_NAME nvidia-smi
        echo ""
        
        echo "=== PG-Strom 정보 ==="
        docker container exec $CONTAINER_NAME su - postgres -c "
            psql testdb -c \"SELECT * FROM pgstrom.gpu_device_info() LIMIT 10;\"
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
    
    # CSV 헤더 추가
    sed -i '1i test_name,gpu_enabled,execution_time_ms' "$RESULT_DIR/summary.csv"
    
    # 결과 분석 스크립트 생성
    cat > "$RESULT_DIR/analyze_results.py" << 'EOF'
#!/usr/bin/env python3
import pandas as pd
import sys

def analyze_results(csv_file):
    try:
        df = pd.read_csv(csv_file)
        
        print("=== PG-Strom 성능 분석 결과 ===\n")
        
        # 테스트별 성능 비교
        for test_name in df['test_name'].unique():
            test_data = df[df['test_name'] == test_name]
            
            gpu_on = test_data[test_data['gpu_enabled'] == 'on']['execution_time_ms'].values
            gpu_off = test_data[test_data['gpu_enabled'] == 'off']['execution_time_ms'].values
            
            if len(gpu_on) > 0 and len(gpu_off) > 0:
                gpu_time = gpu_on[0]
                cpu_time = gpu_off[0]
                
                improvement = ((cpu_time - gpu_time) / cpu_time) * 100
                
                print(f"테스트: {test_name}")
                print(f"  GPU 시간: {gpu_time:.1f}ms")
                print(f"  CPU 시간: {cpu_time:.1f}ms")
                print(f"  성능 향상: {improvement:+.1f}%")
                print()
        
        print("=== 요약 ===")
        print(f"총 테스트 수: {len(df['test_name'].unique())}")
        print(f"GPU 우위 테스트: {len([t for t in df['test_name'].unique() if get_improvement(df, t) > 0])}")
        print(f"CPU 우위 테스트: {len([t for t in df['test_name'].unique() if get_improvement(df, t) < 0])}")
        
    except Exception as e:
        print(f"분석 중 오류 발생: {e}")

def get_improvement(df, test_name):
    test_data = df[df['test_name'] == test_name]
    gpu_on = test_data[test_data['gpu_enabled'] == 'on']['execution_time_ms'].values
    gpu_off = test_data[test_data['gpu_enabled'] == 'off']['execution_time_ms'].values
    
    if len(gpu_on) > 0 and len(gpu_off) > 0:
        return ((gpu_off[0] - gpu_on[0]) / gpu_off[0]) * 100
    return 0

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("사용법: python3 analyze_results.py <csv_file>")
        sys.exit(1)
    
    analyze_results(sys.argv[1])
EOF
    
    # Python으로 결과 분석
    if command -v python3 &> /dev/null; then
        python3 "$RESULT_DIR/analyze_results.py" "$RESULT_DIR/summary.csv" > "$RESULT_DIR/analysis.txt"
        cat "$RESULT_DIR/analysis.txt"
    else
        log_warn "Python3가 설치되지 않아 자동 분석을 건너뜁니다."
    fi
    
    log_info "결과 분석 완료: $RESULT_DIR/analysis.txt"
}

# 메인 실행 함수
main() {
    log_info "PG-Strom 성능 실험 시작"
    log_info "결과 저장 위치: $RESULT_DIR"
    
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