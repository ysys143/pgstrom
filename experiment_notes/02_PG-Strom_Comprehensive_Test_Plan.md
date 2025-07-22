# PG-Strom 종합 테스트 계획 v3.0

## 📋 문서 개정 내역
- **v1.0**: 초기 계획 수립
- **v2.0**: 공식 문서 정밀 분석 후 주요 누락 사항 반영
- **v3.0**: L40S 환경 완료 및 Phase 1-B 완성 상태 반영 (2025-07-17)

## 🎯 테스트 목적 (업데이트)
- **RTX 3060 vs NVIDIA L40S × 3 GPU 성능 비교 분석** (완료된 마이그레이션 반영)
- **L40S 환경 최적화 및 다중 GPU 활용** (신규 목표)
- **실제 워크로드 시나리오별 성능 분석** 
- **에러 상황 및 CPU fallback 동작 검증**
- **실시간 대용량 처리 성능 분석** (Phase 7 신규)
- 최적 설정 및 사용 패턴 도출
- 실제 운영 환경 적용 가이드라인 제시

## 📊 테스트 대상 기능 (진행 상황 반영)

### ✅ Phase 1-A: RTX 3060 기본 테스트 (100% 완료)
- [x] **SCAN 연산**: WHERE 절 조건 평가
- [x] **JOIN 연산**: Hash Join, Nested Loop Join 성능
- [x] **수학 연산**: 기본/복합 수치 계산
- [x] **QPS 측정 시스템**: Query Per Second 성능 분석 도구 개발
- [x] **GPU 병목지점 분석**: GPU 활용률 0% 원인 규명

### ✅ Phase 1-B: L40S 마이그레이션 (100% 완료)
- [x] **새 서버 환경 구축**: 192.168.10.1 서버 완전 구축
- [x] **PG-Strom v6.0.1 환경**: PostgreSQL 16 + CUDA 12.9 완전 호환
- [x] **NVIDIA L40S × 3 GPU**: 인식 및 GPU 가속 쿼리 실행 검증
- [x] **성능 측정 도구 L40S 최적화**: QPS, GPU 모니터링 도구 완성
- [x] **기존 테스트 재검증**: L40S 환경에서 기본 테스트 완료

### 🔄 Phase 1-C: 문자열/날짜시간 연산 (20% 진행 중)
- [ ] **문자열 연산**: 텍스트 처리, 정규표현식 성능 (L40S 환경)
- [ ] **날짜/시간 연산**: timestamp, interval 처리 (L40S 환경)
- [ ] **데이터 타입별 성능**: 전체 지원 타입 체계적 분석
- [ ] **Phase 1 종합 분석**: RTX 3060 vs L40S 기본 성능 비교

### 🔄 Phase 2: 고급 연산 (예정: 7월 4주차)
- [ ] **GROUP BY 연산**: 그룹화 성능 (L40S 최적화)
- [ ] **AGGREGATE 함수**: SUM, COUNT, AVG, MIN, MAX, STDDEV (L40S 환경)
- [ ] **DISTINCT 연산**: 중복 제거 성능 (L40S 환경)
- [ ] **GPU-Sort**: ORDER BY와 별개의 GPU 정렬 엔진 (L40S 활용)
- [ ] **WINDOW 함수**: 윈도우 함수 가속 (L40S 환경)
- [ ] **복합 쿼리**: 여러 연산이 조합된 실제 워크로드 (L40S 최적화)

### 📊 Phase 3: 스토리지 및 메모리 관리 (예정: 8월 1-2주차)
- [ ] **PostgreSQL Heap vs Apache Arrow**: 저장 형식별 성능 (L40S 환경)
- [ ] **Arrow 고급 기능**: 컬럼형 압축, 메모리 효율성 (L40S 44GB 활용)
- [ ] **GPU 메모리 관리**: 대용량 데이터 처리 방식 (L40S × 3 최적화)
- [ ] **Pinned Inner Buffer**: 메모리 최적화 효과 측정 (L40S 환경)
- [ ] **Zero-copy 데이터 접근**: Arrow 특화 기능 (L40S 최적화)

### 🔍 Phase 4: 인덱스 및 최적화 (예정: 8월 3주차)
- [ ] **BRIN 인덱스**: 블록 레벨 인덱스 활용 (L40S 환경)
- [ ] **GiST 인덱스**: PostGIS와 연동 지리 데이터 (L40S GPU 가속)
- [ ] **인덱스 vs Full Scan**: GPU 가속 효과 비교 (L40S 환경)
- [ ] **파티션 테이블**: 파티셔닝 전략별 성능 (L40S × 3 활용)

