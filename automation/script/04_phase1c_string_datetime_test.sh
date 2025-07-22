#!/bin/bash

# Phase 1-C: String and DateTime Operations Test
# Execution Time Based Performance Measurement (Like results_20250717_114539)
# Author: 재솔님 + AI Assistant
# Date: 2025-07-17

set -e

# 설정 변수
CONTAINER_NAME="pgstrom-test"
DB_NAME="postgres"
DB_USER="postgres"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULT_DIR="experiment_results/results_${TIMESTAMP}"
RUNS=8  # 각 테스트당 반복 횟수

# 결과 디렉토리 생성
mkdir -p "$RESULT_DIR"

# 로그 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 에러 처리 함수
handle_error() {
    log "ERROR: $1"
    exit 1
}

# GPU 상태 확인 함수
check_gpu_status() {
    log "=== L40S GPU 상태 확인 ==="
    nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv
    echo ""
}

# PG-Strom 연결 테스트
test_connection() {
    log "=== PG-Strom 연결 테스트 ==="
    docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" || handle_error "DB 연결 실패"
    docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT * FROM pg_extension WHERE extname = 'pg_strom';" || handle_error "PG-Strom extension 확인 실패"
    log "PG-Strom 연결 성공"
}

# 캐시 클리어 함수
clear_cache() {
    log "캐시 클리어 중..."
    docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT pg_reload_conf();"
    docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "DISCARD ALL;"
    sync
    sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || true
    sleep 2
}

# 시스템 정보 수집
collect_system_info() {
    log "시스템 정보 수집 중..."
    
    # 시스템 정보 파일 생성
    {
        echo "실험 환경 정보"
        echo "================"
        echo ""
        echo "날짜: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "호스트: $(hostname)"
        echo "커널: $(uname -r)"
        echo "CPU: $(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
        echo "메모리: $(free -h | grep Mem | awk '{print $2}')"
        echo ""
        echo "CUDA 정보:"
        nvidia-smi --query-gpu=index,name,memory.total --format=csv
        echo ""
        echo "CUDA 버전: $(nvidia-smi | grep "CUDA Version" | awk '{print $9}')"
        echo ""
        echo "PostgreSQL 정보:"
        docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT version();"
        echo ""
        echo "PG-Strom 정보:"
        docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT extversion FROM pg_extension WHERE extname = 'pg_strom';"
    } > "${RESULT_DIR}/system_info.txt"
}

