#!/bin/bash

# PG-Strom 완전 자동화 스크립트
# 실험 진행부터 보고서 작성까지 원클릭 실행
# 재솔님과 함께 작성

set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
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

log_success() {
    echo -e "${PURPLE}[SUCCESS]${NC} $1"
}

# 환경변수 설정
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$PROJECT_ROOT/automation/script"
EXPERIMENT_DIR="$PROJECT_ROOT/experiment_results"

# 실험 설정 환경변수 전달
export REPEAT_COUNT=${REPEAT_COUNT:-8}
export SLEEP_BETWEEN_RUNS=${SLEEP_BETWEEN_RUNS:-1}
export CLEAR_CACHE=${CLEAR_CACHE:-true}

# 실행 시간 측정
start_time=$(date +%s)
timestamp=$(date +"%Y%m%d_%H%M%S")

# 진행률 표시
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

# 실행 전 확인
pre_check() {
    log_header "실행 전 환경 확인"
    
    # 스크립트 존재 확인
    local required_scripts=("setup_pgstrom_experiment.sh" "create_test_data.sh" "run_performance_tests.sh" "generate_report.py")
    
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$SCRIPT_DIR/$script" ]; then
            log_error "필수 스크립트가 없습니다: $SCRIPT_DIR/$script"
            exit 1
        fi
        
        # 실행 권한 확인
        if [ ! -x "$SCRIPT_DIR/$script" ]; then
            log_info "실행 권한 부여: $script"
            chmod +x "$SCRIPT_DIR/$script"
        fi
    done
    
    # 디스크 공간 확인 (최소 30GB)
    local available_space=$(df "$PROJECT_ROOT" | tail -1 | awk '{print $4}')
    local required_space=31457280  # 30GB in KB
    
    if [ "$available_space" -lt "$required_space" ]; then
        log_warn "디스크 공간이 부족할 수 있습니다. (사용 가능: $(($available_space/1024/1024))GB, 권장: 30GB)"
        read -p "계속 진행하시겠습니까? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            log_info "실험을 중단합니다."
            exit 0
        fi
    fi
    
    log_success "환경 확인 완료"
}

# 1단계: 환경 설정
run_setup() {
    log_header "1단계: 환경 설정"
    show_progress 1 5 "Docker 환경 설정 중..."
    
    if ! "$SCRIPT_DIR/setup_pgstrom_experiment.sh"; then
        log_error "환경 설정 실패"
        exit 1
    fi
    
    log_success "1단계 완료"
}

# 2단계: 테스트 데이터 생성
run_data_creation() {
    log_header "2단계: 테스트 데이터 생성"
    show_progress 2 5 "대용량 테스트 데이터 생성 중... (약 10-20분)"
    
    if ! "$SCRIPT_DIR/create_test_data.sh"; then
        log_error "테스트 데이터 생성 실패"
        exit 1
    fi
    
    log_success "2단계 완료"
}

# 3단계: 성능 실험 실행
run_experiments() {
    log_header "3단계: 성능 실험 실행"
    show_progress 3 5 "GPU vs CPU 성능 비교 실험 중... (약 2-3시간, 8회 반복)"
    
    if ! "$SCRIPT_DIR/run_performance_tests.sh"; then
        log_error "성능 실험 실행 실패"
        exit 1
    fi
    
    log_success "3단계 완료"
}

# 4단계: 보고서 생성
generate_reports() {
    log_header "4단계: 보고서 생성"
    show_progress 4 5 "분석 보고서 생성 중..."
    
    # 최신 결과 디렉토리 찾기
    local latest_result=$(ls -td "$EXPERIMENT_DIR"/results_* 2>/dev/null | head -1)
    
    if [ -z "$latest_result" ]; then
        log_error "실험 결과를 찾을 수 없습니다."
        exit 1
    fi
    
    # 보고서 생성
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 "$SCRIPT_DIR/generate_report.py" "$latest_result"; then
            log_error "보고서 생성 실패"
            exit 1
        fi
    else
        log_warn "Python3이 설치되지 않아 자동 보고서 생성을 건너뜁니다."
    fi
    
    log_success "4단계 완료"
}

