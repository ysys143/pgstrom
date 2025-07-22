# PG-Strom Phase별 구현 가이드 v2.0

**최종 업데이트**: 2025-07-17  
**환경**: NVIDIA L40S × 3, PG-Strom v6.0.1, PostgreSQL 16, CUDA 12.9  
**현재 진행**: Phase 1 완료, Phase 2 준비 중

## 📊 전체 진행 현황

### ✅ Phase 1: 기본 GPU 연산 (100% 완료)

#### Phase 1-A: RTX 3060 기본 테스트 (완료)
- ✅ `simple_scan` - 기본 스캔 연산
- ✅ `subset_join`, `large_join` - 조인 연산  
- ✅ `simple_math`, `complex_math`, `simple_ops` - 수학 연산
- ✅ QPS 측정 시스템 개발
- ✅ GPU 병목지점 분석 완료

#### Phase 1-B: L40S 마이그레이션 (완료)
- ✅ NVIDIA L40S × 3 환경 구축 완료
- ✅ PG-Strom v6.0.1 + PostgreSQL 16 설치
- ✅ CUDA 12.9 환경 호환성 확인
- ✅ 기존 테스트 L40S 환경 재검증
- ✅ GPU 가속 쿼리 실행 검증

#### Phase 1-C: 문자열/날짜시간 연산 (완료)
- ✅ 문자열 연결 테스트: GPU 17.6% 성능 향상
- ✅ 복잡한 문자열 연산: CPU 3배 우수 성능
- ✅ 날짜/시간 집계 연산: 성능 차이 미미
- ✅ **핵심 발견**: 모든 테스트에서 GPU 활용률 0%
- ✅ **사용 스크립트**: `04_phase1c_string_datetime_test.sh`

## 🔄 Phase 2: 고급 연산 구현 (다음 단계)

### 2.1 GROUP BY 연산 테스트 (예정: 7월 4주차)

#### L40S 최적화 GROUP BY 테스트
```bash
#!/bin/bash
# GROUP BY 연산 성능 테스트 (L40S 환경)

CONTAINER_NAME="pgstrom-test"
RESULTS_DIR="experiment_results/phase2_group_by_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

# L40S × 3 GPU 테스트용 대용량 데이터 생성
echo "L40S 대용량 테스트 데이터 생성 중..."
docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "
CREATE TABLE IF NOT EXISTS l40s_sales_large (
    id BIGSERIAL PRIMARY KEY,
    category VARCHAR(50),
    region VARCHAR(50),
    amount NUMERIC(15,2),
    order_date DATE,
    partition_key INTEGER
);

-- L40S 44GB 메모리 활용 대용량 데이터 (10M 행)
INSERT INTO l40s_sales_large (category, region, amount, order_date, partition_key)
SELECT 
    'category_' || (i % 100),
    'region_' || (i % 20),
    (random() * 10000)::NUMERIC(15,2),
    '2023-01-01'::date + (i % 365) * INTERVAL '1 day',
    i % 3  -- 3개 GPU에 분산
FROM generate_series(1, 10000000) i;
"

# L40S 환경 GPU 모니터링 시작
nvidia-smi --query-gpu=timestamp,index,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv -l 1 > "$RESULTS_DIR/gpu_monitor_group_by.csv" &
GPU_MONITOR_PID=$!

# GROUP BY 테스트 쿼리들 (L40S 최적화)
GROUP_BY_QUERIES=(
    "SELECT category, COUNT(*) FROM l40s_sales_large GROUP BY category;"
    "SELECT category, SUM(amount) FROM l40s_sales_large GROUP BY category;"
    "SELECT category, region, AVG(amount) FROM l40s_sales_large GROUP BY category, region;"
    "SELECT partition_key, DATE_TRUNC('month', order_date), SUM(amount) FROM l40s_sales_large GROUP BY partition_key, DATE_TRUNC('month', order_date);"
    "SELECT category, COUNT(*), SUM(amount), AVG(amount), MIN(amount), MAX(amount) FROM l40s_sales_large GROUP BY category;"
)

for i in "${!GROUP_BY_QUERIES[@]}"; do
    query="${GROUP_BY_QUERIES[$i]}"
    echo "L40S 테스트 $((i+1)): $query"
    
    # GPU OFF
    echo "GPU OFF 실행 중..."
    time docker exec $CONTAINER_NAME psql -U postgres -d postgres \
        -c "SET pg_strom.enabled = off;" \
        -c "$query" > "$RESULTS_DIR/group_by_${i}_off.txt" 2>&1
    
    sleep 2
    
    # GPU ON
    echo "GPU ON 실행 중..."
    time docker exec $CONTAINER_NAME psql -U postgres -d postgres \
        -c "SET pg_strom.enabled = on;" \
        -c "$query" > "$RESULTS_DIR/group_by_${i}_on.txt" 2>&1
    
    sleep 3
done

# GPU 모니터링 종료
kill $GPU_MONITOR_PID 2>/dev/null || true

echo "GROUP BY 테스트 완료: $RESULTS_DIR"
```

