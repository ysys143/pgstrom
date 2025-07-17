# PG-Strom 테스트 환경 서버 이전 가이드

## 📋 개요
- **현재 서버**: 192.168.10.1 (PG-Strom v6.0.1 완전 구축 완료) **[업데이트]**
- **이전 대상**: 새로운 서버 (필요시 이전)
- **목적**: 성공적으로 구축된 PG-Strom 환경을 새 서버에서 재현
- **현재 상태**: **환경 구축 100% 완료, GPU 가속 쿼리 정상 실행** **[신규]**

## 🎯 구축 완료된 환경 정보 **[업데이트]**

### 성공적으로 구축된 환경
```bash
서버: 192.168.10.1
OS: Rocky Linux 8 (Docker 컨테이너)
GPU: NVIDIA L40S × 3개 (44.39GB RAM each)
PG-Strom: v6.0.1
PostgreSQL: 16.9  
CUDA: 12.9 Runtime
Docker: pgstrom-test 컨테이너 (포트 5432)
상태: GPU 가속 쿼리 정상 실행 확인
GPU Compute Capability: 8.9
```

### 검증된 구성 요소
- [x] **Docker 환경**: `docker.io/nvidia/cuda:12.9.1-devel-rockylinux8` 기반
- [x] **PG-Strom 빌드**: 소스 컴파일 (v6.0 브랜치)
- [x] **PostgreSQL**: 16.9 (PGDG 저장소)
- [x] **NVIDIA Container Toolkit**: GPU 액세스 정상
- [x] **GPU 가속**: Custom Scan (GpuPreAgg) 실행 확인

## 🛠 성공적인 구축 절차 **[실제 경험 기반]**

### Step 1: 환경 요구사항 검증
```bash
# GPU 드라이버 확인
nvidia-smi
# 출력 예시: CUDA Version: 12.9, GPU 0: NVIDIA L40S

# NVIDIA Container Toolkit 테스트
docker run --rm --gpus all docker.io/nvidia/cuda:12.9.1-devel-rockylinux8 nvidia-smi
```

### Step 2: 자동화 스크립트 실행 **[검증된 방법]**
```bash
# 저장소 클론
git clone https://github.com/ysys143/pgstrom.git
cd pgstrom

# 자동 환경 구축 스크립트 실행
./automation/script/setup_pgstrom_experiment.sh

# 예상 소요시간: 20-30분 (빌드 포함)
```

### Step 3: 구축 완료 확인
```bash
# 컨테이너 상태 확인
docker ps | grep pgstrom-test

# PostgreSQL 연결 테스트
docker exec pgstrom-test su - postgres -c "psql -c 'SELECT version();'"

# PG-Strom 확장 생성 및 확인
docker exec pgstrom-test su - postgres -c "psql -c 'CREATE EXTENSION pg_strom;'"
docker exec pgstrom-test su - postgres -c "psql -c 'SELECT extname, extversion FROM pg_extension WHERE extname = '\"'\"'pg_strom'\"'\"';'"

# GPU 인식 확인
docker exec pgstrom-test su - postgres -c "psql -c 'SELECT * FROM pgstrom.gpu_device_info() LIMIT 5;'"
```

### Step 4: GPU 가속 쿼리 검증 **[실제 테스트]**
```bash
# 테스트 데이터 생성
docker exec pgstrom-test su - postgres -c "psql -c \"CREATE TABLE test_table (id int, value float); INSERT INTO test_table SELECT i, random() FROM generate_series(1,10000) i;\""

# GPU 가속 쿼리 실행 (GpuPreAgg 확인)
docker exec pgstrom-test su - postgres -c "psql -c \"EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM test_table WHERE value > 0.5;\""

# 성공 시 출력: Custom Scan (GpuPreAgg), Scan-Engine: VFS with GPU0
```

## 🔧 핵심 해결 사항들 **[실제 문제 및 해결책]**

### 해결된 주요 문제들
1. **Docker 이미지 자동 선택 문제**
   - **문제**: `nvidia/cuda:11.0.3-base-ubuntu20.04`에서 수동 선택 필요
   - **해결**: `docker.io/nvidia/cuda:12.9.1-devel-rockylinux8` 명시적 사용

