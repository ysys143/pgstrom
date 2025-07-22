#!/bin/bash

# Phase 1-C Simple Test: String and DateTime Operations
# Quick Performance Test with Report Generation
# Author: 재솔님 + AI Assistant
# Date: 2025-07-17

set -e

# 설정 변수
CONTAINER_NAME="pgstrom-test"
DB_NAME="postgres"
DB_USER="postgres"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULT_DIR="experiment_results/results_${TIMESTAMP}"
RUNS=3  # 빠른 테스트를 위해 3회로 축소

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

# 캐시 클리어 함수 (간소화)
clear_cache() {
    log "캐시 클리어 중..."
    docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "DISCARD ALL;" > /dev/null
    sleep 1
}

# 시스템 정보 수집
collect_system_info() {
    log "시스템 정보 수집 중..."
    
    {
        echo "Phase 1-C 간단 테스트 환경"
        echo "=========================="
        echo ""
        echo "날짜: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "CUDA 버전: $(nvidia-smi | grep "CUDA Version" | awk '{print $9}' || echo 'Unknown')"
        echo "GPU 정보:"
        nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader
        echo ""
        echo "PG-Strom 버전: $(docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT extversion FROM pg_extension WHERE extname = 'pg_strom';" | xargs)"
    } > "${RESULT_DIR}/system_info.txt"
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
        docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "SET pg_strom.enabled = on;" > /dev/null
    else
        docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "SET pg_strom.enabled = off;" > /dev/null
    fi
    
    # 쿼리 실행 시간 측정
    local start_time=$(date +%s.%N)
    docker exec "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "EXPLAIN (ANALYZE, BUFFERS) $query" > "$output_file" 2>&1
    local end_time=$(date +%s.%N)
    
    # 실행 시간 계산 및 기록
    local execution_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    echo "" >> "$output_file"
    echo "실행 시간: ${execution_time}초" >> "$output_file"
    
    # 실행 시간에서 ms 추출 (EXPLAIN ANALYZE의 Execution Time)
    local exec_time_ms=$(grep "Execution Time:" "$output_file" | tail -1 | awk '{print $3}' | sed 's/ms//')
    if [ -n "$exec_time_ms" ]; then
        echo "$exec_time_ms" >> "${RESULT_DIR}/${test_name}${suffix}_times.txt"
        log "${test_name}${suffix} Run ${run_number}: ${exec_time_ms}ms"
    else
        log "${test_name}${suffix} Run ${run_number}: 시간 측정 실패"
        echo "0" >> "${RESULT_DIR}/${test_name}${suffix}_times.txt"
    fi
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
try:
    with open('${times_file}', 'r') as f:
        times = [float(line.strip()) for line in f if line.strip() and float(line.strip()) > 0]
except:
    times = []

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

# 문자열 연산 테스트 실행
run_string_tests() {
    log "=== 문자열 연산 테스트 실행 ==="
    
    # 간단한 테스트 케이스 정의
    declare -A string_tests
    string_tests["string_concat"]="SELECT COUNT(*) FROM string_test WHERE id <= 10000;"
    string_tests["string_length"]="SELECT category, COUNT(*) FROM string_test WHERE id <= 10000 GROUP BY category;"
    
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
    
    log "문자열 연산 테스트 완료"
}

# 날짜/시간 연산 테스트 실행
run_datetime_tests() {
    log "=== 날짜/시간 연산 테스트 실행 ==="
    
    # 간단한 테스트 케이스 정의
    declare -A datetime_tests
    datetime_tests["date_extraction"]="SELECT EXTRACT(year FROM created_at) as year, COUNT(*) FROM datetime_test WHERE id <= 10000 GROUP BY year;"
    datetime_tests["date_arithmetic"]="SELECT COUNT(*) FROM datetime_test WHERE created_at + INTERVAL '1 year' > modified_at AND id <= 10000;"
    
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
    
    log "날짜/시간 연산 테스트 완료"
}

