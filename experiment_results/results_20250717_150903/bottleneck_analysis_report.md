# PG-Strom GPU 병목지점 정량 분석 리포트

**분석 일시**: Thu Jul 17 03:34:18 PM KST 2025
**테스트 세션**: test_20250717_150903

## 📊 테스트 개요

### 시스템 환경
- GPU: GPU 0: NVIDIA L40S (UUID: GPU-69940b65-67e5-b061-bf93-4d5647ebc58b)
- CUDA: 12.9
- 컨테이너: pgstrom-test
- 데이터베이스: testdb

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

- **computation_qps_basic**: 최대 GPU 활용률  46 %%, 최대 메모리  5815 MiBMiB, 평균 온도 46.0386°C
- **computation_qps_complex**: 최대 GPU 활용률  33 %%, 최대 메모리  5831 MiBMiB, 평균 온도 46.134°C
- **computation_qps_extreme**: 최대 GPU 활용률  63 %%, 최대 메모리  5799 MiBMiB, 평균 온도 45.6314°C
- **computation_qps_medium**: 최대 GPU 활용률  70 %%, 최대 메모리  5767 MiBMiB, 평균 온도 46.0617°C
- **extreme_qps_stress**: 최대 GPU 활용률  53 %%, 최대 메모리  5655 MiBMiB, 평균 온도 45.3846°C
- **groupby_qps_10000**: 최대 GPU 활용률  82 %%, 최대 메모리  4783 MiBMiB, 평균 온도 45.7356°C
- **groupby_qps_1000**: 최대 GPU 활용률  0 %%, 최대 메모리  511 MiBMiB, 평균 온도 45.3136°C
- **groupby_qps_100**: 최대 GPU 활용률  86 %%, 최대 메모리  6567 MiBMiB, 평균 온도 45.6082°C
- **memory_qps_10M**: 최대 GPU 활용률  50 %%, 최대 메모리  5823 MiBMiB, 평균 온도 44.7927°C
- **memory_qps_1M**: 최대 GPU 활용률  89 %%, 최대 메모리  5751 MiBMiB, 평균 온도 44.2937°C
- **memory_qps_50M**: 최대 GPU 활용률  66 %%, 최대 메모리  5791 MiBMiB, 평균 온도 45.1667°C
- **memory_scaling_16**: 최대 GPU 활용률  91 %%, 최대 메모리  5751 MiBMiB, 평균 온도 46.0284°C
- **memory_scaling_2**: 최대 GPU 활용률  64 %%, 최대 메모리  5743 MiBMiB, 평균 온도 45.6316°C
- **memory_scaling_4**: 최대 GPU 활용률  34 %%, 최대 메모리  5815 MiBMiB, 평균 온도 45.6751°C
- **memory_scaling_8**: 최대 GPU 활용률  55 %%, 최대 메모리  5799 MiBMiB, 평균 온도 45.8954°C

### 성능 비교 결과

#### computation_qps_basic
- 실행 시간 데이터 없음 또는 불완전

#### computation_qps_basic_qps_cpu
- 실행 시간 데이터 없음 또는 불완전

#### computation_qps_basic_qps_gpu
- 실행 시간 데이터 없음 또는 불완전

#### computation_qps_complex
- 실행 시간 데이터 없음 또는 불완전

#### computation_qps_complex_qps_cpu
- 실행 시간 데이터 없음 또는 불완전

#### computation_qps_complex_qps_gpu
- 실행 시간 데이터 없음 또는 불완전

#### computation_qps_extreme
- 실행 시간 데이터 없음 또는 불완전

#### computation_qps_extreme_qps_cpu
- 실행 시간 데이터 없음 또는 불완전

#### computation_qps_extreme_qps_gpu
- 실행 시간 데이터 없음 또는 불완전

#### computation_qps_medium
- 실행 시간 데이터 없음 또는 불완전

#### computation_qps_medium_qps_cpu
- 실행 시간 데이터 없음 또는 불완전

#### computation_qps_medium_qps_gpu
- 실행 시간 데이터 없음 또는 불완전

#### extreme_qps_stress
- 실행 시간 데이터 없음 또는 불완전

#### extreme_qps_stress_qps_cpu
- 실행 시간 데이터 없음 또는 불완전

#### extreme_qps_stress_qps_gpu
- 실행 시간 데이터 없음 또는 불완전

#### groupby_qps_10000
- 실행 시간 데이터 없음 또는 불완전

#### groupby_qps_10000_qps_cpu
- 실행 시간 데이터 없음 또는 불완전

#### groupby_qps_10000_qps_gpu
- 실행 시간 데이터 없음 또는 불완전

#### groupby_qps_1000
- 실행 시간 데이터 없음 또는 불완전

#### groupby_qps_1000_qps_cpu
- 실행 시간 데이터 없음 또는 불완전

#### groupby_qps_1000_qps_gpu
- 실행 시간 데이터 없음 또는 불완전

#### groupby_qps_100
- 실행 시간 데이터 없음 또는 불완전