2. **PG-Strom 빌드 경로 문제**
   - **문제**: 루트 디렉토리에서 RPM 빌드 시도
   - **해결**: `cd pg-strom/src && make PG_CONFIG=/usr/pgsql-16/bin/pg_config USE_PGXS=1`

3. **빌드 환경 누락**
   - **문제**: `redhat-hardened-cc1` 파일 없음 에러
   - **해결**: `redhat-rpm-config rpm-build` 패키지 추가

4. **PostgreSQL 사용자 중복 생성**
   - **문제**: `useradd: user 'postgres' already exists`
   - **해결**: `id postgres || useradd -m postgres` 조건부 생성

### 검증된 최적 설정 **[성능 확인됨]**
```bash
# PostgreSQL 설정 (postgresql.conf)
shared_preload_libraries = '$libdir/pg_strom'
max_worker_processes = 100
shared_buffers = 4GB
work_mem = 1GB
pg_strom.enabled = on
pg_strom.debug_force_gpudirect = off

# Docker 리소스 할당
--shm-size=8gb --memory=8gb --gpus all
```

## 📊 기존 테스트 결과 이전

### 완료된 테스트 항목 (재실행 대상)
```bash
# Phase 1: 기본 GPU 연산 (이미 완료)
automation/script/simple_scan.sh
automation/script/subset_join.sh  
automation/script/large_join.sh
automation/script/simple_math.sh
automation/script/complex_math.sh
automation/script/simple_ops.sh

# 결과 분석
automation/script/analyze_simple.sh
```

### 새 서버에서 재현 확인 필요 사항
1. **성능 수치 비교**: 서버 간 하드웨어 차이로 인한 성능 변화
2. **GPU 메모리 설정**: 새 서버 GPU 사양에 맞는 최적화
3. **Docker 리소스 할당**: CPU/메모리 제한 조정

## 🔧 새 서버 최적화 설정

### GPU 메모리 설정 조정
```bash
# 새 서버 GPU 메모리 확인
nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits

# PG-Strom 설정 조정 (postgresql.conf)
# GPU 메모리의 70-80% 사용 권장
shared_buffers = 1GB                    # 시스템 메모리에 따라 조정
pg_strom.chunk_size = 65536            # 기본값에서 시작
pg_strom.max_async_tasks = 8           # CPU 코어 수에 따라 조정
pg_strom.gpu_cache_size = 6GB          # GPU 메모리에 따라 조정
```

### 성능 벤치마크 비교
```bash
# 서버 간 성능 비교를 위한 표준 테스트
cd automation/script

# 1. 시스템 정보 수집
./collect_system_info.sh > ../results/new_server_info.txt

# 2. 기본 성능 테스트 재실행
./run_basic_benchmark.sh

# 3. 결과 비교 분석
python ../analyze_server_comparison.py old_server_results/ new_server_results/
```

## 📝 체크리스트

### 구축 전 준비사항 **[실제 경험 기반]**
- [x] **현재 서버 환경 구축 완료** **[완료 상태]**
- [x] GitHub 저장소 최신 상태 확인
- [x] GPU 하드웨어 사양 확인 (NVIDIA L40S × 3개)
- [x] CUDA 12.9 드라이버 설치 확인

### 새 서버 구축 체크리스트 **[검증된 절차]**
- [ ] Docker 환경 설치 및 테스트
- [ ] NVIDIA 드라이버 및 Container Toolkit 설치
- [ ] `docker run --rm --gpus all docker.io/nvidia/cuda:12.9.1-devel-rockylinux8 nvidia-smi` 테스트
- [ ] 저장소 클론 및 권한 설정
- [ ] `./automation/script/setup_pgstrom_experiment.sh` 실행
- [ ] PostgreSQL + PG-Strom 연결 확인
- [ ] GPU 인식 및 가속 쿼리 테스트

### 구축 완료 검증 **[필수 확인사항]**
- [ ] `docker ps | grep pgstrom-test` 컨테이너 실행 확인
- [ ] `CREATE EXTENSION pg_strom` 성공
- [ ] `SELECT * FROM pgstrom.gpu_device_info()` GPU 정보 조회
- [ ] GPU 가속 쿼리에서 `Custom Scan (GpuPreAgg)` 출력 확인
- [ ] `Scan-Engine: VFS with GPU0` 메시지 확인

