# PG-Strom Phase별 구현 가이드

## Phase 1: 기본 GPU 연산 완성

### 현재 상태 분석
기존 완료된 테스트:
- ✅ `simple_scan` - 기본 스캔 연산
- ✅ `subset_join`, `large_join` - 조인 연산  
- ✅ `simple_math`, `complex_math`, `simple_ops` - 수학 연산

### 추가 구현 필요 항목

#### 1.1 문자열 연산 테스트
```sql
-- 문자열 검색 성능
SELECT * FROM large_table WHERE text_column LIKE '%pattern%';
SELECT * FROM large_table WHERE text_column ~* 'regex_pattern';

-- 문자열 함수 성능  
SELECT LENGTH(text_column), UPPER(text_column) FROM large_table;
SELECT SUBSTRING(text_column, 1, 10) FROM large_table;
```

#### 1.2 날짜/시간 연산 테스트
```sql
-- 날짜 범위 검색
SELECT * FROM events WHERE event_date BETWEEN '2024-01-01' AND '2024-12-31';

-- 날짜 함수 성능
SELECT EXTRACT(YEAR FROM event_date), DATE_TRUNC('month', event_date) FROM events;
SELECT AGE(NOW(), event_date) FROM events;
```

### 구현 스크립트

#### `test_string_operations.sh`
```bash
#!/bin/bash
# 문자열 연산 성능 테스트

CONTAINER_NAME="pgstrom-test"
RESULTS_DIR="experiment_results/string_ops_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

# 테스트 데이터 생성
echo "문자열 테스트 데이터 생성 중..."
docker exec $CONTAINER_NAME psql -U postgres -d testdb -c "
CREATE TABLE IF NOT EXISTS text_table (
    id SERIAL PRIMARY KEY,
    short_text VARCHAR(50),
    long_text TEXT,
    pattern_text VARCHAR(100)
);

INSERT INTO text_table (short_text, long_text, pattern_text)
SELECT 
    'short_' || i::text,
    repeat('long_text_content_' || i::text, 10),
    CASE WHEN i % 100 = 0 THEN 'special_pattern_' || i ELSE 'normal_' || i END
FROM generate_series(1, 5000000) i;
"

# GPU OFF 테스트
echo "GPU OFF 문자열 테스트..."
docker exec $CONTAINER_NAME psql -U postgres -d testdb -c "SET pg_strom.enabled = off;" \
  -c "\\timing on" \
  -c "SELECT COUNT(*) FROM text_table WHERE long_text LIKE '%content_1000%';" \
  > "$RESULTS_DIR/string_like_off.txt"

# GPU ON 테스트  
echo "GPU ON 문자열 테스트..."
docker exec $CONTAINER_NAME psql -U postgres -d testdb -c "SET pg_strom.enabled = on;" \
  -c "\\timing on" \
  -c "SELECT COUNT(*) FROM text_table WHERE long_text LIKE '%content_1000%';" \
  > "$RESULTS_DIR/string_like_on.txt"
```

## Phase 2: 고급 연산 구현

### 2.1 GROUP BY 연산 테스트

#### `test_group_by.sh`
```bash
#!/bin/bash
# GROUP BY 연산 성능 테스트

CONTAINER_NAME="pgstrom-test"
RESULTS_DIR="experiment_results/group_by_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

# 테스트 쿼리들
GROUP_BY_QUERIES=(
    "SELECT category, COUNT(*) FROM sales GROUP BY category;"
    "SELECT category, SUM(amount) FROM sales GROUP BY category;"
    "SELECT category, region, AVG(amount) FROM sales GROUP BY category, region;"
    "SELECT DATE_TRUNC('month', order_date), SUM(amount) FROM sales GROUP BY DATE_TRUNC('month', order_date);"
)

for i in "${!GROUP_BY_QUERIES[@]}"; do
    query="${GROUP_BY_QUERIES[$i]}"
    echo "테스트 $((i+1)): $query"
    
    # GPU OFF
    docker exec $CONTAINER_NAME psql -U postgres -d testdb \
        -c "SET pg_strom.enabled = off;" \
        -c "\\timing on" \
        -c "$query" > "$RESULTS_DIR/group_by_${i}_off.txt"
    
    # GPU ON
    docker exec $CONTAINER_NAME psql -U postgres -d testdb \
        -c "SET pg_strom.enabled = on;" \
        -c "\\timing on" \
        -c "$query" > "$RESULTS_DIR/group_by_${i}_on.txt"
done
```

### 2.2 집계 함수 테스트

#### `test_aggregates.sh`
```bash
#!/bin/bash
# 집계 함수 성능 테스트

AGGREGATE_FUNCTIONS=(
    "SELECT COUNT(*) FROM large_table;"
    "SELECT SUM(amount), AVG(amount), MIN(amount), MAX(amount) FROM large_table;"
    "SELECT COUNT(DISTINCT category) FROM large_table;"
    "SELECT STDDEV(amount), VARIANCE(amount) FROM large_table;"
)

# 실행 로직은 GROUP BY와 유사
```

