# PG-Strom GPU 가속 PostgreSQL 성능 분석 프로젝트

PG-Strom 확장을 활용한 PostgreSQL GPU 가속 성능 분석 및 벤치마킹 시스템

## 📋 프로젝트 개요

이 프로젝트는 PG-Strom을 통한 PostgreSQL의 GPU 가속 효과를 체계적으로 분석하고, 실제 비즈니스 환경에서의 적용 가능성을 검증하는 것을 목표로 합니다.

- **기간**: 2025년 7월 - 10월 (12주)
- **목표**: 7개 Phase, 35+ 테스트 케이스 완성
- **범위**: GPUDirect 제외한 PG-Strom 전 기능 검증

## 🏗 프로젝트 구조

```
├── automation/              # 자동화 테스트 스크립트
│   ├── script/              # 성능 테스트 실행 스크립트
│   └── README.md            # 자동화 도구 사용법
├── experiment_notes/        # 실험 계획 및 분석 문서
│   ├── PG-Strom_Comprehensive_Test_Plan.md  # 종합 테스트 계획
│   ├── Project_Roadmap.md                   # 프로젝트 로드맵
│   ├── Phase_Implementation_Guide.md        # Phase별 구현 가이드
│   ├── Server_Migration_Guide.md            # 서버 이전 가이드
│   └── [기타 실험 노트들]
├── experiment_results/      # 실험 결과 데이터
│   ├── results_[timestamp]/ # 타임스탬프별 결과 저장
│   └── system_info.txt      # 시스템 환경 정보
├── pg-strom-docker/         # Docker 환경 설정
└── README.md               # 이 문서
```

## 🎯 테스트 계획 개요

### Phase 1: 기본 GPU 연산 (진행 중)
- [x] SCAN 연산 성능 테스트
- [x] JOIN 연산 성능 테스트  
- [x] 수학 연산 성능 테스트
- [ ] 문자열 연산 테스트
- [ ] 날짜/시간 연산 테스트

### Phase 2-6: 고급 기능 테스트 (예정)
- GROUP BY, AGGREGATE 함수
- Arrow 스토리지 최적화
- 인덱스 활용 (BRIN, GiST)
- 시스템 파라미터 튜닝
- 에러 케이스 및 실운영 시나리오

### Phase 7: 실제 유즈케이스 통합 테스트 (예정)
- 금융 서비스 시나리오 (고빈도 거래 분석)
- 전자상거래 시나리오 (실시간 추천 시스템)
- IoT/텔레콤 시나리오 (센서 데이터 처리)
- 소셜미디어 시나리오 (대용량 JSON 분석)

## 🚀 빠른 시작

### 전제 조건
- Docker & Docker Compose
- NVIDIA GPU (CUDA 지원)
- nvidia-container-toolkit
- Git, Python 3.8+

### 환경 구축
```bash
# 1. 저장소 클론
git clone https://github.com/ysys143/pgstrom.git
cd pgstrom

# 2. Docker 환경 구축
cd pg-strom-docker
docker-compose up -d

# 3. GPU 인식 확인
docker-compose exec pgstrom psql -U postgres -c "SELECT * FROM pgstrom.device_info;"
```

### 기본 테스트 실행
```bash
# 자동화 스크립트로 기본 성능 테스트 실행
cd automation/script
./run_performance_tests.sh

# 결과 분석
./analyze_simple.sh
```

## 📊 현재 진행 상황

### ✅ 완료된 작업
- **Docker 환경 구축**: PG-Strom 테스트 환경 완료
- **기본 성능 테스트**: SCAN, JOIN, 수학 연산 테스트 완료
- **자동화 도구**: 기본 성능 테스트 자동화 완료
- **GitHub 설정**: 저장소 생성 및 문서화 완료
- **종합 계획 수립**: 7개 Phase 상세 계획 완성

### 🔄 진행 중인 작업
- **Phase 1 완성**: 문자열, 날짜/시간 연산 테스트 추가
- **서버 이전 준비**: 새 서버 환경 구축 준비

### ⏳ 예정된 작업
- **Phase 2-7**: 고급 기능 및 실제 유즈케이스 테스트
- **성능 분석 도구**: Python 기반 종합 분석 도구 개발
- **최종 보고서**: 종합 성능 분석 보고서 작성

## 🔧 기술 스택

### 핵심 기술
- **PostgreSQL 16** + **PG-Strom 6.0.2**
- **Docker** + **Docker Compose**
- **NVIDIA GPU** + **CUDA 12.2**

### 개발 도구
- **Bash Scripts**: 테스트 자동화
- **Python 3**: 결과 분석 및 시각화
- **Git**: 버전 관리 및 협업

### 계획된 추가 기술
- **Apache Arrow**: 컬럼형 스토리지 테스트
- **PostGIS**: 지리정보 데이터 처리
- **GPU 모니터링**: nvidia-smi, nvtop, gpustat

## 📈 주요 성과 (중간 결과)

### 성능 개선 확인 사례
- **단순 스캔 + 수학 연산**: GPU 31.4% 성능 향상
- **복잡한 수학 함수**: pow, sin 등에서 GPU 효과 확인
- **대용량 데이터 처리**: 5천만 행 데이터 처리 가능

### 제한사항 발견
- **복잡한 조인**: 특정 조건에서 CPU가 더 효율적
- **GPU 메모리 제약**: 대용량 데이터 시 메모리 관리 중요
- **워크로드 특성**: OLAP 친화적, OLTP 제한적

## 📚 문서

### 핵심 문서
- [종합 테스트 계획](experiment_notes/PG-Strom_Comprehensive_Test_Plan.md)
- [프로젝트 로드맵](experiment_notes/Project_Roadmap.md)
- [Phase별 구현 가이드](experiment_notes/Phase_Implementation_Guide.md)
- [서버 이전 가이드](experiment_notes/Server_Migration_Guide.md)

### 실험 결과
- [완전 성능 분석 보고서](experiment_notes/PG-Strom_Complete_Performance_Analysis.md)
- [Docker 테스트 로그](experiment_notes/pg-strom-docker-test-log.md)
- 결과 데이터: `experiment_results/` 디렉터리

## 🔗 관련 링크

- **GitHub 저장소**: https://github.com/ysys143/pgstrom
- **PG-Strom 공식 문서**: https://heterodb.github.io/pg-strom/
- **참고 Docker 환경**: https://github.com/ytooyama/pg-strom-docker

## 👥 기여자

- **재솔님**: 프로젝트 리더, 성능 분석 및 테스트 설계

---

*최종 업데이트: 2025-07-10*  
*현재 진행률: Phase 1 (70% 완료)* 