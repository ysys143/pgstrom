# PG-Strom GPU 가속 성능 분석 실험 자동화

재솔님과 함께 작성한 PG-Strom 실험 자동화 스크립트입니다.

## 🎯 목적

다른 서버에서 PG-Strom 실험을 동일하게 재현할 수 있도록 완전 자동화된 환경을 제공합니다.

## 📋 시스템 요구사항

### 필수 요구사항
- **NVIDIA GPU**: RTX 3060 이상 권장
- **CUDA**: 12.2 이상
- **Docker**: 최신 버전
- **NVIDIA Container Toolkit**: 설치 및 구성 완료
- **메모리**: 8GB 이상 (16GB 권장)
- **디스크**: 50GB 이상 여유 공간

### 확인 명령어
```bash
# GPU 확인
nvidia-smi

# Docker 확인
docker --version

# NVIDIA Container Toolkit 확인
docker info | grep -i nvidia
```

## 🚀 사용법

### 1. 전체 실험 실행 (원클릭)
```bash
# 모든 단계를 자동으로 실행
./run_full_experiment.sh
```

### 2. 단계별 실행

#### 2.1 환경 설정
```bash
# 1단계: 기본 환경 설정 (Docker 이미지 빌드, 컨테이너 실행, PostgreSQL 초기화)
./setup_pgstrom_experiment.sh
```

#### 2.2 테스트 데이터 생성
```bash
# 2단계: 테스트 데이터 생성 (약 10-20분 소요)
./create_test_data.sh
```

#### 2.3 실험 실행
```bash
# 3단계: 성능 실험 실행 (약 30-60분 소요)
./run_experiments.sh
```

## 📊 실험 구성

### 테스트 데이터
| 테이블 | 행 수 | 크기 | 용도 |
|--------|-------|------|------|
| t_test | 2,500만 | ~1GB | 기본 스캔 테스트 |
| t_join | 100만 | ~42MB | 조인 테스트 |
| t_large1 | 1,000만 | ~400MB | 대용량 독립 조인 |
| t_large2 | 1,000만 | ~400MB | 대용량 독립 조인 |
| t_huge | 5,000만 | ~1.7GB | 초대용량 연산 |

### 실험 시나리오
1. **단순 스캔**: 대용량 테이블 스캔 + 수학 연산
2. **부분집합 조인**: 2,500만 × 100만 행 조인
3. **대용량 독립 조인**: 1,000만 × 1,000만 행 조인
4. **단순 수학 함수**: pow, sin 함수 테스트
5. **복합 수학 함수**: sqrt, log, exp, atan2 조합
6. **단순 연산**: 기본 사칙연산 테스트

## 📁 결과 파일 구조

```
experiment_results/
├── results_YYYYMMDD_HHMMSS/
│   ├── summary.csv              # 전체 결과 요약
│   ├── analysis.txt             # 자동 분석 결과
│   ├── system_info.txt          # 시스템 정보
│   ├── simple_scan_on.txt       # 개별 테스트 결과
│   ├── simple_scan_off.txt
│   ├── subset_join_on.txt
│   ├── subset_join_off.txt
│   └── ...
└── system_info.txt              # 기본 시스템 정보
```

## 🔧 설정 변경

### 컨테이너 설정 변경
`setup_pgstrom_experiment.sh`에서 다음 변수 수정:
```bash
DOCKER_IMAGE="mypg16-rocky8:latest"
CONTAINER_NAME="pgstrom-test"
WORK_DIR="/home/jaesol/Projects/pgstrom"
```

### 테스트 데이터 크기 조정
`create_test_data.sh`에서 행 수 변경:
```bash
# 예: 1,000만 행으로 변경
FROM generate_series(1, 10000000) AS id
```

### PostgreSQL 설정 조정
`setup_pgstrom_experiment.sh`의 PostgreSQL 설정 부분:
```bash
sed -i 's/shared_buffers = 128MB/shared_buffers = 4GB/g' postgresql.conf
sed -i 's/#work_mem = 4MB/work_mem = 1GB/g' postgresql.conf
```

## 🐛 문제 해결

### 1. 컨테이너 실행 실패
```bash
# 컨테이너 상태 확인
docker ps -a

# 로그 확인
docker logs pgstrom-test

# 컨테이너 재시작
docker restart pgstrom-test
```

### 2. GPU 인식 실패
```bash
# NVIDIA Container Toolkit 재설정
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### 3. 메모리 부족
```bash
# 컨테이너 메모리 설정 변경
docker run --memory=8gb --shm-size=8gb ...
```

### 4. 실험 중단 시
```bash
# 컨테이너 정리
docker stop pgstrom-test
docker rm pgstrom-test

# 처음부터 다시 시작
./setup_pgstrom_experiment.sh
```

## 📈 결과 분석

### 자동 분석 결과 확인
```bash
# 최신 결과 확인
ls -la experiment_results/results_*/

# 분석 결과 보기
cat experiment_results/results_YYYYMMDD_HHMMSS/analysis.txt
```

### 수동 분석
```bash
# CSV 파일로 분석
python3 -c "
import pandas as pd
df = pd.read_csv('experiment_results/results_YYYYMMDD_HHMMSS/summary.csv')
print(df.groupby('test_name').agg({'execution_time_ms': ['min', 'max', 'mean']}))"
```

## 🔄 다른 서버에서 실행

### 1. 스크립트 복사
```bash
# 전체 디렉토리 복사
scp -r /home/jaesol/Projects/pgstrom user@target-server:~/
```

### 2. 경로 수정
```bash
# setup_pgstrom_experiment.sh의 WORK_DIR 변경
WORK_DIR="/home/user/pgstrom"
```

### 3. 실행
```bash
cd ~/pgstrom
./run_full_experiment.sh
```

## 📝 실험 로그

모든 실행 과정은 자동으로 로그가 기록됩니다:
- 컨테이너 로그: `docker logs pgstrom-test`
- 실험 로그: `experiment_results/results_*/`
- 시스템 로그: `journalctl -u docker`

## 🎯 성능 최적화 팁

1. **SSD 사용**: 가능한 한 빠른 스토리지 사용
2. **메모리 할당**: 시스템 메모리의 50% 이상 할당
3. **GPU 온도**: 실험 중 GPU 온도 모니터링
4. **백그라운드 프로세스**: 다른 GPU 사용 프로세스 종료

## 🤝 기여

실험 결과나 개선사항이 있으면 언제든 공유해주세요!

---

**작성자**: 재솔님과 함께  
**최종 수정**: 2025-01-10  
**버전**: 1.0 