### 2.2 AGGREGATE 함수 테스트 (예정: 8월 1주차)

#### L40S 대용량 집계 테스트
```bash
#!/bin/bash
# 집계 함수 성능 테스트 (L40S 44GB 메모리 활용)

AGGREGATE_FUNCTIONS=(
    "SELECT COUNT(*) FROM l40s_sales_large;"
    "SELECT SUM(amount), AVG(amount), MIN(amount), MAX(amount) FROM l40s_sales_large;"
    "SELECT COUNT(DISTINCT category), COUNT(DISTINCT region) FROM l40s_sales_large;"
    "SELECT STDDEV(amount), VARIANCE(amount) FROM l40s_sales_large WHERE amount > 1000;"
    "SELECT category, COUNT(*), SUM(amount), AVG(amount) FROM l40s_sales_large GROUP BY category HAVING COUNT(*) > 50000;"
)

# 실행 로직은 GROUP BY와 유사하지만 더 복잡한 집계 함수 포함
```

### 2.3 WINDOW 함수 테스트 (예정: 8월 1주차)

#### L40S WINDOW 함수 가속 테스트
```bash
#!/bin/bash
# WINDOW 함수 GPU 가속 테스트

WINDOW_QUERIES=(
    "SELECT id, amount, ROW_NUMBER() OVER (PARTITION BY category ORDER BY amount DESC) FROM l40s_sales_large;"
    "SELECT id, amount, SUM(amount) OVER (PARTITION BY category ORDER BY order_date) FROM l40s_sales_large;"
    "SELECT id, amount, AVG(amount) OVER (PARTITION BY region ORDER BY order_date ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) FROM l40s_sales_large;"
    "SELECT id, amount, RANK() OVER (ORDER BY amount DESC), DENSE_RANK() OVER (ORDER BY amount DESC) FROM l40s_sales_large;"
)
```

## 📊 Phase 3: 스토리지 및 메모리 관리 (예정: 8월 2주차)

### 3.1 L40S 메모리 최적화 테스트

#### L40S 44GB 메모리 활용도 측정
```bash
#!/bin/bash
# L40S GPU 메모리 효율성 테스트

# PG-Strom L40S 최적화 설정
docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "
SET pg_strom.chunk_size = '128MB';  -- L40S 44GB 메모리 고려
SET pg_strom.max_async_tasks = 12;  -- L40S × 3 멀티태스킹
SET pg_strom.gpu_cache_size = '32GB';  -- L40S 메모리 풀 최적화
"

# 메모리 사용량별 성능 측정
MEMORY_TEST_SIZES=(
    "1000000"    # 1M 행 (~100MB)
    "10000000"   # 10M 행 (~1GB)
    "50000000"   # 50M 행 (~5GB)
    "100000000"  # 100M 행 (~10GB) - L40S 대용량 테스트
)
```

### 3.2 Apache Arrow vs PostgreSQL Heap (L40S 환경)

#### L40S 환경에서 스토리지 형식 비교
```bash
#!/bin/bash
# L40S 환경 Arrow vs Heap 성능 비교

# Arrow 테이블 생성 (L40S 대용량 처리 고려)
docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "
CREATE FOREIGN TABLE arrow_sales_l40s (
    id BIGINT,
    amount NUMERIC,
    category TEXT,
    order_date DATE,
    partition_key INTEGER
) SERVER arrow_fdw OPTIONS (file '/data/l40s_sales.arrow');
"

# L40S × 3 GPU 병렬 처리 테스트
COMPARISON_QUERIES=(
    "SELECT COUNT(*) FROM l40s_sales_large;" # Heap
    "SELECT COUNT(*) FROM arrow_sales_l40s;" # Arrow
    "SELECT partition_key, category, SUM(amount) FROM l40s_sales_large GROUP BY partition_key, category;" # Heap
    "SELECT partition_key, category, SUM(amount) FROM arrow_sales_l40s GROUP BY partition_key, category;" # Arrow
)
```

