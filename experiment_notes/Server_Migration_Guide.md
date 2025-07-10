# PG-Strom 테스트 환경 서버 이전 가이드

## 📋 개요
- **현재 서버**: 192.168.0.102 (테스트 완료 환경)
- **이전 대상**: 새로운 서버 (다음주부터 사용)
- **목적**: 기존 테스트 결과 및 환경을 새 서버에서 재현

## 🎯 이전 대상 항목

### 1. 코드 및 설정
- [x] **GitHub 저장소**: https://github.com/ysys143/pgstrom
- [ ] **Docker 환경 설정**
- [ ] **테스트 스크립트 및 자동화 도구**
- [ ] **실험 결과 데이터**

### 2. 환경 요구사항
```bash
# 필수 소프트웨어
- Docker & Docker Compose
- NVIDIA GPU Driver
- nvidia-container-toolkit
- Git
- Python 3.8+
- PostgreSQL client tools

# GPU 요구사항
- CUDA 호환 GPU
- 최소 8GB GPU 메모리 (권장: 16GB+)
```

## 🛠 새 서버 환경 구축 단계

### Step 1: 기본 환경 설정
```bash
# 1. 저장소 클론
git clone https://github.com/ysys143/pgstrom.git
cd pgstrom

# 2. Docker 설치 확인
docker --version
docker-compose --version

# 3. NVIDIA Container Toolkit 설치 확인
sudo docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

### Step 2: GPU 및 드라이버 검증
```bash
# GPU 상태 확인
nvidia-smi

# CUDA 버전 확인
nvcc --version

# GPU 메모리 및 사용률 모니터링 테스트
nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv -l 1
```

### Step 3: PG-Strom Docker 환경 구축
```bash
# Docker 환경 빌드
cd pg-strom-docker
docker-compose build

# 환경 변수 설정 확인
cp .env.example .env
# GPU 메모리 설정 조정 (새 서버 사양에 맞게)

# 컨테이너 실행 테스트
docker-compose up -d
docker-compose logs pgstrom
```

### Step 4: 기본 연결 및 동작 테스트
```bash
# PostgreSQL 연결 테스트
docker-compose exec pgstrom psql -U postgres -d postgres

# PG-Strom 확장 확인
\dx
SELECT * FROM pg_extension WHERE extname = 'pg_strom';

# GPU 인식 확인
SELECT * FROM pgstrom.device_info;
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

### 이전 전 준비사항
- [ ] 현재 서버 테스트 결과 백업 완료
- [ ] GitHub 저장소 최신 상태 확인
- [ ] 새 서버 하드웨어 사양 확인 (GPU, CPU, 메모리)
- [ ] 새 서버 OS 및 기본 소프트웨어 설치 확인

### 새 서버 구축 체크리스트
- [ ] Docker 환경 설치 및 테스트
- [ ] NVIDIA 드라이버 및 Container Toolkit 설치
- [ ] 저장소 클론 및 권한 설정
- [ ] Docker Compose 빌드 및 실행
- [ ] PostgreSQL + PG-Strom 연결 확인
- [ ] GPU 인식 및 기본 기능 테스트

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

## 🚨 주의사항 및 트러블슈팅

### 예상 이슈들
1. **GPU 호환성 문제**
   ```bash
   # CUDA 버전 호환성 확인
   docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
   ```

2. **메모리 부족 에러**
   ```bash
   # GPU 메모리 설정 축소
   pg_strom.gpu_cache_size = 4GB  # 기존 6GB에서 축소
   ```

3. **Docker 권한 문제**
   ```bash
   # Docker 그룹 추가
   sudo usermod -aG docker $USER
   # 재로그인 필요
   ```

4. **포트 충돌**
   ```bash
   # 사용 중인 포트 확인
   netstat -tlnp | grep 5432
   # docker-compose.yml에서 포트 변경
   ```

## 📈 성능 비교 기준점

### 현재 서버 기준 성능 (참고용)
```
GPU: [현재 GPU 모델]
Memory: [GPU 메모리 크기]
기본 스캔 성능: [수치]
조인 성능: [수치]
수학 연산 성능: [수치]
```

### 새 서버 목표 성능
- **기본 기능**: 현재 서버 대비 ±20% 이내
- **GPU 활용률**: 80% 이상 유지
- **에러율**: 0% (모든 테스트 정상 완료)

## 🔄 지속적 통합 (CI/CD) 준비

### 자동화 스크립트 개선
```bash
# 서버 환경 자동 감지 및 설정
./automation/script/detect_and_configure.sh

# 전체 테스트 자동 실행
./automation/script/run_full_test_suite.sh

# 결과 자동 업로드
./automation/script/upload_results.sh
```

---

## 📅 이전 일정

### 이전 준비 (이번 주)
- **목요일**: 현재 서버 최종 테스트 및 결과 정리
- **금요일**: 이전 가이드 완성 및 백업

### 새 서버 구축 (다음 주 월요일)
- **오전**: 기본 환경 설정 및 Docker 구축
- **오후**: PG-Strom 환경 설정 및 연결 테스트

### 테스트 재개 (다음 주 화요일부터)
- **화요일**: 기본 테스트 재실행 및 성능 비교
- **수요일**: Phase 1 완성 (문자열, 날짜/시간 연산)
- **목-금**: Phase 2 시작 (GROUP BY, AGGREGATE)

*작성일: 2025-07-10*