### ⚙️ Phase 5: 시스템 튜닝 및 모니터링 (예정: 8월 3주차)
- [ ] **파라미터 최적화** (L40S 환경 전용):
  - `pg_strom.chunk_size` 튜닝 (L40S 44GB 메모리 고려)
  - `pg_strom.max_async_tasks` 조정 (다중 GPU 활용)
  - `pg_strom.gpu_cache_size` 최적화 (L40S × 3 메모리 풀)
  - `shared_buffers` vs GPU memory 밸런싱 (L40S 환경)
- [x] **모니터링 도구**: nvidia-smi, nvtop, 커스텀 스크립트 완성
- [ ] **디버깅 기능**: GPU 커널 소스 분석, 쿼리 실행 계획 최적화

### 🚨 Phase 6: 에러 케이스 및 실운영 시나리오 (예정: 8월 4주차)
- [ ] **에러 상황 테스트** (L40S 환경):
  - GPU 메모리 부족 상황 (44GB 한계 테스트)
  - 커널 컴파일 실패 대응
  - CPU fallback 동작 검증
- [ ] **워크로드 시나리오** (L40S × 3 활용):
  - OLAP vs OLTP 성능 특성
  - 동시 접속 부하 테스트 (다중 GPU 분산)
  - 대용량 배치 처리 (L40S × 3 병렬 처리)
- [ ] **실운영 가이드**: L40S 사용 권장/비권장 케이스

### 🎯 Phase 7: 실시간 대용량 처리 테스트 (예정: 9월 1주차) **[신규]**
- [ ] **실시간 데이터 생성 프로그램**: 지속적 대용량 스트림 생성
- [ ] **스트리밍 처리 성능**: 실시간 집계, 윈도우 분석 (L40S × 3 활용)
- [ ] **배치 vs 스트리밍**: 동일 데이터량 처리 방식 비교 (L40S 환경)
- [ ] **다중 GPU 활용**: L40S × 3개 실시간 부하 분산 최적화
- [ ] **성능 확장성**: 동시 스트림 수 증가에 따른 성능 변화

## 📈 측정 지표 (L40S 환경 반영)

### 기존 지표 (완료된 측정)
- [x] 실행 시간 (GPU ON vs GPU OFF)
- [x] 메모리 사용량 (GPU 메모리 5.3GB 고정 할당 확인)
- [x] GPU 사용률 (모든 테스트에서 0% 확인)
- [x] 처리량 (QPS 기준 성능 분석 완료)

### L40S 환경 특화 지표
- [ ] **다중 GPU 활용률**: L40S × 3개 개별 GPU 사용 패턴
- [ ] **44GB 메모리 활용도**: 대용량 데이터 처리 시 메모리 효율성
- [ ] **GPU 간 부하 분산**: 다중 GPU 워크로드 배분 효과
- [ ] **열 관리**: 장시간 테스트 시 L40S GPU 온도 패턴
- [ ] **전력 효율성**: RTX 3060 vs L40S 전력 소비 대비 성능

### Phase 7 추가 지표 (실시간 처리)
- [ ] **스트리밍 처리량**: 초당 처리 가능한 레코드 수 (L40S × 3)
- [ ] **실시간 지연시간**: 데이터 입력부터 결과 출력까지 시간
- [ ] **확장성**: 동시 스트림 수 증가에 따른 성능 변화
- [ ] **안정성**: 장시간 연속 처리 시 성능 일관성

## 🛠 개선된 테스트 환경 (L40S 반영)

### 현재 완료된 환경
```bash
서버: 192.168.10.1
GPU: NVIDIA L40S × 3개 (44.39GB RAM each) ✅
PG-Strom: v6.0.1 ✅
PostgreSQL: 16.9 ✅
CUDA: 12.9 Runtime ✅
Docker: pgstrom-test 컨테이너 (포트 5432) ✅
```

### 추가 도구 및 설정 (L40S 최적화)
```bash
# L40S 다중 GPU 모니터링
nvidia-smi --query-gpu=index,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw --format=csv -l 1

# PG-Strom L40S 최적화 설정
pg_strom.chunk_size = '128MB'  # L40S 44GB 메모리 고려
pg_strom.max_async_tasks = 12  # L40S × 3 멀티태스킹
pg_strom.gpu_cache_size = '32GB'  # L40S 메모리 풀 최적화

# L40S 환경 디버그 설정
pg_strom.debug_kernel_source = on
pg_strom.debug_force_gpuscan = on  
pg_strom.debug_force_gpujoin = on
```

