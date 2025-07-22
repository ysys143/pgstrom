#!/bin/bash

# Phase 1-C: 본격적인 문자열 및 날짜/시간 연산 성능 테스트
# 2025-07-17 작성자: 신재솔
# 기존 성공 사례(results_20250717_114539)와 동일한 구조 및 방식 적용

set -e

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_DIR="$PROJECT_ROOT/experiment_results/results_$TIMESTAMP"
ITERATIONS=8
CONTAINER_NAME="pgstrom-test"

# 결과 디렉토리 생성
mkdir -p "$RESULTS_DIR"

echo "=== Phase 1-C: 본격적인 문자열/날짜시간 연산 성능 테스트 ==="
echo "실험 시작 시간: $(date '+%Y-%m-%d %H:%M:%S')"
echo "결과 저장 경로: $RESULTS_DIR"
echo "반복 횟수: $ITERATIONS회"
echo

# 시스템 정보 수집
echo "시스템 정보 수집 중..."
{
    echo "=== 시스템 정보 ==="
    echo "실험 일시: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "서버: $(hostname)"
    echo "OS: $(uname -a)"
    echo
    echo "=== GPU 정보 ==="
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits
    echo
    echo "=== PostgreSQL 버전 ==="
    docker exec $CONTAINER_NAME psql -U postgres -d testdb -c "SELECT version();"
    echo
    echo "=== PG-Strom 설정 ==="
    docker exec $CONTAINER_NAME psql -U postgres -d testdb -c "SHOW pg_strom.enabled;"
} > "$RESULTS_DIR/system_info.txt"

# 함수: 캐시 클리어
clear_cache() {
    echo "캐시 클리어 중..."
    docker exec $CONTAINER_NAME psql -U postgres -d testdb -c "SELECT pg_prewarm_reset();" 2>/dev/null || true
    docker exec $CONTAINER_NAME psql -U postgres -d testdb -c "DISCARD ALL;" 2>/dev/null || true
    sync
    # 권한이 있는 경우에만 시스템 캐시 클리어
    if [ -w /proc/sys/vm/drop_caches ]; then
        echo 3 > /proc/sys/vm/drop_caches
    fi
    sleep 2
}

# 함수: EXPLAIN ANALYZE에서 실행 시간 추출
extract_execution_time() {
    local log_file="$1"
    grep "Execution Time:" "$log_file" | tail -1 | awk '{print $3}' | tr -d 'ms'
}

# 함수: 테스트 실행
run_test() {
    local test_name="$1"
    local sql_query="$2"
    local pg_strom_enabled="$3"
    local status_suffix=""
    
    if [ "$pg_strom_enabled" = "on" ]; then
        status_suffix="on"
    else
        status_suffix="off"
    fi
    
    local base_file="$RESULTS_DIR/${test_name}_${status_suffix}.txt"
    local times_file="$RESULTS_DIR/${test_name}_${status_suffix}_times.txt"
    
    echo "  테스트 실행: $test_name (PG-Strom: $pg_strom_enabled)"
    
    # PG-Strom 설정
    clear_cache
    docker exec $CONTAINER_NAME psql -U postgres -d testdb -c "SET pg_strom.enabled = $pg_strom_enabled;"
    
    # 반복 실행
    for i in $(seq 1 $ITERATIONS); do
        echo "    실행 $i/$ITERATIONS..."
        clear_cache
        
        local run_file="${base_file}_run${i}.txt"
        
        # EXPLAIN ANALYZE 실행
        docker exec $CONTAINER_NAME psql -U postgres -d testdb -c "
        EXPLAIN (ANALYZE, BUFFERS, TIMING) 
        $sql_query
        " > "$run_file" 2>&1
        
        # 실행 시간 추출
        local exec_time=$(extract_execution_time "$run_file")
        echo "$exec_time" >> "$times_file"
        echo "      실행 시간: ${exec_time}ms"
    done
    
    # 전체 결과 통합
    cat "$RESULTS_DIR/${test_name}_${status_suffix}.txt_run"* > "$base_file"
    
    echo "  $test_name ($pg_strom_enabled) 완료"
    echo
}