### 2.3 정렬 연산 테스트

#### `test_sorting.sh`
```bash
#!/bin/bash
# ORDER BY 성능 테스트

SORTING_QUERIES=(
    "SELECT * FROM large_table ORDER BY amount LIMIT 1000;"
    "SELECT * FROM large_table ORDER BY amount DESC, category ASC LIMIT 1000;"
    "SELECT category, SUM(amount) FROM large_table GROUP BY category ORDER BY SUM(amount) DESC;"
)
```

## Phase 3: 스토리지 및 데이터 형식

### 3.1 Apache Arrow 연동 테스트

#### `test_arrow_storage.sh`
```bash
#!/bin/bash
# Apache Arrow vs PostgreSQL Heap 성능 비교

# Arrow 테이블 생성
docker exec $CONTAINER_NAME psql -U postgres -d testdb -c "
CREATE FOREIGN TABLE arrow_sales (
    id INTEGER,
    amount NUMERIC,
    category TEXT,
    order_date DATE
) SERVER arrow_fdw OPTIONS (file '/data/sales.arrow');
"

# 동일 쿼리로 성능 비교
COMPARISON_QUERIES=(
    "SELECT COUNT(*) FROM sales;" # Heap
    "SELECT COUNT(*) FROM arrow_sales;" # Arrow
    "SELECT category, SUM(amount) FROM sales GROUP BY category;" # Heap
    "SELECT category, SUM(amount) FROM arrow_sales GROUP BY category;" # Arrow
)
```

### 3.2 데이터 타입별 성능 테스트

#### `test_data_types.sh`
```bash
#!/bin/bash
# 다양한 데이터 타입 성능 측정

DATA_TYPE_TESTS=(
    "INTEGER" "SELECT SUM(int_col) FROM type_test_table;"
    "BIGINT" "SELECT SUM(bigint_col) FROM type_test_table;"  
    "NUMERIC" "SELECT SUM(numeric_col) FROM type_test_table;"
    "FLOAT" "SELECT SUM(float_col) FROM type_test_table;"
    "TEXT" "SELECT COUNT(DISTINCT text_col) FROM type_test_table;"
    "TIMESTAMP" "SELECT COUNT(*) FROM type_test_table WHERE ts_col > '2024-01-01';"
)
```

## Phase 4: 인덱스 활용

### 4.1 BRIN 인덱스 테스트

#### `test_indexing.sh`
```bash
#!/bin/bash
# 인덱스 활용도 테스트

# BRIN 인덱스 생성
docker exec $CONTAINER_NAME psql -U postgres -d testdb -c "
CREATE INDEX CONCURRENTLY idx_sales_date_brin ON sales USING BRIN (order_date);
CREATE INDEX CONCURRENTLY idx_sales_amount_brin ON sales USING BRIN (amount);
"

# 인덱스 유무 비교 테스트
INDEX_TESTS=(
    "SELECT * FROM sales WHERE order_date BETWEEN '2024-01-01' AND '2024-01-31';"
    "SELECT * FROM sales WHERE amount BETWEEN 1000 AND 5000;"
    "SELECT COUNT(*) FROM sales WHERE order_date > '2024-06-01';"
)

# 각 테스트를 인덱스 있음/없음으로 실행
```

## Phase 5: 고급 기능

### 5.1 GPU Cache 테스트

#### `test_gpu_cache.sh`
```bash
#!/bin/bash
# GPU Cache 효과 측정

# GPU Cache 설정
docker exec $CONTAINER_NAME psql -U postgres -d testdb -c "
SET pg_strom.gpu_cache_size = '2GB';
SET pg_strom.gpu_cache_threshold = 100;
"

# 반복 쿼리로 캐시 효과 측정
CACHE_QUERY="SELECT category, COUNT(*), SUM(amount) FROM sales GROUP BY category;"

echo "첫 번째 실행 (캐시 미스)"
docker exec $CONTAINER_NAME psql -U postgres -d testdb -c "\\timing on" -c "$CACHE_QUERY"

echo "두 번째 실행 (캐시 히트 예상)"  
docker exec $CONTAINER_NAME psql -U postgres -d testdb -c "\\timing on" -c "$CACHE_QUERY"
```

### 5.2 PostGIS 테스트

#### `test_postgis.sh`
```bash
#!/bin/bash
# PostGIS 함수 GPU 가속 테스트

# 지리 데이터 생성
docker exec $CONTAINER_NAME psql -U postgres -d testdb -c "
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE locations (
    id SERIAL PRIMARY KEY,
    point GEOMETRY(POINT, 4326),
    polygon GEOMETRY(POLYGON, 4326)
);

INSERT INTO locations (point, polygon)
SELECT 
    ST_MakePoint(random() * 360 - 180, random() * 180 - 90),
    ST_Buffer(ST_MakePoint(random() * 360 - 180, random() * 180 - 90), 0.1)
FROM generate_series(1, 1000000);
"

# PostGIS 함수 성능 테스트
POSTGIS_QUERIES=(
    "SELECT COUNT(*) FROM locations WHERE ST_DWithin(point, ST_MakePoint(0, 0), 10);"
    "SELECT ST_Area(polygon), ST_Perimeter(polygon) FROM locations LIMIT 100000;"
)
```