### 테스트 데이터 확장 (L40S 대용량 처리 고려)
```sql
-- L40S 44GB 메모리 활용 대용량 테스트 테이블
CREATE TABLE l40s_large_test (
    id BIGSERIAL PRIMARY KEY,
    -- 기존 데이터 타입들
    int_col INTEGER,
    bigint_col BIGINT,
    real_col REAL,
    float_col DOUBLE PRECISION,
    numeric_col NUMERIC(15,2),
    text_col TEXT,
    varchar_col VARCHAR(100),
    date_col DATE,
    timestamp_col TIMESTAMP,
    
    -- L40S 대용량 테스트용 추가 컬럼
    json_col JSONB,
    array_col INTEGER[],
    large_text_col TEXT,  -- 최대 1MB 텍스트
    
    -- 실시간 처리 테스트용
    created_at TIMESTAMP DEFAULT NOW(),
    stream_id INTEGER,
    partition_key INTEGER
);

-- L40S × 3 GPU 테스트용 파티션 테이블
CREATE TABLE l40s_partitioned_test (
    LIKE l40s_large_test INCLUDING ALL
) PARTITION BY HASH (partition_key);

-- 3개 파티션 생성 (GPU별 처리)
CREATE TABLE l40s_part_0 PARTITION OF l40s_partitioned_test FOR VALUES WITH (modulus 3, remainder 0);
CREATE TABLE l40s_part_1 PARTITION OF l40s_partitioned_test FOR VALUES WITH (modulus 3, remainder 1);
CREATE TABLE l40s_part_2 PARTITION OF l40s_partitioned_test FOR VALUES WITH (modulus 3, remainder 2);
```

## 🎯 L40S 환경 특화 워크로드 시나리오

### OLAP 워크로드 (L40S × 3 GPU 활용)
```sql
-- 대규모 병렬 집계 (L40S × 3 분산 처리)
WITH gpu_parallel AS (
  SELECT 
    partition_key % 3 as gpu_id,
    DATE_TRUNC('month', timestamp_col) as month,
    COUNT(*) as record_count,
    SUM(bigint_col) as total_sum,
    AVG(real_col) as avg_value
  FROM l40s_partitioned_test 
  WHERE timestamp_col >= '2024-01-01'
  GROUP BY partition_key % 3, DATE_TRUNC('month', timestamp_col)
)
SELECT 
  month,
  SUM(record_count) as total_records,
  SUM(total_sum) as grand_total,
  AVG(avg_value) as overall_avg
FROM gpu_parallel
GROUP BY month
ORDER BY month;

-- 복잡한 조인 + 집계 (L40S 44GB 메모리 활용)
SELECT 
  t1.partition_key,
  t2.stream_id,
  COUNT(*) as join_count,
  SUM(t1.bigint_col * t2.real_col) as weighted_sum
FROM l40s_large_test t1
JOIN l40s_large_test t2 ON t1.id % 1000 = t2.id % 1000
WHERE t1.timestamp_col >= NOW() - INTERVAL '1 hour'
  AND t2.timestamp_col >= NOW() - INTERVAL '1 hour'
GROUP BY t1.partition_key, t2.stream_id
HAVING COUNT(*) > 1000;
```

### 실시간 스트리밍 워크로드 (Phase 7)
```sql
-- 실시간 윈도우 집계 (L40S × 3 실시간 처리)
SELECT 
  stream_id,
  window_start,
  COUNT(*) as events_in_window,
  AVG(real_col) as avg_value,
  MAX(bigint_col) as max_value
FROM (
  SELECT *,
    DATE_TRUNC('minute', created_at) as window_start
  FROM l40s_large_test
  WHERE created_at >= NOW() - INTERVAL '5 minutes'
) windowed_data
GROUP BY stream_id, window_start
ORDER BY window_start DESC, stream_id;

-- 실시간 이상 탐지
SELECT 
  id,
  stream_id,
  real_col,
  AVG(real_col) OVER (
    PARTITION BY stream_id 
    ORDER BY created_at 
    ROWS BETWEEN 100 PRECEDING AND CURRENT ROW
  ) as moving_avg,
  real_col - AVG(real_col) OVER (
    PARTITION BY stream_id 
    ORDER BY created_at 
    ROWS BETWEEN 100 PRECEDING AND CURRENT ROW
  ) as deviation
FROM l40s_large_test
WHERE created_at >= NOW() - INTERVAL '1 minute'
  AND ABS(real_col - AVG(real_col) OVER (
    PARTITION BY stream_id 
    ORDER BY created_at 
    ROWS BETWEEN 100 PRECEDING AND CURRENT ROW
  )) > 2 * STDDEV(real_col) OVER (
    PARTITION BY stream_id 
    ORDER BY created_at 
    ROWS BETWEEN 100 PRECEDING AND CURRENT ROW
  );
```

## 📋 Phase별 상세 우선순위 (업데이트)