## 🔍 Phase 4: 인덱스 및 최적화 (예정: 8월 3주차)

### 4.1 L40S 환경 BRIN 인덱스 테스트

#### L40S 대용량 데이터 인덱스 성능
```bash
#!/bin/bash
# L40S 환경 인덱스 활용도 테스트

# BRIN 인덱스 생성 (L40S 대용량 데이터 고려)
docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "
CREATE INDEX CONCURRENTLY idx_l40s_sales_date_brin ON l40s_sales_large USING BRIN (order_date);
CREATE INDEX CONCURRENTLY idx_l40s_sales_amount_brin ON l40s_sales_large USING BRIN (amount);
CREATE INDEX CONCURRENTLY idx_l40s_sales_partition_brin ON l40s_sales_large USING BRIN (partition_key);
"

# L40S 환경 인덱스 테스트
INDEX_TESTS=(
    "SELECT * FROM l40s_sales_large WHERE order_date BETWEEN '2024-01-01' AND '2024-01-31';"
    "SELECT * FROM l40s_sales_large WHERE amount BETWEEN 1000 AND 5000;"
    "SELECT COUNT(*) FROM l40s_sales_large WHERE partition_key = 0 AND order_date > '2024-06-01';"
)
```

## ⚙️ Phase 5: L40S 시스템 튜닝 (예정: 8월 3주차)

### 5.1 L40S × 3 GPU 최적화 설정

#### L40S 전용 파라미터 튜닝
```bash
#!/bin/bash
# L40S × 3 GPU 최적화 설정 테스트

# L40S 최적화 파라미터 설정
L40S_CONFIGS=(
    "pg_strom.chunk_size = '64MB'"
    "pg_strom.chunk_size = '128MB'"
    "pg_strom.chunk_size = '256MB'"
)

L40S_ASYNC_TASKS=(
    "pg_strom.max_async_tasks = 6"   # 2 per GPU
    "pg_strom.max_async_tasks = 12"  # 4 per GPU
    "pg_strom.max_async_tasks = 18"  # 6 per GPU
)

L40S_CACHE_SIZES=(
    "pg_strom.gpu_cache_size = '16GB'"
    "pg_strom.gpu_cache_size = '32GB'"
    "pg_strom.gpu_cache_size = '40GB'"  # L40S 44GB 중 대부분 활용
)

# 각 설정 조합별 성능 측정
for chunk_size in "${L40S_CONFIGS[@]}"; do
    for async_tasks in "${L40S_ASYNC_TASKS[@]}"; do
        for cache_size in "${L40S_CACHE_SIZES[@]}"; do
            echo "테스트 설정: $chunk_size, $async_tasks, $cache_size"
            
            docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "
            SET $chunk_size;
            SET $async_tasks;
            SET $cache_size;
            "
            
            # 표준 벤치마크 쿼리 실행
            time docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "
            SELECT category, COUNT(*), SUM(amount) FROM l40s_sales_large GROUP BY category;
            "
        done
    done
done
```

## 🚨 Phase 6: 에러 케이스 및 실운영 (예정: 8월 4주차)

### 6.1 L40S 44GB 메모리 한계 테스트

#### GPU 메모리 부족 상황 테스트
```bash
#!/bin/bash
# L40S 44GB 메모리 한계 상황 테스트

# 점진적 데이터 크기 증가로 메모리 한계 찾기
MEMORY_LIMIT_TESTS=(
    "SELECT COUNT(*) FROM l40s_sales_large;"  # 기본 10M 행
    "SELECT COUNT(*) FROM l40s_sales_large CROSS JOIN l40s_sales_large LIMIT 100000000;"  # 크로스 조인으로 메모리 압박
    "SELECT category, region, COUNT(*), SUM(amount) FROM l40s_sales_large GROUP BY category, region;"  # 대용량 GROUP BY
)

# GPU 메모리 사용량 실시간 모니터링
nvidia-smi --query-gpu=memory.used,memory.total --format=csv -l 1 > memory_usage.csv &

# CPU fallback 동작 확인
echo "GPU 메모리 한계 테스트 - CPU fallback 동작 확인"
```

## 🎯 Phase 7: 실시간 대용량 처리 (예정: 9월 1주차)

### 7.1 L40S × 3 실시간 스트리밍 테스트

