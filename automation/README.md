# PG-Strom GPU 가속 성능 분석 자동화 시스템

**작성자**: 신재솔  
**버전**: 2.0 (완전 자동화)  
**작성일**: 2025-07-10

## 개요

이 시스템은 PG-Strom을 사용한 PostgreSQL GPU 가속 성능을 자동으로 분석하는 완전 자동화된 도구입니다. 환경 설정부터 실험 실행, 결과 분석, 보고서 생성까지 모든 과정을 원클릭으로 수행할 수 있습니다.

## 주요 기능

### 🚀 완전 자동화
- 원클릭 실행으로 모든 과정 자동화
- 환경 설정부터 보고서 생성까지 무인 실행
- 진행률 표시 및 상태 모니터링

### 📊 종합 성능 분석
- GPU vs CPU 성능 비교
- 6가지 다양한 테스트 케이스
- 각 테스트 8회 반복으로 통계적 신뢰성 확보
- 평균, 표준편차, 최소/최대값 통계 분석
- 실제 GPU 처리량 분석
- 자동 보고서 생성

### 📈 다양한 출력 형식
- 마크다운 보고서 (performance_report.md)
- JSON 데이터 (experiment_summary.json)
- 빠른 요약 (quick_summary.txt)
- CSV 원본 데이터 (summary.csv)

## 시스템 요구사항

### 필수 요구사항
- Linux 운영체제
- NVIDIA GPU (CUDA 지원)
- Docker 및 Docker Compose
- NVIDIA Container Toolkit
- Python 3.x
- 최소 30GB 디스크 공간

### 권장 사양
- NVIDIA GeForce RTX 3060 이상
- 16GB 이상 RAM
- 50GB 이상 디스크 공간

## 설치 및 실행

### 1. 빠른 시작 (완전 자동화)

```bash
# 프로젝트 클론
git clone <repository-url>
cd pgstrom

# 완전 자동화 실행 (3-4시간 소요, 8회 반복)
./automation/script/run_complete_automation.sh
```

### 2. 단계별 실행

```bash
# 1단계: 환경 설정
./automation/script/setup_pgstrom_experiment.sh

# 2단계: 테스트 데이터 생성
./automation/script/create_test_data.sh

# 3단계: 성능 실험 실행
./automation/script/run_experiments.sh

# 4단계: 보고서 생성 (선택사항)
python3 automation/script/generate_report.py experiment_results/results_YYYYMMDD_HHMMSS
```

## 스크립트 구조

```
automation/
├── script/
│   ├── run_complete_automation.sh     # 완전 자동화 마스터 스크립트
│   ├── setup_pgstrom_experiment.sh    # 환경 설정
│   ├── create_test_data.sh            # 테스트 데이터 생성
│   ├── run_experiments.sh             # 성능 실험 실행
│   ├── generate_report.py             # 보고서 생성
│   └── run_full_experiment.sh         # 기존 전체 실행 스크립트
└── README.md                          # 이 파일
```

## 실험 테스트 케이스

### 1. Simple Scan
- 2,500만 행 단순 스캔
- 집계 함수 테스트

### 2. Subset Join
- 2,500만 행 × 100만 행 조인
- 부분집합 조인 성능

### 3. Large Join
- 1,000만 행 × 1,000만 행 조인
- 대용량 조인 성능

### 4. Simple Math
- 단순 수학 함수 (pow, sin)
- 5,000만 행 처리

### 5. Complex Math
- 복합 수학 함수 (sqrt, log, exp, atan2)
- 고급 연산 성능

### 6. Simple Ops
- 기본 사칙연산
- 단순 연산 성능

## 결과 분석

### 성능 지표
- **실행 시간**: 밀리초 단위 측정 (8회 반복)
- **통계 분석**: 평균, 표준편차, 최소/최대값
- **GPU 처리량**: 실제 GPU에서 처리된 행 수
- **성능 향상률**: CPU 대비 GPU 성능 개선율

### 출력 파일
- `performance_report.md`: 상세 분석 보고서
- `quick_summary.txt`: 빠른 결과 요약
- `experiment_summary.json`: 구조화된 데이터
- `summary.csv`: 원본 측정 데이터
- `automation_final_report.txt`: 최종 종합 보고서

## 문제 해결

### 일반적인 문제

1. **Docker 권한 오류**
   ```bash
   sudo usermod -aG docker $USER
   # 로그아웃 후 다시 로그인
   ```

2. **NVIDIA Container Toolkit 설치**
   ```bash
   # Ubuntu/Debian
   sudo apt-get update
   sudo apt-get install nvidia-container-toolkit
   sudo systemctl restart docker
   ```

3. **디스크 공간 부족**
   ```bash
   # 불필요한 Docker 이미지 정리
   docker system prune -a
   ```

4. **Python 모듈 오류**
   ```bash
   # 필요한 경우 (표준 라이브러리만 사용)
   python3 -m pip install --upgrade pip
   ```

### 로그 확인

```bash
# Docker 컨테이너 로그
docker logs pgstrom-test

# 실험 결과 디렉토리
ls -la experiment_results/results_*/

# 시스템 정보
cat experiment_results/results_*/system_info.txt
```

## 고급 사용법

### 환경변수 커스터마이징

```bash
# 프로젝트 루트 변경
export PROJECT_ROOT="/custom/path"

# 실험 결과 디렉토리 변경
export EXPERIMENT_DIR="/custom/results"

# 실험 설정 변경
export REPEAT_COUNT=16          # 반복 횟수 (기본: 8)
export SLEEP_BETWEEN_RUNS=2     # 실행 간 대기 시간 초 (기본: 1)
export CLEAR_CACHE=true         # 캐시 클리어 여부 (기본: true)
```

### 실험 설정 예시

```bash
# 빠른 테스트 (3회 반복)
export REPEAT_COUNT=3
./automation/script/run_complete_automation.sh

# 고정밀 테스트 (20회 반복, 3초 간격)
export REPEAT_COUNT=20
export SLEEP_BETWEEN_RUNS=3
./automation/script/run_complete_automation.sh

# 캐시 영향 테스트 (캐시 클리어 비활성화)
export CLEAR_CACHE=false
./automation/script/run_complete_automation.sh
```

### 테스트 케이스 수정

`run_experiments.sh` 파일을 편집하여 SQL 쿼리나 테스트 조건을 변경할 수 있습니다.

### 보고서 템플릿 수정

`generate_report.py` 파일을 편집하여 보고서 형식을 커스터마이징할 수 있습니다.

## 성능 최적화 팁

### GPU 최적화
- `shared_buffers` 설정 조정
- `work_mem` 크기 최적화
- `pg_strom.chunk_size` 튜닝

### 시스템 최적화
- SSD 사용 권장
- 충분한 RAM 확보
- CPU 코어 수 고려

## 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.

## 기여하기

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 지원

문제가 발생하거나 질문이 있는 경우:
- Issues 탭에서 문제 보고
- 로그 파일과 함께 상세한 설명 제공
- 시스템 환경 정보 포함

---

**참고**: 이 시스템은 실험 및 연구 목적으로 설계되었습니다. 프로덕션 환경에서 사용하기 전에 충분한 테스트를 수행하시기 바랍니다. 