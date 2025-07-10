#!/bin/bash

# PG-Strom GPU 가속 성능 분석 실험 자동화 스크립트
# 작성자: 재솔님과 함께 작성
# 날짜: 2025-01-10

set -e  # 에러 발생 시 스크립트 중단

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 설정 변수
DOCKER_IMAGE="mypg16-rocky8:latest"
CONTAINER_NAME="pgstrom-test"
WORK_DIR="/home/jaesol/Projects/pgstrom"
EXPERIMENT_DIR="$WORK_DIR/experiment_results"

# 시스템 요구사항 확인
check_requirements() {
    log_step "시스템 요구사항 확인 중..."
    
    # NVIDIA GPU 확인
    if ! command -v nvidia-smi &> /dev/null; then
        log_error "NVIDIA GPU 드라이버가 설치되지 않았습니다."
        exit 1
    fi
    
    # Docker 확인
    if ! command -v docker &> /dev/null; then
        log_error "Docker가 설치되지 않았습니다."
        exit 1
    fi
    
    # NVIDIA Container Toolkit 확인
    if ! docker info | grep -q "nvidia"; then
        log_error "NVIDIA Container Toolkit이 설정되지 않았습니다."
        exit 1
    fi
    
    log_info "모든 요구사항이 충족되었습니다."
}

# 작업 디렉토리 생성
create_directories() {
    log_step "작업 디렉토리 생성 중..."
    
    mkdir -p "$EXPERIMENT_DIR"
    mkdir -p "$WORK_DIR/scripts"
    mkdir -p "$WORK_DIR/configs"
    mkdir -p "$WORK_DIR/logs"
    
    log_info "디렉토리 생성 완료"
}

# Docker 이미지 빌드
build_docker_image() {
    log_step "Docker 이미지 빌드 중..."
    
    if [[ "$(docker images -q $DOCKER_IMAGE 2> /dev/null)" == "" ]]; then
        log_info "PG-Strom Docker 이미지 빌드 시작..."
        
        # pg-strom-docker 클론 (이미 존재하지 않는 경우)
        if [ ! -d "pg-strom-docker" ]; then
            git clone https://github.com/ytooyama/pg-strom-docker.git
        fi
        
        cd pg-strom-docker/docker
        docker image build --compress -t $DOCKER_IMAGE -f Dockerfile .
        cd "$WORK_DIR"
        
        log_info "Docker 이미지 빌드 완료"
    else
        log_info "Docker 이미지가 이미 존재합니다."
    fi
}

# 컨테이너 실행
start_container() {
    log_step "PG-Strom 컨테이너 시작 중..."
    
    # 기존 컨테이너 정리
    if docker ps -a --format 'table {{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        log_info "기존 컨테이너 정리 중..."
        docker container stop $CONTAINER_NAME 2>/dev/null || true
        docker container rm $CONTAINER_NAME 2>/dev/null || true
    fi
    
    # 새 컨테이너 시작
    docker container run --gpus all --shm-size=4gb --memory=4gb \
        -p 5432:5432 -itd --name=$CONTAINER_NAME $DOCKER_IMAGE
    
    # 컨테이너 시작 대기
    sleep 10
    
    log_info "컨테이너 시작 완료"
}

# PostgreSQL 초기화
setup_postgresql() {
    log_step "PostgreSQL 초기화 중..."
    
    # PostgreSQL 초기화
    docker container exec $CONTAINER_NAME su - postgres -c \
        "/usr/pgsql-16/bin/initdb -D /var/lib/pgsql/16/data"
    
    # 설정 파일 수정
    docker container exec $CONTAINER_NAME bash -c "
        cd /var/lib/pgsql/16/data
        sed -i \"s/#shared_preload_libraries = ''/shared_preload_libraries = '\\\$libdir\/pg_strom'/g\" postgresql.conf
        sed -i 's/#max_worker_processes = 8/max_worker_processes = 100/g' postgresql.conf
        sed -i 's/shared_buffers = 128MB/shared_buffers = 2GB/g' postgresql.conf
        sed -i 's/#work_mem = 4MB/work_mem = 512MB/g' postgresql.conf
        sed -i 's/#listen_addresses = .*/listen_addresses = '\''*'\''/g' postgresql.conf
        echo 'host all all 0.0.0.0/0 trust' >> pg_hba.conf
    "
    
    # PostgreSQL 시작
    docker container exec $CONTAINER_NAME systemctl start postgresql
    
    # PG-Strom 로딩 확인
    sleep 5
    docker container exec $CONTAINER_NAME journalctl -u postgresql -n 20 | grep -i "pg-strom"
    
    log_info "PostgreSQL 초기화 완료"
}

# 메인 실행 함수
main() {
    log_info "PG-Strom 실험 환경 자동화 설정 시작"
    log_info "작업 디렉토리: $WORK_DIR"
    
    check_requirements
    create_directories
    build_docker_image
    start_container
    setup_postgresql
    
    log_info "기본 설정 완료!"
    log_info "다음 단계: ./run_experiments.sh 실행"
    
    # 시스템 정보 수집
    log_step "시스템 정보 수집 중..."
    nvidia-smi > "$EXPERIMENT_DIR/system_info.txt"
    docker info >> "$EXPERIMENT_DIR/system_info.txt"
    uname -a >> "$EXPERIMENT_DIR/system_info.txt"
    
    log_info "모든 설정이 완료되었습니다!"
}

# 스크립트 실행
main "$@" 