#### 실시간 데이터 생성 프로그램 (L40S 최적화)
```python
#!/usr/bin/env python3
# L40S 환경 실시간 대용량 데이터 생성기

import psycopg2
import time
import random
from concurrent.futures import ThreadPoolExecutor

class L40SStreamGenerator:
    def __init__(self):
        self.conn = psycopg2.connect(
            host="localhost",
            port=5432,
            database="postgres",
            user="postgres"
        )
    
    def generate_stream_data(self, gpu_partition, records_per_second=1000):
        """L40S GPU별 파티션 데이터 생성"""
        cursor = self.conn.cursor()
        
        batch_size = 100
        while True:
            batch_data = []
            for _ in range(batch_size):
                record = (
                    random.randint(1, 1000000),
                    f'category_{random.randint(1, 100)}',
                    f'region_{random.randint(1, 20)}',
                    round(random.uniform(10, 10000), 2),
                    gpu_partition  # L40S GPU 파티션
                )
                batch_data.append(record)
            
            cursor.executemany("""
                INSERT INTO l40s_realtime_stream 
                (id, category, region, amount, gpu_partition, created_at)
                VALUES (%s, %s, %s, %s, %s, NOW())
            """, batch_data)
            
            self.conn.commit()
            time.sleep(batch_size / records_per_second)
    
    def start_multi_gpu_streams(self):
        """L40S × 3 GPU 병렬 스트림 시작"""
        with ThreadPoolExecutor(max_workers=3) as executor:
            for gpu_id in range(3):
                executor.submit(self.generate_stream_data, gpu_id)

if __name__ == "__main__":
    generator = L40SStreamGenerator()
    generator.start_multi_gpu_streams()
```

## 📋 자동화 통합 스크립트 (L40S 환경)

### `l40s_comprehensive_benchmark.sh`
```bash
#!/bin/bash
# L40S × 3 GPU 전체 Phase 자동 실행

echo "=== L40S 환경 PG-Strom 종합 벤치마크 시작 ==="
echo "GPU 정보:"
nvidia-smi --query-gpu=index,name,memory.total --format=csv

# L40S 환경 Phase 실행 순서
L40S_PHASES=(
    "03_run_basic_performance_tests.sh"       # 기본 성능 재검증
    "04_phase1c_string_datetime_test.sh"      # Phase 1-C 재실행
    "phase2_group_by_test.sh"                 # Phase 2 GROUP BY
    "phase2_aggregate_test.sh"                # Phase 2 AGGREGATE
    "phase3_memory_optimization.sh"           # Phase 3 메모리 최적화
    "phase4_indexing_test.sh"                 # Phase 4 인덱싱
    "phase5_l40s_tuning.sh"                   # Phase 5 L40S 튜닝
    "phase6_error_handling.sh"                # Phase 6 에러 처리
    "phase7_realtime_streaming.sh"            # Phase 7 실시간 처리
)

RESULTS_BASE_DIR="experiment_results/l40s_comprehensive_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_BASE_DIR"

echo "결과 저장 위치: $RESULTS_BASE_DIR"

for phase in "${L40S_PHASES[@]}"; do
    if [[ -f "automation/script/$phase" ]]; then
        echo "실행 중: $phase"
        ./automation/script/"$phase" | tee "$RESULTS_BASE_DIR/${phase%.sh}.log"
        echo "$phase 완료"
        sleep 5  # L40S GPU 쿨다운
    else
        echo "스크립트를 찾을 수 없음: $phase"
    fi
done

echo "=== L40S 환경 종합 벤치마크 완료 ==="

# L40S 환경 종합 분석
python3 automation/script/generate_report.py "$RESULTS_BASE_DIR"
```

## 📊 L40S 환경 성능 분석 도구