### 기본 테스트 재실행
- [ ] `simple_scan` 테스트 재실행
- [ ] `subset_join` 테스트 재실행  
- [ ] `large_join` 테스트 재실행
- [ ] `simple_math` 테스트 재실행
- [ ] `complex_math` 테스트 재실행
- [ ] `simple_ops` 테스트 재실행

### 결과 검증
- [ ] 새 서버 vs 기존 서버 성능 비교
- [ ] GPU 사용률 및 메모리 사용량 확인
- [ ] 에러 없이 모든 테스트 완료 확인
- [ ] 결과 데이터 정상 생성 확인

## 🚨 주의사항 및 트러블슈팅 **[실제 경험]**

### 해결된 이슈들 **[실제 발생 및 해결]**
1. **CUDA 12.9.1 이미지 호환성**
   ```bash
   # 성공 확인된 이미지
   FROM nvidia/cuda:12.9.1-devel-rockylinux8
   
   # 필수 빌드 도구
   dnf -y install git make gcc redhat-rpm-config rpm-build
   ```

2. **PG-Strom 소스 빌드**
   ```bash
   # 올바른 빌드 경로
   cd pg-strom/src
   make PG_CONFIG=/usr/pgsql-16/bin/pg_config USE_PGXS=1
   make install PG_CONFIG=/usr/pgsql-16/bin/pg_config USE_PGXS=1
   ```

3. **Docker 권한 문제**
   ```bash
   # GPU 액세스 확인
   docker run --rm --gpus all docker.io/nvidia/cuda:12.9.1-devel-rockylinux8 nvidia-smi
   ```

4. **PostgreSQL 설정 문제**
   ```bash
   # 사용자 확인 후 생성
   RUN id postgres || useradd -m postgres
   ```

## 📈 성능 기준점 **[실제 측정값]**

### 현재 서버 검증된 성능
```bash
GPU: NVIDIA L40S × 3개 (44.39GB RAM each)
Compute Capability: 8.9
Memory: 384-bit, 8.58GHz
SMs: 142개, 2520MHz
L2 Cache: 96MB

테스트 쿼리 성능:
- 10,000개 레코드 처리
- GPU 스캔으로 4,964개 결과 필터링
- 실행시간: 257ms (GPU 가속)
- GPU 사용률: 정상 인식 및 활용
```

### 새 서버 목표 성능
- **GPU 인식**: 모든 GPU 정상 인식
- **확장 설치**: PG-Strom 확장 생성 성공
- **가속 쿼리**: `Custom Scan (GpuPreAgg)` 실행
- **에러율**: 0% (모든 단계 정상 완료)

## 🔄 자동화 스크립트 **[검증 완료]**

### 완성된 자동화 도구
```bash
# 전체 환경 자동 구축
./automation/script/setup_pgstrom_experiment.sh

# 특징:
- Docker 이미지 자동 감지 및 선택
- PG-Strom v6.0 소스 빌드 자동화
- PostgreSQL 16 설정 자동 최적화
- GPU 인식 자동 확인
- 컨테이너 실행 및 설정 자동화
```

---

## 📅 성공적 구축 기록 **[신규 섹션]**

### 구축 완료 시점
- **날짜**: 2025-07-17
- **소요 시간**: 약 30분 (자동화 스크립트 포함)
- **최종 확인**: GPU 가속 쿼리 정상 실행

### 핵심 성공 요인
1. **올바른 Docker 베이스 이미지**: `nvidia/cuda:12.9.1-devel-rockylinux8`
2. **소스 빌드 방식**: RPM 패키지 대신 `src/` 디렉토리 빌드
3. **완전한 빌드 환경**: 모든 필수 패키지 사전 설치
4. **자동화된 설정**: 수동 개입 최소화

### 향후 이전 시 활용 방안
- **자동화 스크립트 재사용**: `setup_pgstrom_experiment.sh` 그대로 사용
- **설정 템플릿 활용**: postgresql.conf, Docker 설정 재사용
- **검증 절차 표준화**: GPU 가속 쿼리 테스트 자동화

---

*작성일: 2025-07-17*
*상태: 현재 서버 환경 구축 100% 완료*
*GPU 가속: 정상 동작 확인*