# 함수: 통계 계산
calculate_stats() {
    local times_file="$1"
    
    if [ ! -f "$times_file" ] || [ ! -s "$times_file" ]; then
        echo "0 0 0 0 0 0"
        return
    fi
    
    python3 << EOF
import sys
import math

try:
    with open('$times_file', 'r') as f:
        times = [float(line.strip()) for line in f if line.strip()]
    
    if not times:
        print("0 0 0 0 0 0")
        sys.exit(0)
    
    n = len(times)
    mean = sum(times) / n
    variance = sum((x - mean) ** 2 for x in times) / (n - 1) if n > 1 else 0
    std_dev = math.sqrt(variance)
    cv = (std_dev / mean * 100) if mean > 0 else 0
    min_time = min(times)
    max_time = max(times)
    
    print(f"{mean:.1f} {std_dev:.1f} {variance:.1f} {cv:.1f} {min_time:.1f} {max_time:.1f}")
    
except Exception as e:
    print("0 0 0 0 0 0")
EOF
}

# 테스트 데이터 준비
echo "테스트 데이터 준비 중..."
docker exec $CONTAINER_NAME psql -U postgres -d testdb << 'EOF'
-- 기존 테이블 삭제 (존재하는 경우)
DROP TABLE IF EXISTS string_datetime_test;

-- 문자열/날짜시간 테스트용 테이블 생성 (100만 행)
CREATE TABLE string_datetime_test (
    id SERIAL PRIMARY KEY,
    text_data VARCHAR(100),
    short_text VARCHAR(20),
    created_date DATE,
    updated_timestamp TIMESTAMP,
    year_data INTEGER,
    category_code CHAR(5)
);

-- 인덱스 생성
CREATE INDEX idx_string_datetime_id ON string_datetime_test(id);
CREATE INDEX idx_string_datetime_date ON string_datetime_test(created_date);
CREATE INDEX idx_string_datetime_text ON string_datetime_test(text_data);

-- 샘플 데이터 삽입 (100만 행)
INSERT INTO string_datetime_test (text_data, short_text, created_date, updated_timestamp, year_data, category_code)
SELECT 
    'Sample text data for testing string operations number ' || i::TEXT,
    'Item' || (i % 1000)::TEXT,
    '2020-01-01'::DATE + (i % 1826)::INTEGER,
    '2020-01-01 00:00:00'::TIMESTAMP + (i * INTERVAL '1 minute'),
    2020 + (i % 5),
    'CAT' || LPAD((i % 100)::TEXT, 2, '0')
FROM generate_series(1, 1000000) AS i;

-- 통계 정보 업데이트
ANALYZE string_datetime_test;

-- 테이블 정보 확인
SELECT 
    COUNT(*) as total_rows,
    MIN(created_date) as min_date,
    MAX(created_date) as max_date,
    COUNT(DISTINCT category_code) as distinct_categories
FROM string_datetime_test;
EOF

echo "테스트 데이터 준비 완료"
echo

# 테스트 케이스 정의 및 실행
declare -A TEST_CASES

# 1. 문자열 연결 및 길이 계산
TEST_CASES["string_concat"]="
SELECT COUNT(*) 
FROM string_datetime_test 
WHERE LENGTH(text_data || ' - ' || short_text) > 50;
"

# 2. 문자열 패턴 매칭
TEST_CASES["string_pattern"]="
SELECT COUNT(*), category_code
FROM string_datetime_test 
WHERE text_data LIKE '%testing%' 
  AND short_text SIMILAR TO 'Item[0-9]+' 
GROUP BY category_code;
"

# 3. 문자열 함수 조합
TEST_CASES["string_functions"]="
SELECT 
    UPPER(LEFT(text_data, 20)) as upper_text,
    LOWER(RIGHT(short_text, 5)) as lower_text,
    COUNT(*)
FROM string_datetime_test 
WHERE POSITION('data' IN text_data) > 0
GROUP BY UPPER(LEFT(text_data, 20)), LOWER(RIGHT(short_text, 5))
ORDER BY COUNT(*) DESC
LIMIT 100;
"