### 완료됨 (높은 성과)
1. ✅ **Phase 1-A**: RTX 3060 기본 테스트 (100% 완료)
2. ✅ **Phase 1-B**: L40S 마이그레이션 (100% 완료)
3. ✅ **QPS 성능 분석**: GPU 활용률 0% 원인 규명 완료

### 진행 중 (현재 집중)  
1. 🔄 **Phase 1-C**: 문자열/날짜시간 연산 (20% 진행, 7월 4주차 완료 예정)

### 높은 우선순위 (7-8월)
1. **Phase 2**: 고급 연산 (L40S 최적화, 8월 1주차)
2. **Phase 3**: 스토리지 및 메모리 관리 (L40S 44GB 활용, 8월 2주차)
3. **Phase 5**: 시스템 파라미터 튜닝 (L40S × 3 최적화, 8월 3주차)

### 중간 우선순위 (8월 말)  
1. **Phase 4**: 인덱스 및 최적화 (L40S 환경)
2. **Phase 6**: 에러 케이스 테스트 (L40S × 3 한계 테스트)

### 최고 가치 (9월)
1. **Phase 7**: 실시간 대용량 처리 (L40S × 3 실시간 분산 처리)
   - 실제 운영 시나리오 검증
   - L40S 다중 GPU 실시간 활용 최적화
   - RTX 3060 vs L40S 종합 성능 비교

## ⚠️ L40S 환경 특화 리스크 요소

### 기술적 리스크 (L40S 환경)
1. **다중 GPU 메모리 경합**: L40S × 3개 GPU 간 메모리 할당 충돌
2. **44GB 메모리 단편화**: 장시간 실행 시 대용량 메모리 효율성 저하
3. **GPU 간 동기화 이슈**: 다중 GPU 병렬 처리 시 일관성 문제
4. **L40S 발열 관리**: 연속 고부하 테스트 시 온도 관리

### 대응 방안 (L40S 최적화)
1. **GPU별 워크로드 분리**: 파티션 기반 GPU 할당 전략
2. **메모리 풀 관리**: 정기적 GPU 메모리 정리 및 재할당
3. **단계별 부하 증가**: 1개 → 2개 → 3개 GPU 순차 테스트
4. **열 모니터링**: 연속 테스트 중 GPU 온도 실시간 추적

## 📊 성공 지표 (L40S 반영)

### 정량적 지표 (업데이트)
- [x] **Phase 1-B 완성**: L40S 환경 구축 100% 완료
- [x] **QPS 측정 시스템**: GPU vs CPU 성능 비교 완료
- [x] **GPU 병목 분석**: GPU 활용률 0% 원인 규명 완료
- [ ] **70개 이상** 테스트 케이스 완성 (RTX 3060 + L40S × 3 비교)
- [ ] **전체 지원 데이터 타입** 성능 데이터 수집 (L40S 환경)
- [ ] **7개 Phase** 모든 영역 커버 (L40S 최적화)
- [ ] **15개 이상 시스템 파라미터** L40S 최적화 완료
- [ ] **다중 GPU 활용** 최적화 전략 수립

### 정성적 지표 (L40S 반영)
- [x] **안정적인 L40S 운영 환경** 확보 완료
- [x] **GPU 성능 병목지점** 식별 및 분석 완료
- [ ] **RTX 3060 vs L40S × 3** 종합 성능 특성 비교
- [ ] **L40S 다중 GPU 활용** 최적화 가이드라인 제시
- [ ] **실시간 대용량 처리** 시나리오별 최적화 전략
- [ ] **GPU 등급별 워크로드** 배치 전략 수립

---

## 🔄 v2.0 → v3.0 주요 업데이트

1. **✅ 완료 상태 반영**: Phase 1-A (RTX 3060) 및 Phase 1-B (L40S 마이그레이션) 완료
2. **🔧 L40S 환경 특화**: 44GB 메모리, 다중 GPU 활용 최적화 반영
3. **📊 실제 측정 데이터**: QPS 성능 분석, GPU 활용률 0% 원인 규명 반영
4. **🚀 Phase 7 강화**: 실시간 대용량 처리 테스트 구체화 (L40S × 3 활용)
5. **⚙️ 시스템 최적화**: L40S 전용 파라미터 튜닝 및 모니터링 전략
6. **📈 측정 지표 확장**: 70개 이상 테스트 케이스, 다중 GPU 활용 지표
7. **🎯 현실적 목표**: 완료된 작업과 진행 중인 작업 명확히 구분

*최종 업데이트: 2025-07-17 (v3.0)*
*현재 상태: Phase 1-B 완료, Phase 1-C 진행 중 (20%)*
*다음 목표: Phase 1-C 완성 (7월 4주차)*