### `l40s_performance_analyzer.py`
```python
#!/usr/bin/env python3
import os
import re
import json
from datetime import datetime

class L40SPerformanceAnalyzer:
    def __init__(self, results_dir):
        self.results_dir = results_dir
        self.l40s_data = {
            "gpu_count": 3,
            "gpu_memory_per_unit": "44GB",
            "total_gpu_memory": "132GB",
            "cuda_version": "12.9",
            "pg_strom_version": "6.0.1"
        }
    
    def analyze_gpu_utilization(self, gpu_monitor_file):
        """L40S GPU 활용률 분석"""
        if not os.path.exists(gpu_monitor_file):
            return None
        
        gpu_stats = {0: [], 1: [], 2: []}
        
        with open(gpu_monitor_file, 'r') as f:
            lines = f.readlines()[1:]  # 헤더 제외
            
            for line in lines:
                parts = line.strip().split(', ')
                if len(parts) >= 6:
                    gpu_id = int(parts[1])
                    utilization = float(parts[2].replace(' %', ''))
                    memory_used = float(parts[3].replace(' MiB', ''))
                    
                    gpu_stats[gpu_id].append({
                        'utilization': utilization,
                        'memory_used': memory_used
                    })
        
        # L40S × 3 GPU 통계 계산
        summary = {}
        for gpu_id, stats in gpu_stats.items():
            if stats:
                avg_util = sum(s['utilization'] for s in stats) / len(stats)
                avg_memory = sum(s['memory_used'] for s in stats) / len(stats)
                max_memory = max(s['memory_used'] for s in stats)
                
                summary[f'GPU_{gpu_id}'] = {
                    'avg_utilization': avg_util,
                    'avg_memory_used_mb': avg_memory,
                    'max_memory_used_mb': max_memory,
                    'memory_utilization_percent': (max_memory / 47185) * 100  # L40S 46GB = 47185MB
                }
        
        return summary
    
    def generate_l40s_report(self):
        """L40S 환경 특화 보고서 생성"""
        report = {
            "environment": self.l40s_data,
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "phase_results": {},
            "gpu_analysis": {},
            "recommendations": []
        }
        
        # GPU 모니터링 파일들 분석
        for file in os.listdir(self.results_dir):
            if "gpu_monitor" in file and file.endswith(".csv"):
                phase_name = file.replace("gpu_monitor_", "").replace(".csv", "")
                gpu_analysis = self.analyze_gpu_utilization(
                    os.path.join(self.results_dir, file)
                )
                if gpu_analysis:
                    report["gpu_analysis"][phase_name] = gpu_analysis
        
        # L40S 환경 권장사항 생성
        self.generate_l40s_recommendations(report)
        
        return report
    
    def generate_l40s_recommendations(self, report):
        """L40S 환경 최적화 권장사항"""
        recommendations = []
        
        # GPU 활용률 기반 권장사항
        gpu_analysis = report.get("gpu_analysis", {})
        
        for phase, analysis in gpu_analysis.items():
            for gpu_key, stats in analysis.items():
                avg_util = stats.get('avg_utilization', 0)
                memory_util = stats.get('memory_utilization_percent', 0)
                
                if avg_util < 5:
                    recommendations.append(f"{phase}: {gpu_key} 활용률이 {avg_util:.1f}%로 매우 낮음 - CPU 처리 고려")
                
                if memory_util > 80:
                    recommendations.append(f"{phase}: {gpu_key} 메모리 사용률이 {memory_util:.1f}%로 높음 - 청크 크기 조정 필요")
                elif memory_util < 20:
                    recommendations.append(f"{phase}: {gpu_key} 메모리 사용률이 {memory_util:.1f}%로 낮음 - 더 큰 데이터 처리 가능")
        
        report["recommendations"] = recommendations

if __name__ == "__main__":
    analyzer = L40SPerformanceAnalyzer("../experiment_results/latest")
    report = analyzer.generate_l40s_report()
    
    # L40S 환경 보고서 저장
    with open("l40s_performance_report.json", "w", encoding='utf-8') as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    
    print("L40S 환경 성능 분석 완료!")
```

## 🎯 다음 단계 (우선순위)

### 즉시 실행 (7월 4주차)
1. **Phase 2 GROUP BY 테스트** 구현 및 실행
2. **L40S × 3 GPU 병렬 처리** 최적화
3. **대용량 데이터 테스트** (44GB 메모리 활용)

### 단기 목표 (8월)
1. **Phase 2-3 완성**: AGGREGATE, WINDOW, 스토리지 최적화
2. **L40S 파라미터 튜닝**: 최적 설정 도출
3. **실시간 처리 환경** 구축

### 장기 목표 (9월)
1. **Phase 7 실시간 스트리밍** 완전 구현
2. **RTX 3060 vs L40S** 종합 성능 비교
3. **실운영 가이드라인** 완성

---
**작성일**: 2025-07-17  
**담당자**: 재솔님  
**현재 상태**: Phase 1 완료 (100%), Phase 2 준비 중  
**환경**: NVIDIA L40S × 3, 44GB × 3 = 132GB GPU 메모리 