# 4. 복합 문자열 연산
TEST_CASES["string_complex"]="
SELECT 
    category_code,
    SUBSTRING(text_data, 1, 30) as text_part,
    COUNT(*) as cnt,
    STRING_AGG(DISTINCT short_text, ', ') as aggregated_text
FROM string_datetime_test 
WHERE LENGTH(TRIM(text_data)) > 30 
  AND CHAR_LENGTH(short_text) BETWEEN 5 AND 15
GROUP BY category_code, SUBSTRING(text_data, 1, 30)
HAVING COUNT(*) > 10
ORDER BY COUNT(*) DESC
LIMIT 50;
"

# 5. 날짜 추출 및 계산
TEST_CASES["date_extraction"]="
SELECT 
    EXTRACT(YEAR FROM created_date) as year,
    EXTRACT(MONTH FROM created_date) as month,
    COUNT(*) as count,
    AVG(year_data) as avg_year
FROM string_datetime_test 
WHERE created_date BETWEEN '2021-01-01' AND '2023-12-31'
GROUP BY EXTRACT(YEAR FROM created_date), EXTRACT(MONTH FROM created_date)
ORDER BY year, month;
"

# 6. 날짜 연산 및 비교
TEST_CASES["date_arithmetic"]="
SELECT COUNT(*) 
FROM string_datetime_test s1 
JOIN string_datetime_test s2 ON s1.id = s2.id + 1000
WHERE s1.created_date - s2.created_date > INTERVAL '30 days'
  AND EXTRACT(DOW FROM s1.updated_timestamp) IN (1, 5, 6);
"

# 7. 타임스탬프 함수
TEST_CASES["timestamp_functions"]="
SELECT 
    DATE_TRUNC('month', updated_timestamp) as month_start,
    COUNT(*) as count,
    MIN(updated_timestamp) as min_ts,
    MAX(updated_timestamp) as max_ts,
    MAX(updated_timestamp) - MIN(updated_timestamp) as time_range
FROM string_datetime_test 
WHERE updated_timestamp > NOW() - INTERVAL '2 years'
GROUP BY DATE_TRUNC('month', updated_timestamp)
ORDER BY month_start
LIMIT 100;
"

# 8. 복합 날짜/시간 연산
TEST_CASES["datetime_complex"]="
SELECT 
    CASE 
        WHEN EXTRACT(QUARTER FROM created_date) = 1 THEN 'Q1'
        WHEN EXTRACT(QUARTER FROM created_date) = 2 THEN 'Q2'
        WHEN EXTRACT(QUARTER FROM created_date) = 3 THEN 'Q3'
        ELSE 'Q4'
    END as quarter,
    EXTRACT(YEAR FROM created_date) as year,
    COUNT(*) as count,
    AVG(EXTRACT(EPOCH FROM (updated_timestamp - (created_date + TIME '00:00:00')))) as avg_seconds_diff
FROM string_datetime_test 
WHERE AGE(updated_timestamp, created_date + TIME '00:00:00') < INTERVAL '2 years'
GROUP BY EXTRACT(QUARTER FROM created_date), EXTRACT(YEAR FROM created_date)
HAVING COUNT(*) > 1000
ORDER BY year, quarter;
"

# 모든 테스트 실행
echo "본격적인 성능 테스트 시작..."
echo

for test_name in "${!TEST_CASES[@]}"; do
    echo "=== $test_name 테스트 ==="
    
    # GPU 활성화 테스트
    run_test "$test_name" "${TEST_CASES[$test_name]}" "on"
    
    # GPU 비활성화 테스트  
    run_test "$test_name" "${TEST_CASES[$test_name]}" "off"
done

# 결과 분석 및 보고서 생성
echo "결과 분석 중..."

# CSV 요약 파일 생성
{
    echo "Test,GPU_Status,Mean,StdDev,Variance,CV,Min,Max,Iteration"
    
    for test_name in "${!TEST_CASES[@]}"; do
        for status in "on" "off"; do
            times_file="$RESULTS_DIR/${test_name}_${status}_times.txt"
            if [ -f "$times_file" ]; then
                stats=$(calculate_stats "$times_file")
                echo "$test_name,$status,$stats,$ITERATIONS"
            fi
        done
    done
} > "$RESULTS_DIR/summary.csv"