## 자동화 통합 스크립트

### `comprehensive_benchmark.sh`
```bash
#!/bin/bash
# 전체 Phase 자동 실행

PHASES=(
    "test_string_operations.sh"
    "test_group_by.sh" 
    "test_aggregates.sh"
    "test_sorting.sh"
    "test_arrow_storage.sh"
    "test_data_types.sh"
    "test_indexing.sh"
    "test_gpu_cache.sh"
    "test_postgis.sh"
)

echo "PG-Strom 종합 벤치마크 시작: $(date)"

for phase in "${PHASES[@]}"; do
    echo "실행 중: $phase"
    if [[ -f "$phase" ]]; then
        ./"$phase"
        echo "$phase 완료"
    else
        echo "스크립트를 찾을 수 없음: $phase"
    fi
done

echo "전체 벤치마크 완료: $(date)"

# 결과 통합 분석
python3 ../analysis/comprehensive_analyzer.py
```

## 성능 분석 도구

### `performance_analyzer.py`
```python
#!/usr/bin/env python3
import os
import re
import json
import pandas as pd
import matplotlib.pyplot as plt

class PGStromAnalyzer:
    def __init__(self, results_dir):
        self.results_dir = results_dir
        self.performance_data = {}
    
    def parse_timing_output(self, file_path):
        """psql timing 출력에서 실행 시간 추출"""
        with open(file_path, 'r') as f:
            content = f.read()
        
        # "Time: 1234.567 ms" 패턴 찾기
        time_pattern = r'Time: ([\d.]+) ms'
        matches = re.findall(time_pattern, content)
        
        if matches:
            return float(matches[-1])  # 마지막 실행 시간
        return None
    
    def analyze_phase_results(self, phase_name):
        """특정 Phase 결과 분석"""
        phase_results = {}
        
        for file in os.listdir(self.results_dir):
            if phase_name in file:
                gpu_status = 'on' if '_on.txt' in file else 'off'
                execution_time = self.parse_timing_output(
                    os.path.join(self.results_dir, file)
                )
                
                test_name = file.replace(f'_{gpu_status}.txt', '')
                if test_name not in phase_results:
                    phase_results[test_name] = {}
                
                phase_results[test_name][gpu_status] = execution_time
        
        return phase_results
    
    def calculate_speedup(self, gpu_off_time, gpu_on_time):
        """속도 향상 배수 계산"""
        if gpu_on_time and gpu_off_time:
            return gpu_off_time / gpu_on_time
        return None
    
    def generate_report(self):
        """종합 성능 보고서 생성"""
        report = {
            "summary": {},
            "detailed_results": {},
            "recommendations": []
        }
        
        # 각 Phase별 결과 분석
        phases = ["group_by", "aggregates", "sorting", "string_ops"]
        
        for phase in phases:
            results = self.analyze_phase_results(phase)
            report["detailed_results"][phase] = results
            
            # 평균 성능 향상 계산
            speedups = []
            for test, times in results.items():
                if 'on' in times and 'off' in times:
                    speedup = self.calculate_speedup(times['off'], times['on'])
                    if speedup:
                        speedups.append(speedup)
            
            if speedups:
                avg_speedup = sum(speedups) / len(speedups)
                report["summary"][phase] = {
                    "average_speedup": avg_speedup,
                    "best_speedup": max(speedups),
                    "worst_speedup": min(speedups)
                }
        
        return report
    
    def create_visualizations(self, report):
        """성능 비교 그래프 생성"""
        # Phase별 평균 성능 향상 차트
        phases = list(report["summary"].keys())
        speedups = [report["summary"][phase]["average_speedup"] for phase in phases]
        
        plt.figure(figsize=(10, 6))
        plt.bar(phases, speedups)
        plt.title('PG-Strom GPU 가속 효과 (Phase별 평균)')
        plt.ylabel('성능 향상 배수 (GPU OFF / GPU ON)')
        plt.xticks(rotation=45)
        plt.tight_layout()
        plt.savefig(os.path.join(self.results_dir, 'phase_comparison.png'))
        plt.close()

if __name__ == "__main__":
    analyzer = PGStromAnalyzer("../experiment_results/latest")
    report = analyzer.generate_report()
    analyzer.create_visualizations(report)
    
    # JSON 보고서 저장
    with open("performance_report.json", "w") as f:
        json.dump(report, f, indent=2)
```

## 다음 단계

1. **Phase 1 완성**: 누락된 문자열, 날짜 연산 테스트 추가
2. **Phase 2 구현**: GROUP BY, AGGREGATE 스크립트 개발  
3. **자동화 개선**: 전체 파이프라인 통합
4. **분석 도구**: Python 기반 성능 분석기 완성
5. **문서화**: 각 Phase별 상세 결과 기록

---
*작성일: 2025-07-10*
*담당자: 재솔님* 