# 5단계: 결과 정리 및 요약
finalize_results() {
    log_header "5단계: 결과 정리 및 요약"
    show_progress 5 5 "최종 결과 정리 중..."
    
    # 최신 결과 디렉토리 찾기
    local latest_result=$(ls -td "$EXPERIMENT_DIR"/results_* 2>/dev/null | head -1)
    
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
        echo "PG-Strom 완전 자동화 실험 완료 보고서"
        echo "========================================"
        echo ""
        echo "실험 ID: $timestamp"
        echo "실행 날짜: $(date)"
        echo "총 실행 시간: ${hours}시간 ${minutes}분 ${seconds}초"
        echo "결과 위치: $latest_result"
        echo ""
        echo "생성된 파일:"
        ls -la "$latest_result" | grep -E '\.(md|json|txt|csv)$' | while read -r line; do
            echo "  $line"
        done
        echo ""
        echo "빠른 결과 확인:"
        if [ -f "$latest_result/quick_summary.txt" ]; then
            cat "$latest_result/quick_summary.txt"
        fi
        echo ""
        echo "상세 분석 보고서:"
        echo "  cat $latest_result/performance_report.md"
        echo ""
        echo "JSON 데이터:"
        echo "  cat $latest_result/experiment_summary.json"
        echo ""
        echo "CSV 원본 데이터:"
        echo "  cat $latest_result/summary.csv"
        
    } > "$latest_result/automation_final_report.txt"
    
    log_success "5단계 완료"
    
    # 최종 결과 출력
    log_header "🎉 PG-Strom 자동화 실험 완료! 🎉"
    echo ""
    log_info "총 실행 시간: ${hours}시간 ${minutes}분 ${seconds}초"
    log_info "결과 위치: $latest_result"
    echo ""
    log_info "생성된 보고서:"
    if [ -f "$latest_result/performance_report.md" ]; then
        echo "  📊 성능 분석 보고서: $latest_result/performance_report.md"
    fi
    if [ -f "$latest_result/quick_summary.txt" ]; then
        echo "  📋 빠른 요약: $latest_result/quick_summary.txt"
    fi
    if [ -f "$latest_result/experiment_summary.json" ]; then
        echo "  📈 JSON 데이터: $latest_result/experiment_summary.json"
    fi
    if [ -f "$latest_result/automation_final_report.txt" ]; then
        echo "  📝 최종 보고서: $latest_result/automation_final_report.txt"
    fi
    echo ""
    log_info "다음 명령어로 결과를 확인하세요:"
    echo "  cat $latest_result/quick_summary.txt"
    echo "  cat $latest_result/performance_report.md"
}

# 정리 함수
cleanup() {
    log_info "정리 작업 중..."
    # 필요시 임시 파일 정리
}

# 메인 실행 함수
main() {
    log_header "🚀 PG-Strom 완전 자동화 시스템 🚀"
    log_info "실험 진행부터 보고서 작성까지 완전 자동화"
    log_info "각 테스트 ${REPEAT_COUNT}회 반복으로 통계적 신뢰성 확보"
    log_info "실행 간격: ${SLEEP_BETWEEN_RUNS}초"
    log_info "캐시 클리어: ${CLEAR_CACHE}"
    log_info "예상 소요 시간: $((REPEAT_COUNT * 30 / 60))시간 (${REPEAT_COUNT}회 반복 실행)"
    log_info "시작 시간: $(date)"
    echo ""
    
    # 실행 확인
    read -p "실험을 시작하시겠습니까? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "실험을 취소합니다."
        exit 0
    fi
    
    # 트랩 설정 (오류 발생 시 정리)
    trap cleanup EXIT
    
    # 단계별 실행
    pre_check
    run_setup
    run_data_creation
    run_experiments
    generate_reports
    finalize_results
    
    log_success "모든 단계가 성공적으로 완료되었습니다!"
}

# 스크립트 실행
main "$@" 