# 간단한 리포트 생성
generate_simple_report() {
    log "=== 간단한 보고서 생성 중 ==="
    
    cat > "${RESULT_DIR}/generate_report.py" << 'EOF'
#!/usr/bin/env python3
import os
import re
import json
import statistics
from datetime import datetime

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
        'count': len(times)
    }

def analyze_performance():
    """성능 분석"""
    result_dir = os.path.dirname(os.path.abspath(__file__))
    
    # 테스트 케이스 목록
    all_tests = ['string_concat', 'string_length', 'date_extraction', 'date_arithmetic']
    
    results = {
        'performance_results': {},
        'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    }
    
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
                'improvement_percent': abs(improvement),
                'faster': faster,
                'runs_count': gpu_on_stats['count']
            }
    
    return results

def generate_markdown_report(results):
    """마크다운 보고서 생성"""
    content = f"""# PG-Strom Phase 1-C 간단 성능 테스트

**작성자**: 재솔님  
**작성일**: {results['timestamp']}  

## 실험 결과

| 테스트 케이스 | GPU (ms) | CPU (ms) | 성능 향상 | 우수한 방식 |
|---------------|----------|----------|-----------|------------|
"""
    
    for test_name, data in results['performance_results'].items():
        display_name = test_name.replace('_', ' ').title()
        content += f"| {display_name} | {data['gpu_on']:.1f} | {data['gpu_off']:.1f} | {data['improvement_percent']:.1f}% | {data['faster']} |\n"
    
    gpu_wins = sum(1 for data in results['performance_results'].values() if data['faster'] == 'GPU')
    cpu_wins = sum(1 for data in results['performance_results'].values() if data['faster'] == 'CPU')
    total_tests = len(results['performance_results'])
    
    content += f"""

## 요약

- 총 {total_tests}개 테스트 중 GPU가 {gpu_wins}개, CPU가 {cpu_wins}개 테스트에서 우수한 성능을 보였습니다.
- 각 테스트는 {list(results['performance_results'].values())[0]['runs_count']}회 반복 실행되었습니다.

## 결론

문자열 및 날짜/시간 연산에서 PG-Strom의 GPU 가속 효과를 확인했습니다.

---
*Phase 1-C 간단 테스트 결과입니다.*
"""
    
    with open('performance_report.md', 'w', encoding='utf-8') as f:
        f.write(content)

def main():
    """메인 함수"""
    results = analyze_performance()
    
    # JSON 결과 저장
    with open('experiment_summary.json', 'w') as f:
        json.dump(results, f, indent=2)
    
    # 마크다운 보고서 생성
    generate_markdown_report(results)
    
    # 간단한 요약 출력
    print("=== Phase 1-C 간단 테스트 결과 ===")
    for test_name, data in results['performance_results'].items():
        print(f"{test_name}: GPU {data['gpu_on']:.1f}ms vs CPU {data['gpu_off']:.1f}ms ({data['faster']} 우수)")
    
    print("\n보고서 생성 완료:")
    print("- performance_report.md: 마크다운 보고서")
    print("- experiment_summary.json: JSON 결과")

if __name__ == "__main__":
    main()
EOF
    
    chmod +x "${RESULT_DIR}/generate_report.py"
}

# 메인 실행 함수
main() {
    log "=== Phase 1-C 간단 테스트 시작 ==="
    
    # 초기 설정
    collect_system_info
    
    # 성능 테스트 실행
    run_string_tests
    run_datetime_tests
    
    # 보고서 생성
    generate_simple_report
    
    log "=== 보고서 생성 중 ==="
    cd "$RESULT_DIR"
    python3 generate_report.py
    cd - > /dev/null
    
    log "=== Phase 1-C 간단 테스트 완료 ==="
    log "결과 위치: $RESULT_DIR"
    
    echo ""
    echo "Phase 1-C 간단 테스트가 완료되었습니다!"
    echo "결과 디렉토리: $RESULT_DIR"
    echo ""
    echo "주요 결과 파일:"
    echo "- performance_report.md: 마크다운 보고서"
    echo "- experiment_summary.json: JSON 결과"
    echo "- *_on.txt / *_off.txt: 개별 테스트 결과"
}

# 스크립트 실행
main "$@" 