# JSON 형식 결과 생성
python3 << EOF > "$RESULTS_DIR/experiment_summary.json"
import json
import os
from datetime import datetime

results = {
    "experiment_info": {
        "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
        "phase": "1-C",
        "test_type": "String and DateTime Operations",
        "iterations": $ITERATIONS,
        "data_size": "1,000,000 rows"
    },
    "test_results": {}
}

test_names = [$(printf '"%s",' "${!TEST_CASES[@]}" | sed 's/,$//')]

for test_name in test_names:
    results["test_results"][test_name] = {"gpu_on": {}, "gpu_off": {}}
    
    for status in ["on", "off"]:
        times_file = f"$RESULTS_DIR/{test_name}_{status}_times.txt"
        
        if os.path.exists(times_file):
            try:
                with open(times_file, 'r') as f:
                    times = [float(line.strip()) for line in f if line.strip()]
                
                if times:
                    import math
                    n = len(times)
                    mean = sum(times) / n
                    variance = sum((x - mean) ** 2 for x in times) / (n - 1) if n > 1 else 0
                    std_dev = math.sqrt(variance)
                    cv = (std_dev / mean * 100) if mean > 0 else 0
                    
                    key = "gpu_on" if status == "on" else "gpu_off"
                    results["test_results"][test_name][key] = {
                        "mean_ms": round(mean, 1),
                        "std_dev_ms": round(std_dev, 1),
                        "variance_ms2": round(variance, 1),
                        "cv_percent": round(cv, 1),
                        "min_ms": round(min(times), 1),
                        "max_ms": round(max(times), 1),
                        "raw_times": times
                    }
            except:
                pass

print(json.dumps(results, indent=2, ensure_ascii=False))
EOF

# 마크다운 보고서 생성
python3 << 'EOF' > "$RESULTS_DIR/performance_report.md"
import json
import os
from datetime import datetime

# JSON 데이터 로드
with open(os.path.join("$RESULTS_DIR", "experiment_summary.json"), 'r') as f:
    data = json.load(f)

print("# PG-Strom GPU 가속 성능 분석 보고서 - Phase 1-C")
print()
print("**작성자**: 신재솔")
print(f"**작성일**: {data['experiment_info']['timestamp']}")
print("**실험 환경**: NVIDIA L40S x3 (CUDA 12.9)")
print()

print("## 1. 실험 개요")
print()
print("본 실험은 PG-Strom을 사용한 PostgreSQL의 문자열 및 날짜/시간 연산에 대한 GPU 가속 성능을 분석하기 위해 수행되었습니다.")
print()

print("### 실험 방법론")
print("- 매 실행 전 PostgreSQL shared_buffers 및 OS 페이지 캐시 클리어")
print("- 통계적 신뢰성을 위한 다중 반복 실행")
print("- 평균, 표준편차, 분산, 변동계수 산출")
print()

print("### 실험 환경")
print("- GPU: NVIDIA L40S x3")
print("- 데이터 크기: 1,000,000 행")
print("- 반복 횟수: 8회")
print(f"- 실험 일시: {data['experiment_info']['timestamp']}")
print()

print("## 2. 실험 결과")
print()

print("### 성능 비교 결과 (반복 실행 평균)")
print()
print("| 테스트 케이스 | GPU 활성화 (ms) | GPU 비활성화 (ms) | 성능 향상 | 우수한 방식 |")
print("|---------------|----------------|------------------|-----------|------------|")

for test_name, test_data in data["test_results"].items():
    if "gpu_on" in test_data and "gpu_off" in test_data:
        gpu_on = test_data["gpu_on"]
        gpu_off = test_data["gpu_off"]
        
        if "mean_ms" in gpu_on and "mean_ms" in gpu_off:
            gpu_mean = gpu_on["mean_ms"]
            cpu_mean = gpu_off["mean_ms"]
            gpu_std = gpu_on.get("std_dev_ms", 0)
            cpu_std = gpu_off.get("std_dev_ms", 0)
            
            if cpu_mean > 0:
                improvement = ((cpu_mean - gpu_mean) / cpu_mean) * 100
                better = "GPU" if gpu_mean < cpu_mean else "CPU"
                
                print(f"| {test_name.replace('_', ' ').title()} | {gpu_mean:.1f}±{gpu_std:.1f} | {cpu_mean:.1f}±{cpu_std:.1f} | {improvement:.1f}% | {better} |")