#### groupby_qps_100_qps_cpu
- 실행 시간 데이터 없음 또는 불완전

#### groupby_qps_100_qps_gpu
- 실행 시간 데이터 없음 또는 불완전

#### memory_qps_10M
- 실행 시간 데이터 없음 또는 불완전

#### memory_qps_10M_qps_cpu
- 실행 시간 데이터 없음 또는 불완전

#### memory_qps_10M_qps_gpu
- 실행 시간 데이터 없음 또는 불완전

#### memory_qps_1M
- 실행 시간 데이터 없음 또는 불완전

#### memory_qps_1M_qps_cpu
- 실행 시간 데이터 없음 또는 불완전

#### memory_qps_1M_qps_gpu
- 실행 시간 데이터 없음 또는 불완전

#### memory_qps_50M
- 실행 시간 데이터 없음 또는 불완전

#### memory_qps_50M_qps_cpu
- 실행 시간 데이터 없음 또는 불완전

#### memory_qps_50M_qps_gpu
- 실행 시간 데이터 없음 또는 불완전

#### memory_scaling_16
- 실행 시간 데이터 없음 또는 불완전

#### memory_scaling_16_qps_cpu
- 실행 시간 데이터 없음 또는 불완전

#### memory_scaling_16_qps_gpu
- 실행 시간 데이터 없음 또는 불완전

#### memory_scaling_2
- 실행 시간 데이터 없음 또는 불완전

#### memory_scaling_2_qps_cpu
- 실행 시간 데이터 없음 또는 불완전

#### memory_scaling_2_qps_gpu
- 실행 시간 데이터 없음 또는 불완전

#### memory_scaling_4
- 실행 시간 데이터 없음 또는 불완전

#### memory_scaling_4_qps_cpu
- 실행 시간 데이터 없음 또는 불완전

#### memory_scaling_4_qps_gpu
- 실행 시간 데이터 없음 또는 불완전

#### memory_scaling_8
- 실행 시간 데이터 없음 또는 불완전

#### memory_scaling_8_qps_cpu
- 실행 시간 데이터 없음 또는 불완전

#### memory_scaling_8_qps_gpu
- 실행 시간 데이터 없음 또는 불완전


## 📋 상세 결과 파일

### GPU 모니터링 데이터
- computation_qps_basic_gpu.csv
- computation_qps_complex_gpu.csv
- computation_qps_extreme_gpu.csv
- computation_qps_medium_gpu.csv
- extreme_qps_stress_gpu.csv
- groupby_qps_10000_gpu.csv
- groupby_qps_1000_gpu.csv
- groupby_qps_100_gpu.csv
- memory_qps_10M_gpu.csv
- memory_qps_1M_gpu.csv
- memory_qps_50M_gpu.csv
- memory_scaling_16_gpu.csv
- memory_scaling_2_gpu.csv
- memory_scaling_4_gpu.csv
- memory_scaling_8_gpu.csv

### 쿼리 실행 로그
- computation_qps_basic.log
- computation_qps_basic_qps_cpu.log
- computation_qps_basic_qps_gpu.log
- computation_qps_complex.log
- computation_qps_complex_qps_cpu.log
- computation_qps_complex_qps_gpu.log
- computation_qps_extreme.log
- computation_qps_extreme_qps_cpu.log
- computation_qps_extreme_qps_gpu.log
- computation_qps_medium.log
- computation_qps_medium_qps_cpu.log
- computation_qps_medium_qps_gpu.log
- extreme_qps_stress.log
- extreme_qps_stress_qps_cpu.log
- extreme_qps_stress_qps_gpu.log
- groupby_qps_10000.log
- groupby_qps_10000_qps_cpu.log
- groupby_qps_10000_qps_gpu.log
- groupby_qps_1000.log
- groupby_qps_1000_qps_cpu.log
- groupby_qps_1000_qps_gpu.log
- groupby_qps_100.log
- groupby_qps_100_qps_cpu.log
- groupby_qps_100_qps_gpu.log
- memory_qps_10M.log
- memory_qps_10M_qps_cpu.log
- memory_qps_10M_qps_gpu.log
- memory_qps_1M.log
- memory_qps_1M_qps_cpu.log
- memory_qps_1M_qps_gpu.log
- memory_qps_50M.log
- memory_qps_50M_qps_cpu.log
- memory_qps_50M_qps_gpu.log
- memory_scaling_16.log
- memory_scaling_16_qps_cpu.log
- memory_scaling_16_qps_gpu.log
- memory_scaling_2.log
- memory_scaling_2_qps_cpu.log
- memory_scaling_2_qps_gpu.log
- memory_scaling_4.log
- memory_scaling_4_qps_cpu.log
- memory_scaling_4_qps_gpu.log
- memory_scaling_8.log
- memory_scaling_8_qps_cpu.log
- memory_scaling_8_qps_gpu.log

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
*분석 완료: Thu Jul 17 03:34:19 PM KST 2025*