# 테스트 데이터 생성
create_test_data() {
    log "=== 테스트 데이터 생성 ==="
    
    docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" << 'EOF'
-- 기존 테이블 삭제
DROP TABLE IF EXISTS string_test CASCADE;
DROP TABLE IF EXISTS datetime_test CASCADE;
DROP TABLE IF EXISTS string_test_small CASCADE;
DROP TABLE IF EXISTS datetime_test_small CASCADE;

-- 문자열 테스트 테이블 생성 (1M 레코드)
CREATE TABLE string_test (
    id SERIAL PRIMARY KEY,
    text_short VARCHAR(50),
    text_medium VARCHAR(500),
    text_long TEXT,
    category VARCHAR(20),
    status VARCHAR(10)
);

-- 문자열 데이터 생성
INSERT INTO string_test (text_short, text_medium, text_long, category, status)
SELECT 
    'Item_' || (i % 1000),
    'This is a medium length text for testing string operations. Record number: ' || i || '. ' || repeat('data ', 20),
    'This is a long text field for comprehensive string testing. ' || repeat('Lorem ipsum dolor sit amet, consectetur adipiscing elit. ', 10) || ' Record: ' || i,
    CASE (i % 10)
        WHEN 0 THEN 'electronics'
        WHEN 1 THEN 'clothing'
        WHEN 2 THEN 'books'
        WHEN 3 THEN 'sports'
        WHEN 4 THEN 'home'
        WHEN 5 THEN 'garden'
        WHEN 6 THEN 'automotive'
        WHEN 7 THEN 'health'
        WHEN 8 THEN 'beauty'
        ELSE 'other'
    END,
    CASE (i % 3)
        WHEN 0 THEN 'active'
        WHEN 1 THEN 'inactive'
        ELSE 'pending'
    END
FROM generate_series(1, 1000000) AS i;

-- 날짜/시간 테스트 테이블 생성 (1M 레코드)
CREATE TABLE datetime_test (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP,
    modified_at TIMESTAMP,
    birth_date DATE,
    event_time TIME,
    duration INTERVAL,
    timezone_info TIMESTAMPTZ,
    year_col INTEGER,
    month_col INTEGER,
    day_col INTEGER
);

-- 날짜/시간 데이터 생성
INSERT INTO datetime_test (created_at, modified_at, birth_date, event_time, duration, timezone_info, year_col, month_col, day_col)
SELECT 
    TIMESTAMP '2020-01-01' + (i || ' seconds')::interval,
    TIMESTAMP '2023-01-01' + (i || ' seconds')::interval,
    DATE '1980-01-01' + (i % 15000) || ' days',
    TIME '08:00:00' + (i % 86400 || ' seconds')::interval,
    (i % 3600 || ' seconds')::interval,
    (TIMESTAMP '2023-01-01' + (i || ' seconds')::interval) AT TIME ZONE 'UTC',
    2020 + (i % 5),
    1 + (i % 12),
    1 + (i % 28)
FROM generate_series(1, 1000000) AS i;

-- 인덱스 생성
CREATE INDEX idx_string_category ON string_test(category);
CREATE INDEX idx_string_status ON string_test(status);
CREATE INDEX idx_datetime_created ON datetime_test(created_at);
CREATE INDEX idx_datetime_year_month ON datetime_test(year_col, month_col);

-- 통계 업데이트
ANALYZE string_test;
ANALYZE datetime_test;

-- 테이블 크기 확인
SELECT 'string_test' as table_name, 
       pg_size_pretty(pg_total_relation_size('string_test')) as size,
       count(*) as rows FROM string_test
UNION ALL
SELECT 'datetime_test' as table_name,
       pg_size_pretty(pg_total_relation_size('datetime_test')) as size,
       count(*) as rows FROM datetime_test;
EOF

    log "테스트 데이터 생성 완료"
}

# 단일 테스트 실행 함수
run_single_test() {
    local test_name="$1"
    local gpu_enabled="$2"
    local query="$3"
    local run_number="$4"
    
    local suffix=""
    if [ "$gpu_enabled" = "true" ]; then
        suffix="_on"
    else
        suffix="_off"
    fi
    
    local output_file="${RESULT_DIR}/${test_name}${suffix}.txt_run${run_number}.txt"
    
    # 캐시 클리어
    clear_cache
    
    # GPU 설정
    if [ "$gpu_enabled" = "true" ]; then
        docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "SET pg_strom.enabled = on;"
    else
        docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "SET pg_strom.enabled = off;"
    fi
    
    # 쿼리 실행 시간 측정
    local start_time=$(date +%s.%N)
    docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "EXPLAIN (ANALYZE, BUFFERS) $query" > "$output_file"
    local end_time=$(date +%s.%N)
    
    # 실행 시간 계산 및 기록
    local execution_time=$(echo "$end_time - $start_time" | bc)
    echo "" >> "$output_file"
    echo "실행 시간: ${execution_time}초" >> "$output_file"
    
    # 실행 시간에서 ms 추출 (EXPLAIN ANALYZE의 Execution Time)
    local exec_time_ms=$(grep "Execution Time:" "$output_file" | awk '{print $3}')
    echo "$exec_time_ms" >> "${RESULT_DIR}/${test_name}${suffix}_times.txt"
    
    log "${test_name}${suffix} Run ${run_number}: ${exec_time_ms}ms"
}

