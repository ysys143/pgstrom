#!/bin/bash

# Shell 전용 간단 성능 분석 스크립트
# 재솔님 요청 - Python 의존성 없는 버전

analyze_csv() {
    local csv_file="$1"
    
    if [ ! -f "$csv_file" ]; then
        echo "ERROR: CSV 파일을 찾을 수 없습니다: $csv_file"
        return 1
    fi
    
    echo "=== PG-Strom 성능 분석 결과 (Shell 버전) ==="
    echo ""
    
    # 테스트 이름 목록 추출 (헤더 제외)
    local test_names=$(awk -F',' 'NR>1 && $1!="test_name" {print $1}' "$csv_file" | sort -u)
    
    local gpu_better=0
    local cpu_better=0
    local total_tests=0
    
    for test_name in $test_names; do
        echo "테스트: $test_name"
        
        # GPU ON 시간 추출 (첫 번째 값)
        local gpu_time=$(awk -F',' -v test="$test_name" '$1==test && $2=="on" {print $3; exit}' "$csv_file")
        
        # GPU OFF 시간 추출 (첫 번째 값)
        local cpu_time=$(awk -F',' -v test="$test_name" '$1==test && $2=="off" {print $3; exit}' "$csv_file")
        
        if [ -n "$gpu_time" ] && [ -n "$cpu_time" ]; then
            # 성능 향상 계산 (bc 사용)
            local improvement=$(echo "scale=1; (($cpu_time - $gpu_time) / $cpu_time) * 100" | bc -l)
            
            echo "  GPU 시간: ${gpu_time}ms"
            echo "  CPU 시간: ${cpu_time}ms"
            echo "  성능 향상: ${improvement}%"
            
            # 어느 쪽이 더 빠른지 판단
            if (( $(echo "$gpu_time < $cpu_time" | bc -l) )); then
                echo "  우수한 방식: GPU"
                ((gpu_better++))
            else
                echo "  우수한 방식: CPU"
                ((cpu_better++))
            fi
            
            ((total_tests++))
        else
            echo "  데이터 부족 - GPU: $gpu_time, CPU: $cpu_time"
        fi
        echo ""
    done
    
    echo "=== 요약 ==="
    echo "총 테스트 수: $total_tests"
    echo "GPU 우위 테스트: $gpu_better"
    echo "CPU 우위 테스트: $cpu_better"
}

# 메인 실행
if [ $# -ne 1 ]; then
    echo "사용법: $0 <csv_file>"
    exit 1
fi

# bc 명령어 존재 확인
if ! command -v bc &> /dev/null; then
    echo "ERROR: bc 명령어가 필요합니다. 설치하세요: sudo apt-get install bc"
    exit 1
fi

analyze_csv "$1" 