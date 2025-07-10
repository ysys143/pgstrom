#!/bin/bash

# PG-Strom 실험 전체 자동화 실행 스크립트
# 재솔님과 함께 작성 - 원클릭 실행

set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
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

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# 실행 시간 측정
start_time=$(date +%s)

# 스크립트 실행 권한 확인
check_permissions() {
    log_step "스크립트 실행 권한 확인 중..."
    
    local scripts=("setup_pgstrom_experiment.sh" "create_test_data.sh" "run_experiments.sh")
    
    for script in "${scripts[@]}"; do
        if [ ! -f "$script" ]; then
            log_error "스크립트 파일이 없습니다: $script"
            exit 1
        fi
        
        if [ ! -x "$script" ]; then
            log_info "실행 권한 부여: $script"
            chmod +x "$script"
        fi
    done
    
    log_info "모든 스크립트 실행 권한 확인 완료"
}

# 실행 전 확인
pre_check() {
    log_step "실행 전 확인 중..."
    
    # 현재 디렉토리 확인
    if [ ! -f "setup_pgstrom_experiment.sh" ]; then
        log_error "올바른 디렉토리에서 실행하세요. setup_pgstrom_experiment.sh 파일이 없습니다."
        exit 1
    fi
    
    # 디스크 공간 확인 (최소 50GB)
    local available_space=$(df . | tail -1 | awk '{print $4}')
    local required_space=52428800  # 50GB in KB
    
    if [ "$available_space" -lt "$required_space" ]; then
        log_warn "디스크 공간이 부족할 수 있습니다. (사용 가능: $(($available_space/1024/1024))GB, 권장: 50GB)"
        read -p "계속 진행하시겠습니까? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            log_info "실험을 중단합니다."
            exit 0
        fi
    fi
    
    log_info "실행 전 확인 완료"
}

# 진행 상황 표시
show_progress() {
    local current=$1
    local total=$2
    local description=$3
    
    local percentage=$((current * 100 / total))
    local bar_length=50
    local filled_length=$((percentage * bar_length / 100))
    
    printf "\r${BLUE}[진행률]${NC} ["
    for ((i=1; i<=filled_length; i++)); do printf "█"; done
    for ((i=filled_length+1; i<=bar_length; i++)); do printf "░"; done
    printf "] %d%% - %s" "$percentage" "$description"
    
    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

# 1단계: 환경 설정
run_setup() {
    log_header "1단계: 환경 설정 (Docker 이미지 빌드, 컨테이너 실행)"
    show_progress 1 4 "환경 설정 중..."
    
    if ! ./setup_pgstrom_experiment.sh; then
        log_error "환경 설정 실패"
        exit 1
    fi
    
    log_info "1단계 완료"
}

# 2단계: 테스트 데이터 생성
run_data_creation() {
    log_header "2단계: 테스트 데이터 생성 (약 10-20분 소요)"
    show_progress 2 4 "테스트 데이터 생성 중..."
    
    if ! ./create_test_data.sh; then
        log_error "테스트 데이터 생성 실패"
        exit 1
    fi
    
    log_info "2단계 완료"
}

# 3단계: 실험 실행
run_experiments() {
    log_header "3단계: 성능 실험 실행 (약 30-60분 소요)"
    show_progress 3 4 "성능 실험 실행 중..."
    
    if ! ./run_experiments.sh; then
        log_error "성능 실험 실행 실패"
        exit 1
    fi
    
    log_info "3단계 완료"
}

# 4단계: 결과 정리
finalize_results() {
    log_header "4단계: 결과 정리 및 요약"
    show_progress 4 4 "결과 정리 중..."
    
    # 최신 결과 디렉토리 찾기
    local latest_result=$(ls -td experiment_results/results_* 2>/dev/null | head -1)
    
    if [ -z "$latest_result" ]; then
        log_error "실험 결과를 찾을 수 없습니다."
        exit 1
    fi
    
    # 실행 시간 계산
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    local hours=$((total_time / 3600))
    local minutes=$(((total_time % 3600) / 60))
    local seconds=$((total_time % 60))
    
    # 최종 요약 생성
    {
        echo "=== PG-Strom 실험 완료 요약 ==="
        echo "실행 날짜: $(date)"
        echo "총 실행 시간: ${hours}시간 ${minutes}분 ${seconds}초"
        echo "결과 위치: $latest_result"
        echo ""
        echo "=== 빠른 결과 확인 ==="
        if [ -f "$latest_result/analysis.txt" ]; then
            cat "$latest_result/analysis.txt"
        fi
        echo ""
        echo "=== 상세 결과 확인 명령어 ==="
        echo "ls -la $latest_result"
        echo "cat $latest_result/summary.csv"
        echo "docker logs pgstrom-test"
        
    } > "$latest_result/final_summary.txt"
    
    log_info "4단계 완료"
}

# 실험 결과 미리보기
show_preview() {
    log_header "실험 결과 미리보기"
    
    local latest_result=$(ls -td experiment_results/results_* 2>/dev/null | head -1)
    
    if [ -f "$latest_result/final_summary.txt" ]; then
        cat "$latest_result/final_summary.txt"
    fi
}

# 정리 함수
cleanup_on_error() {
    log_error "실험 중 오류가 발생했습니다."
    log_info "정리 작업 중..."
    
    # 컨테이너 정리 (선택사항)
    read -p "컨테이너를 정리하시겠습니까? (y/N): " cleanup_confirm
    if [ "$cleanup_confirm" = "y" ] || [ "$cleanup_confirm" = "Y" ]; then
        docker stop pgstrom-test 2>/dev/null || true
        docker rm pgstrom-test 2>/dev/null || true
        log_info "컨테이너 정리 완료"
    fi
}

# 신호 처리
trap cleanup_on_error ERR INT TERM

# 메인 실행 함수
main() {
    log_header "PG-Strom GPU 가속 성능 분석 실험 - 전체 자동화"
    log_info "재솔님과 함께 작성한 자동화 스크립트입니다."
    log_info "예상 총 실행 시간: 1-2시간"
    
    # 실행 확인
    read -p "실험을 시작하시겠습니까? (y/N): " start_confirm
    if [ "$start_confirm" != "y" ] && [ "$start_confirm" != "Y" ]; then
        log_info "실험을 취소합니다."
        exit 0
    fi
    
    # 실행 전 확인
    check_permissions
    pre_check
    
    # 전체 실험 실행
    run_setup
    run_data_creation
    run_experiments
    finalize_results
    
    # 결과 미리보기
    show_preview
    
    log_header "🎉 모든 실험이 성공적으로 완료되었습니다!"
    log_info "상세 결과는 experiment_results/ 디렉토리에서 확인하세요."
    
    # 실행 시간 표시
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    local hours=$((total_time / 3600))
    local minutes=$(((total_time % 3600) / 60))
    local seconds=$((total_time % 60))
    
    log_info "총 실행 시간: ${hours}시간 ${minutes}분 ${seconds}초"
}

# 스크립트 실행
main "$@" 