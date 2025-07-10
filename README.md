# PG-Strom Performance Analysis

PG-Strom GPU 가속 PostgreSQL 성능 분석 및 자동화 시스템

## 개요

이 프로젝트는 PG-Strom 확장을 사용한 PostgreSQL의 GPU 가속 성능을 분석하고 벤치마킹하는 자동화된 시스템입니다.

## 구조

```
├── automation/          # 자동화 스크립트
│   └── script/         # 성능 테스트 및 분석 스크립트
├── experiment_notes/    # 실험 노트 및 분석 문서
├── experiment_results/  # 실험 결과 데이터
└── pg-strom-docker/    # Docker 환경 설정
```

## 주요 기능

- **자동화된 성능 테스트**: GPU 가속 vs CPU 기반 쿼리 성능 비교
- **결과 분석**: 자동화된 성능 보고서 생성
- **Docker 환경**: 재현 가능한 테스트 환경 제공
- **벤치마킹**: 다양한 워크로드에 대한 성능 측정

## 빠른 시작

### 전체 자동화 실행
```bash
cd automation/script
./run_full_automation.sh
```

### 개별 성능 테스트
```bash
./run_performance_tests.sh
```

### 결과 분석
```bash
./analyze_simple.sh
```

## 요구사항

- Docker & Docker Compose
- NVIDIA GPU (CUDA 지원)
- nvidia-container-toolkit

## 결과

실험 결과는 `experiment_results/` 디렉터리에 타임스탬프별로 저장되며, 성능 보고서와 CSV 요약이 자동 생성됩니다. 