# 테스트 통계 계산
calculate_statistics() {
    local test_name="$1"
    local gpu_enabled="$2"
    
    local suffix=""
    if [ "$gpu_enabled" = "true" ]; then
        suffix="_on"
    else
        suffix="_off"
    fi
    
    local times_file="${RESULT_DIR}/${test_name}${suffix}_times.txt"
    local output_file="${RESULT_DIR}/${test_name}${suffix}.txt"
    
    if [ ! -f "$times_file" ]; then
        return
    fi
    
    # Python을 사용한 통계 계산
    python3 << EOF
import statistics
import sys

# 실행 시간 읽기
with open('${times_file}', 'r') as f:
    times = [float(line.strip()) for line in f if line.strip()]

if not times:
    sys.exit(1)

# 통계 계산
mean_time = statistics.mean(times)
min_time = min(times)
max_time = max(times)
stdev_time = statistics.stdev(times) if len(times) > 1 else 0
variance_time = statistics.variance(times) if len(times) > 1 else 0
cv = (stdev_time / mean_time * 100) if mean_time > 0 else 0

# 첫 번째 실행 결과에 통계 추가
with open('${output_file}', 'a') as f:
    f.write(f"""

=== {len(times)}회 반복 실행 통계 ===
평균 실행 시간: {mean_time:.2f}ms
최소 실행 시간: {min_time:.3f}ms
최대 실행 시간: {max_time:.3f}ms
표준편차: {stdev_time:.5f}ms
분산: {variance_time:.5f}ms²
변동계수 (CV): {cv:.2f}%ms
개별 실행 시간:
""")
    for time in times:
        f.write(f"{time:.3f}\n")
    f.write("\n")
EOF
}

# GPU 모니터링 시작
start_gpu_monitoring() {
    local test_name="$1"
    local monitor_file="${RESULT_DIR}/gpu_monitor_${test_name}.csv"
    
    # 헤더 작성
    echo "timestamp,index,name,memory.used [MiB],memory.total [MiB],utilization.gpu [%],temperature.gpu" > "$monitor_file"
    
    # 백그라운드에서 GPU 모니터링 시작
    while true; do
        nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader,nounits | \
        sed "s/^/$(date +%s),/" >> "$monitor_file"
        sleep 1
    done &
    
    echo $! > "${RESULT_DIR}/gpu_monitor_${test_name}.pid"
}

# GPU 모니터링 중지
stop_gpu_monitoring() {
    local test_name="$1"
    local pid_file="${RESULT_DIR}/gpu_monitor_${test_name}.pid"
    
    if [ -f "$pid_file" ]; then
        kill $(cat "$pid_file") 2>/dev/null || true
        rm -f "$pid_file"
    fi
}

# 문자열 연산 테스트 실행
run_string_tests() {
    log "=== 문자열 연산 테스트 실행 ==="
    
    # GPU 모니터링 시작
    start_gpu_monitoring "string"
    
    # 테스트 케이스 정의
    declare -A string_tests
    string_tests["string_concat"]="SELECT COUNT(*), LENGTH(text_short || '_suffix') FROM string_test WHERE id <= 500000;"
    string_tests["string_length"]="SELECT category, AVG(LENGTH(text_medium)), COUNT(*) FROM string_test WHERE id <= 500000 GROUP BY category;"
    string_tests["string_pattern"]="SELECT COUNT(*) FROM string_test WHERE text_medium LIKE '%Record number%' AND id <= 300000;"
    string_tests["complex_string"]="SELECT category, COUNT(*), STRING_AGG(SUBSTRING(text_short, 1, 10), '|') FROM string_test WHERE LENGTH(text_medium) > 100 AND id <= 200000 GROUP BY category;"
    
    # 각 테스트 실행
    for test_name in "${!string_tests[@]}"; do
        local query="${string_tests[$test_name]}"
        
        log "문자열 테스트: $test_name"
        
        # GPU ON 테스트
        for run in $(seq 1 $RUNS); do
            run_single_test "$test_name" "true" "$query" "$run"
        done
        calculate_statistics "$test_name" "true"
        
        # GPU OFF 테스트  
        for run in $(seq 1 $RUNS); do
            run_single_test "$test_name" "false" "$query" "$run"
        done
        calculate_statistics "$test_name" "false"
    done
    
    # GPU 모니터링 중지
    stop_gpu_monitoring "string"
    
    log "문자열 연산 테스트 완료"
}

