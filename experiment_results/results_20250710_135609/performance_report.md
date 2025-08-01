# PG-Strom GPU 가속 성능 분석 보고서

**작성자**: 신재솔  
**작성일**: 2025-07-10 13:57:05  
**실험 환경**: NVIDIA GeForce RTX 3060

## 1. 실험 개요

본 실험은 PG-Strom을 사용한 PostgreSQL GPU 가속 성능을 분석하기 위해 수행되었습니다.

### 실험 환경
- GPU: NVIDIA GeForce RTX 3060
- GPU 메모리: 812MB
- 실험 일시: 2025-07-10 13:57:05

## 2. 실험 결과

### 성능 비교 결과

| 테스트 케이스 | GPU 활성화 (ms) | GPU 비활성화 (ms) | 성능 향상 | 우수한 방식 |
|---------------|----------------|------------------|-----------|------------|
| Simple Scan | 969.5 | 840.6 | -15.3% | CPU |
| Subset Join | 916.4 | 2348.6 | 61.0% | GPU |
| Large Join | 6367.0 | 3245.2 | -96.2% | CPU |
| Simple Math | 3457.4 | 2171.6 | -59.2% | CPU |
| Complex Math | 2674.5 | 3172.3 | 15.7% | GPU |
| Simple Ops | 750.3 | 1544.3 | 51.4% | GPU |

## 3. 상세 분석

### GPU 활용도 분석
- **Subset Join**: GPU 처리량 25,000,000건 (활용됨)
- **Simple Scan**: GPU 처리량 25,000,000건 (활용됨)
- **Simple Math**: GPU 처리량 50,000,000건 (활용됨)
- **Large Join**: GPU 처리량 10,000,000건 (활용됨)
- **Complex Math**: GPU 처리량 50,000,000건 (활용됨)
- **Simple Ops**: GPU 처리량 50,000,000건 (활용됨)

## 4. 결론 및 권장사항

### 주요 발견사항
- 총 6개 테스트 중 GPU가 3개, CPU가 3개 테스트에서 우수한 성능을 보였습니다.
- GPU 가속이 가장 효과적인 테스트: Subset Join (61.0% 향상)

### 권장사항
- GPU 가속은 대용량 데이터 처리와 수학 연산에서 효과적입니다.
- 단순 조인 작업의 경우 CPU가 더 효율적일 수 있습니다.
- 실제 워크로드에 따라 GPU 활성화 여부를 결정하는 것이 중요합니다.

## 5. 기술적 세부사항

### 실험 설정
- 테스트 데이터: 최대 5,000만 행
- 측정 방법: PostgreSQL EXPLAIN ANALYZE
- 반복 횟수: 각 테스트 GPU ON/OFF 각 1회

### 측정 지표
- 실행 시간 (ms)
- GPU 처리량 (exec count)
- 메모리 사용량

---
*이 보고서는 PG-Strom 자동화 시스템에 의해 생성되었습니다.*