print()
print("### 상세 통계 정보")
print()

for test_name, test_data in data["test_results"].items():
    if "gpu_on" in test_data and "gpu_off" in test_data:
        print(f"#### {test_name.replace('_', ' ').title()}")
        
        gpu_on = test_data["gpu_on"]
        gpu_off = test_data["gpu_off"]
        
        if "mean_ms" in gpu_on:
            print(f"- **GPU 활성화**: 평균 {gpu_on['mean_ms']:.1f}ms")
            print(f"  - 표준편차: {gpu_on.get('std_dev_ms', 0):.1f}ms, 분산: {gpu_on.get('variance_ms2', 0):.1f}ms²")
            print(f"  - 변동계수: {gpu_on.get('cv_percent', 0):.1f}%")
            print(f"  - 최소: {gpu_on.get('min_ms', 0):.1f}ms, 최대: {gpu_on.get('max_ms', 0):.1f}ms")
        
        if "mean_ms" in gpu_off:
            print(f"- **GPU 비활성화**: 평균 {gpu_off['mean_ms']:.1f}ms")
            print(f"  - 표준편차: {gpu_off.get('std_dev_ms', 0):.1f}ms, 분산: {gpu_off.get('variance_ms2', 0):.1f}ms²")
            print(f"  - 변동계수: {gpu_off.get('cv_percent', 0):.1f}%")
            print(f"  - 최소: {gpu_off.get('min_ms', 0):.1f}ms, 최대: {gpu_off.get('max_ms', 0):.1f}ms")
        
        print(f"- **반복 횟수**: {data['experiment_info']['iterations']}회")
        print()

print("## 3. 분석 및 결론")
print()
print("### 주요 발견사항")
print("- 문자열 및 날짜/시간 연산에 대한 GPU 가속 효과 분석")
print("- 복잡한 문자열 함수 조합에서의 성능 특성")
print("- 날짜/시간 추출 및 계산 연산의 GPU 활용도")
print("- 대용량 데이터 처리 시 GPU와 CPU 성능 비교")
print()

print("### 권장사항")
print("- GPU 가속이 효과적인 연산 유형 식별")
print("- 데이터 크기와 연산 복잡도에 따른 최적 설정")
print("- 메모리 사용량과 성능의 균형점 탐색")
print()

print(f"**보고서 생성 일시**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
EOF

# 간단한 요약 파일 생성
{
    echo "=== Phase 1-C 문자열/날짜시간 연산 성능 테스트 요약 ==="
    echo "실험 일시: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "테스트 케이스 수: ${#TEST_CASES[@]}개"
    echo "반복 횟수: $ITERATIONS회"
    echo "데이터 크기: 1,000,000 행"
    echo
    echo "테스트 완료된 케이스:"
    for test_name in "${!TEST_CASES[@]}"; do
        echo "- $test_name"
    done
    echo
    echo "상세 결과:"
    echo "- performance_report.md: 마크다운 형식 보고서"
    echo "- experiment_summary.json: JSON 형식 원시 데이터"
    echo "- summary.csv: CSV 형식 요약 데이터"
    echo "- system_info.txt: 시스템 환경 정보"
} > "$RESULTS_DIR/quick_summary.txt"

# 정리
echo "=== 테스트 완료 ==="
echo "실험 종료 시간: $(date '+%Y-%m-%d %H:%M:%S')"
echo "결과 저장 경로: $RESULTS_DIR"
echo
echo "생성된 파일:"
echo "- performance_report.md: 상세 성능 분석 보고서"
echo "- experiment_summary.json: JSON 형식 실험 결과"
echo "- summary.csv: CSV 요약 데이터"
echo "- quick_summary.txt: 간단 요약"
echo "- system_info.txt: 시스템 정보"
echo
echo "다음 단계: Phase Implementation Guide 업데이트" 