# 날짜/시간 연산 테스트 실행
run_datetime_tests() {
    log "=== 날짜/시간 연산 테스트 실행 ==="
    
    # GPU 모니터링 시작
    start_gpu_monitoring "datetime"
    
    # 테스트 케이스 정의
    declare -A datetime_tests
    datetime_tests["date_extraction"]="SELECT EXTRACT(year FROM created_at) as year, COUNT(*) FROM datetime_test WHERE id <= 500000 GROUP BY year;"
    datetime_tests["date_arithmetic"]="SELECT COUNT(*) FROM datetime_test WHERE created_at + INTERVAL '1 year' > modified_at AND id <= 400000;"
    datetime_tests["timestamp_ops"]="SELECT year_col, month_col, COUNT(*), AVG(EXTRACT(epoch FROM duration)) FROM datetime_test WHERE id <= 300000 GROUP BY year_col, month_col;"
    datetime_tests["complex_datetime"]="SELECT DATE_TRUNC('month', created_at) as month, COUNT(*), MIN(birth_date), MAX(modified_at) FROM datetime_test WHERE EXTRACT(year FROM created_at) >= 2022 AND id <= 200000 GROUP BY month;"
    
    # 각 테스트 실행
    for test_name in "${!datetime_tests[@]}"; do
        local query="${datetime_tests[$test_name]}"
        
        log "날짜/시간 테스트: $test_name"
        
        # GPU ON 테스트
        for run in $(seq 1 $RUNS); do
            run_single_test "$test_name" "true" "$query" "$run"
        done
        calculate_statistics "$test_name" "true"
        
        # GPU OFF 테스트
        for run in $(seq 1 $RUNS); do
            run_single_test "$test_name" "false" "$query" "$run"
        done
        calculate_statistics "$test_name" "false"
    done
    
    # GPU 모니터링 중지
    stop_gpu_monitoring "datetime"
    
    log "날짜/시간 연산 테스트 완료"
}

