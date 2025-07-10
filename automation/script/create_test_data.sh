#!/bin/bash

# PG-Strom 실험용 테스트 데이터 생성 스크립트
# 재솔님과 함께 작성

set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 설정 변수
CONTAINER_NAME="pgstrom-test"

# 데이터베이스 생성 및 테스트 데이터 생성
create_test_databases() {
    log_step "테스트 데이터베이스 생성 중..."
    
    # 기본 테스트 데이터베이스
    docker container exec $CONTAINER_NAME su - postgres -c "
        createdb testdb
        createdb testdb2
    "
    
    log_info "데이터베이스 생성 완료"
}

# 기본 테스트 데이터 생성 (2500만 행)
create_basic_test_data() {
    log_step "기본 테스트 데이터 생성 중 (2500만 행)..."
    
    docker container exec $CONTAINER_NAME su - postgres -c "
        psql testdb -c \"
            CREATE TABLE t_test AS 
            SELECT id, 
                   random() * 100 AS ten, 
                   random() * 20 AS twenty 
            FROM generate_series(1, 25000000) AS id;
            
            CREATE INDEX idx_t_test_id ON t_test(id);
            ANALYZE t_test;
        \"
    "
    
    log_info "기본 테스트 데이터 생성 완료"
}

# 조인용 테스트 데이터 생성 (100만 행)
create_join_test_data() {
    log_step "조인용 테스트 데이터 생성 중 (100만 행)..."
    
    docker container exec $CONTAINER_NAME su - postgres -c "
        psql testdb -c \"
            CREATE TABLE t_join AS 
            SELECT * FROM t_test WHERE random() < 0.04;
            
            CREATE INDEX idx_t_join_id ON t_join(id);
            ANALYZE t_join;
        \"
    "
    
    log_info "조인용 테스트 데이터 생성 완료"
}

# 대용량 독립 테이블 생성 (1000만 행 × 2)
create_large_independent_data() {
    log_step "대용량 독립 테이블 생성 중 (1000만 행 × 2)..."
    
    docker container exec $CONTAINER_NAME su - postgres -c "
        psql testdb2 -c \"
            CREATE TABLE t_large1 AS 
            SELECT id, random()::int AS val 
            FROM generate_series(1, 10000000) AS id;
            
            CREATE TABLE t_large2 AS 
            SELECT id, random()::int AS val 
            FROM generate_series(1, 10000000) AS id;
            
            CREATE INDEX idx_t_large1_id ON t_large1(id);
            CREATE INDEX idx_t_large2_id ON t_large2(id);
            
            ANALYZE t_large1;
            ANALYZE t_large2;
        \"
    "
    
    log_info "대용량 독립 테이블 생성 완료"
}

# 초대용량 테이블 생성 (5000만 행)
create_huge_table() {
    log_step "초대용량 테이블 생성 중 (5000만 행)..."
    
    docker container exec $CONTAINER_NAME su - postgres -c "
        psql testdb2 -c \"
            CREATE TABLE t_huge AS 
            SELECT id, random()::int AS val 
            FROM generate_series(1, 50000000) AS id;
            
            CREATE INDEX idx_t_huge_id ON t_huge(id);
            ANALYZE t_huge;
        \"
    "
    
    log_info "초대용량 테이블 생성 완료"
}

# 테이블 정보 확인
show_table_info() {
    log_step "생성된 테이블 정보 확인 중..."
    
    echo "=== testdb 테이블 정보 ==="
    docker container exec $CONTAINER_NAME su - postgres -c "
        psql testdb -c \"\\dt+ t_test t_join\"
    "
    
    echo "=== testdb2 테이블 정보 ==="
    docker container exec $CONTAINER_NAME su - postgres -c "
        psql testdb2 -c \"\\dt+ t_large1 t_large2 t_huge\"
    "
    
    log_info "테이블 정보 확인 완료"
}

# 메인 실행 함수
main() {
    log_info "PG-Strom 실험용 테스트 데이터 생성 시작"
    
    # 컨테이너 실행 상태 확인
    if ! docker ps --format 'table {{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        log_warn "컨테이너가 실행되지 않았습니다. setup_pgstrom_experiment.sh를 먼저 실행하세요."
        exit 1
    fi
    
    create_test_databases
    create_basic_test_data
    create_join_test_data
    create_large_independent_data
    create_huge_table
    show_table_info
    
    log_info "모든 테스트 데이터 생성 완료!"
    log_info "다음 단계: ./run_experiments.sh 실행"
}

# 스크립트 실행
main "$@" 