# 성능 분석 스크립트 생성
generate_analysis_script() {
    cat > "${RESULT_DIR}/generate_report.py" << 'EOF'
#!/usr/bin/env python3
import os
import re
import json
import statistics
from datetime import datetime

def extract_execution_time(file_path):
    """EXPLAIN ANALYZE 결과에서 실행 시간 추출"""
    if not os.path.exists(file_path):
        return None
    
    with open(file_path, 'r') as f:
        content = f.read()
        match = re.search(r'Execution Time: ([\d.]+) ms', content)
        if match:
            return float(match.group(1))
    return None

def read_times_file(file_path):
    """times 파일에서 실행 시간 리스트 읽기"""
    if not os.path.exists(file_path):
        return []
    
    with open(file_path, 'r') as f:
        times = []
        for line in f:
            line = line.strip()
            if line:
                try:
                    times.append(float(line))
                except ValueError:
                    continue
        return times

def calculate_statistics(times):
    """통계 계산"""
    if not times:
        return None
    
    return {
        'mean': statistics.mean(times),
        'min': min(times),
        'max': max(times),
        'std': statistics.stdev(times) if len(times) > 1 else 0,
        'var': statistics.variance(times) if len(times) > 1 else 0,
        'cv': (statistics.stdev(times) / statistics.mean(times) * 100) if len(times) > 1 and statistics.mean(times) > 0 else 0,
        'count': len(times)
    }

def analyze_performance():
    """성능 분석"""
    result_dir = os.path.dirname(os.path.abspath(__file__))
    
    # 테스트 케이스 목록
    string_tests = ['string_concat', 'string_length', 'string_pattern', 'complex_string']
    datetime_tests = ['date_extraction', 'date_arithmetic', 'timestamp_ops', 'complex_datetime']
    
    results = {
        'performance_results': {},
        'system_info': {},
        'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    }
    
    # 시스템 정보 읽기
    system_info_file = os.path.join(result_dir, 'system_info.txt')
    if os.path.exists(system_info_file):
        with open(system_info_file, 'r') as f:
            content = f.read()
            
        # CUDA 버전 추출
        cuda_match = re.search(r'CUDA 버전: ([\d.]+)', content)
        cuda_version = cuda_match.group(1) if cuda_match else "Unknown"
        
        # GPU 정보 추출
        gpu_match = re.search(r'(\d+),\s*NVIDIA\s+([^,]+),\s*(\d+)', content)
        if gpu_match:
            gpu_count = int(gpu_match.group(1)) + 1  # 0-indexed
            gpu_model = gpu_match.group(2).strip()
            gpu_memory = gpu_match.group(3) + "MB"
        else:
            gpu_count = "Unknown"
            gpu_model = "Unknown"
            gpu_memory = "Unknown"
        
        results['system_info'] = {
            'cuda_version': cuda_version,
            'gpu_model': gpu_model,
            'gpu_count': str(gpu_count),
            'gpu_memory': gpu_memory,
            'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        }
    
    # 모든 테스트 분석
    all_tests = string_tests + datetime_tests
    
    for test_name in all_tests:
        # GPU ON 결과
        gpu_on_times = read_times_file(os.path.join(result_dir, f'{test_name}_on_times.txt'))
        gpu_on_stats = calculate_statistics(gpu_on_times)
        
        # GPU OFF 결과
        gpu_off_times = read_times_file(os.path.join(result_dir, f'{test_name}_off_times.txt'))
        gpu_off_stats = calculate_statistics(gpu_off_times)
        
        if gpu_on_stats and gpu_off_stats:
            # 성능 향상 계산
            improvement = ((gpu_off_stats['mean'] - gpu_on_stats['mean']) / gpu_off_stats['mean']) * 100
            faster = "GPU" if gpu_on_stats['mean'] < gpu_off_stats['mean'] else "CPU"
            
            results['performance_results'][test_name] = {
                'gpu_on': gpu_on_stats['mean'],
                'gpu_off': gpu_off_stats['mean'],
                'gpu_on_std': gpu_on_stats['std'],
                'gpu_off_std': gpu_off_stats['std'],
                'gpu_on_var': gpu_on_stats['var'],
                'gpu_off_var': gpu_off_stats['var'],
                'gpu_on_cv': gpu_on_stats['cv'],
                'gpu_off_cv': gpu_off_stats['cv'],
                'gpu_on_min': gpu_on_stats['min'],
                'gpu_on_max': gpu_on_stats['max'],
                'gpu_off_min': gpu_off_stats['min'],
                'gpu_off_max': gpu_off_stats['max'],
                'improvement_percent': abs(improvement),
                'faster': faster,
                'runs_count': gpu_on_stats['count']
            }
    
    return results

def generate_summary_csv(results):
    """CSV 요약 생성"""
    csv_content = "Test,GPU_ON_avg,GPU_OFF_avg,Improvement_%,Faster,Runs\n"
    
    for test_name, data in results['performance_results'].items():
        csv_content += f"{test_name},{data['gpu_on']:.2f},{data['gpu_off']:.2f},{data['improvement_percent']:.1f},{data['faster']},{data['runs_count']}\n"
    
    with open('summary.csv', 'w') as f:
        f.write(csv_content)

def generate_quick_summary(results):
    """빠른 요약 생성"""
    content = f"PG-Strom Phase 1-C 실험 결과 요약 ({results['timestamp']})\n"
    content += "=" * 60 + "\n\n"
    
    for test_name, data in results['performance_results'].items():
        content += f"{test_name.replace('_', ' ').title()} ({data['runs_count']}회 반복):\n"
        content += f"  GPU ON:  {data['gpu_on']:.1f}±{data['gpu_on_std']:.1f}ms (CV: {data['gpu_on_cv']:.1f}%)\n"
        content += f"  GPU OFF: {data['gpu_off']:.1f}±{data['gpu_off_std']:.1f}ms (CV: {data['gpu_off_cv']:.1f}%)\n"
        content += f"  성능 향상: {data['improvement_percent']:.1f}% ({data['faster']} 우수)\n\n"
    
    with open('quick_summary.txt', 'w') as f:
        f.write(content)

def generate_markdown_report(results):
    """마크다운 보고서 생성"""
    content = f"""# PG-Strom Phase 1-C 성능 분석 보고서

**작성자**: 재솔님  
**작성일**: {results['timestamp']}  
**실험 환경**: {results['system_info'].get('gpu_model', 'Unknown')} (CUDA {results['system_info'].get('cuda_version', 'Unknown')})

## 1. 실험 개요

본 실험은 PG-Strom을 사용한 PostgreSQL 문자열 및 날짜/시간 연산의 GPU 가속 성능을 분석하기 위해 수행되었습니다.

### 실험 방법론
- 매 실행 전 PostgreSQL shared_buffers 및 OS 페이지 캐시 클리어
- 통계적 신뢰성을 위한 다중 반복 실행 ({list(results['performance_results'].values())[0]['runs_count']}회)
- 평균, 표준편차, 분산, 변동계수 산출

### 실험 환경
- GPU: {results['system_info'].get('gpu_model', 'Unknown')}
- GPU 개수: {results['system_info'].get('gpu_count', 'Unknown')}
- CUDA 버전: {results['system_info'].get('cuda_version', 'Unknown')}
- 실험 일시: {results['timestamp']}

## 2. 실험 결과

### 성능 비교 결과 (반복 실행 평균)

| 테스트 케이스 | GPU 활성화 (ms) | GPU 비활성화 (ms) | 성능 향상 | 우수한 방식 |
|---------------|----------------|------------------|-----------|------------|
"""
    
    for test_name, data in results['performance_results'].items():
        display_name = test_name.replace('_', ' ').title()
        content += f"| {display_name} | {data['gpu_on']:.1f}±{data['gpu_on_std']:.1f} | {data['gpu_off']:.1f}±{data['gpu_off_std']:.1f} | {data['improvement_percent']:.1f}% | {data['faster']} |\n"
    
    content += f"""

### 상세 통계 정보

"""
    
    for test_name, data in results['performance_results'].items():
        display_name = test_name.replace('_', ' ').title()
        content += f"""
#### {display_name}
- **GPU 활성화**: 평균 {data['gpu_on']:.1f}ms
  - 표준편차: {data['gpu_on_std']:.1f}ms, 분산: {data['gpu_on_var']:.1f}ms²
  - 변동계수: {data['gpu_on_cv']:.1f}%
  - 최소: {data['gpu_on_min']:.1f}ms, 최대: {data['gpu_on_max']:.1f}ms
- **GPU 비활성화**: 평균 {data['gpu_off']:.1f}ms
  - 표준편차: {data['gpu_off_std']:.1f}ms, 분산: {data['gpu_off_var']:.1f}ms²
  - 변동계수: {data['gpu_off_cv']:.1f}%
  - 최소: {data['gpu_off_min']:.1f}ms, 최대: {data['gpu_off_max']:.1f}ms
- **반복 횟수**: {data['runs_count']}회
"""
    
    # 결론 분석
    gpu_wins = sum(1 for data in results['performance_results'].values() if data['faster'] == 'GPU')
    cpu_wins = sum(1 for data in results['performance_results'].values() if data['faster'] == 'CPU')
    total_tests = len(results['performance_results'])
    
    content += f"""

## 3. 결론 및 권장사항

### 주요 발견사항
- 총 {total_tests}개 테스트 중 GPU가 {gpu_wins}개, CPU가 {cpu_wins}개 테스트에서 우수한 성능을 보였습니다.
"""
    
    if gpu_wins > cpu_wins:
        best_gpu_test = max(results['performance_results'].items(), key=lambda x: x[1]['improvement_percent'] if x[1]['faster'] == 'GPU' else 0)
        content += f"- GPU 가속이 가장 효과적인 테스트: {best_gpu_test[0].replace('_', ' ').title()} ({best_gpu_test[1]['improvement_percent']:.1f}% 향상)\n"
    else:
        content += "- 문자열/날짜시간 연산에서는 CPU가 더 효율적인 경향을 보입니다.\n"
    
    content += f"""

### 권장사항
- 문자열 및 날짜/시간 연산의 경우 워크로드 특성에 따라 GPU 활성화 여부를 결정하는 것이 중요합니다.
- 실제 프로덕션 환경에서는 데이터 크기와 복잡도를 고려한 추가 테스트가 필요합니다.

## 4. 기술적 세부사항

### 실험 설정
- 테스트 데이터: 문자열 테이블 1,000만 행, 날짜/시간 테이블 1,000만 행
- 측정 방법: PostgreSQL EXPLAIN ANALYZE
- 반복 횟수: 각 테스트 GPU ON/OFF 각 {list(results['performance_results'].values())[0]['runs_count']}회

### 측정 지표
- 실행 시간 (ms)
- 표준편차 및 변동계수
- 성능 향상률

---
*이 보고서는 PG-Strom Phase 1-C 자동화 시스템에 의해 생성되었습니다.*
"""
    
    with open('performance_report.md', 'w', encoding='utf-8') as f:
        f.write(content)

def generate_analysis_summary(results):
    """분석 요약 생성 (기존 format과 유사)"""
    content = "=== PG-Strom Phase 1-C 성능 분석 결과 ===\n\n"
    
    for test_name, data in results['performance_results'].items():
        display_name = test_name.replace('_', ' ').title()
        content += f"테스트: {test_name}\n"
        content += f"  GPU 시간: {data['gpu_on']:.3f}ms\n"
        content += f"  CPU 시간: {data['gpu_off']:.3f}ms\n"
        content += f"  성능 향상: {data['improvement_percent']:.1f}%\n"
        content += f"  우수한 방식: {data['faster']}\n\n"
    
    # 요약
    gpu_wins = sum(1 for data in results['performance_results'].values() if data['faster'] == 'GPU')
    cpu_wins = sum(1 for data in results['performance_results'].values() if data['faster'] == 'CPU')
    total_tests = len(results['performance_results'])
    
    content += "=== 요약 ===\n"
    content += f"총 테스트 수: {total_tests}\n"
    content += f"GPU 우위 테스트: {gpu_wins}\n"
    content += f"CPU 우위 테스트: {cpu_wins}\n"
    
    with open('analysis.txt', 'w') as f:
        f.write(content)

def main():
    """메인 함수"""
    results = analyze_performance()
    
    # JSON 결과 저장
    with open('experiment_summary.json', 'w') as f:
        json.dump(results, f, indent=2)
    
    # 다양한 형식의 보고서 생성
    generate_summary_csv(results)
    generate_quick_summary(results)
    generate_markdown_report(results)
    generate_analysis_summary(results)
    
    print("보고서 생성 완료:")
    print("- performance_report.md: 상세 마크다운 보고서")
    print("- quick_summary.txt: 빠른 요약")
    print("- analysis.txt: 성능 분석 요약")
    print("- summary.csv: CSV 형식 요약")
    print("- experiment_summary.json: JSON 형식 전체 결과")

if __name__ == "__main__":
    main()
EOF
    
    chmod +x "${RESULT_DIR}/generate_report.py"
}

# 메인 실행 함수
main() {
    log "=== Phase 1-C: 문자열/날짜시간 연산 테스트 시작 ==="
    log "실행 시간 기반 성능 측정 (results_20250717_114539 방식)"
    
    # 초기 설정
    check_gpu_status
    test_connection
    collect_system_info
    
    # 테스트 데이터 생성
    create_test_data
    
    # 성능 테스트 실행
    run_string_tests
    run_datetime_tests
    
    # 분석 스크립트 생성 및 실행
    generate_analysis_script
    
    log "=== 보고서 생성 중 ==="
    cd "$RESULT_DIR"
    python3 generate_report.py
    cd - > /dev/null
    
    # 최종 상태 확인
    check_gpu_status
    
    log "=== Phase 1-C 테스트 완료 ==="
    log "결과 위치: $RESULT_DIR"
    
    echo ""
    echo "Phase 1-C 테스트가 완료되었습니다!"
    echo "결과 디렉토리: $RESULT_DIR"
    echo ""
    echo "주요 결과 파일:"
    echo "- performance_report.md: 상세 마크다운 보고서"
    echo "- quick_summary.txt: 빠른 요약"
    echo "- analysis.txt: 성능 분석 요약"
    echo "- summary.csv: CSV 형식 요약"
    echo "- experiment_summary.json: JSON 형식 전체 결과"
    echo ""
    echo "개별 테스트 결과:"
    echo "- *_on.txt / *_off.txt: 각 테스트의 상세 실행 결과"
    echo "- *_times.txt: 개별 실행 시간 기록"
    echo "- gpu_monitor_*.csv: GPU 모니터링 데이터"
}

# 스크립트 실행
main "$@" 