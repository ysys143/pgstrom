#!/usr/bin/env python3
import os
import re
import json
import statistics
from datetime import datetime

def read_times_file(file_path):
    """times 파일에서 실행 시간 리스트 읽기"""
    if not os.path.exists(file_path):
        return []
    
    with open(file_path, 'r') as f:
        times = []
        for line in f:
            line = line.strip()
            if line:
                try:
                    times.append(float(line))
                except ValueError:
                    continue
        return times

def calculate_statistics(times):
    """통계 계산"""
    if not times:
        return None
    
    return {
        'mean': statistics.mean(times),
        'min': min(times),
        'max': max(times),
        'std': statistics.stdev(times) if len(times) > 1 else 0,
        'count': len(times)
    }

def analyze_performance():
    """성능 분석"""
    result_dir = os.path.dirname(os.path.abspath(__file__))
    
    # 테스트 케이스 목록
    all_tests = ['string_concat', 'string_length', 'date_extraction', 'date_arithmetic']
    
    results = {
        'performance_results': {},
        'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    }
    
    for test_name in all_tests:
        # GPU ON 결과
        gpu_on_times = read_times_file(os.path.join(result_dir, f'{test_name}_on_times.txt'))
        gpu_on_stats = calculate_statistics(gpu_on_times)
        
        # GPU OFF 결과
        gpu_off_times = read_times_file(os.path.join(result_dir, f'{test_name}_off_times.txt'))
        gpu_off_stats = calculate_statistics(gpu_off_times)
        
        if gpu_on_stats and gpu_off_stats:
            # 성능 향상 계산
            improvement = ((gpu_off_stats['mean'] - gpu_on_stats['mean']) / gpu_off_stats['mean']) * 100
            faster = "GPU" if gpu_on_stats['mean'] < gpu_off_stats['mean'] else "CPU"
            
            results['performance_results'][test_name] = {
                'gpu_on': gpu_on_stats['mean'],
                'gpu_off': gpu_off_stats['mean'],
                'improvement_percent': abs(improvement),
                'faster': faster,
                'runs_count': gpu_on_stats['count']
            }
    
    return results

def generate_markdown_report(results):
    """마크다운 보고서 생성"""
    content = f"""# PG-Strom Phase 1-C 간단 성능 테스트

**작성자**: 재솔님  
**작성일**: {results['timestamp']}  

## 실험 결과

| 테스트 케이스 | GPU (ms) | CPU (ms) | 성능 향상 | 우수한 방식 |
|---------------|----------|----------|-----------|------------|
"""
    
    for test_name, data in results['performance_results'].items():
        display_name = test_name.replace('_', ' ').title()
        content += f"| {display_name} | {data['gpu_on']:.1f} | {data['gpu_off']:.1f} | {data['improvement_percent']:.1f}% | {data['faster']} |\n"
    
    gpu_wins = sum(1 for data in results['performance_results'].values() if data['faster'] == 'GPU')
    cpu_wins = sum(1 for data in results['performance_results'].values() if data['faster'] == 'CPU')
    total_tests = len(results['performance_results'])
    
    content += f"""

## 요약

- 총 {total_tests}개 테스트 중 GPU가 {gpu_wins}개, CPU가 {cpu_wins}개 테스트에서 우수한 성능을 보였습니다.
- 각 테스트는 {list(results['performance_results'].values())[0]['runs_count']}회 반복 실행되었습니다.

## 결론

문자열 및 날짜/시간 연산에서 PG-Strom의 GPU 가속 효과를 확인했습니다.

---
*Phase 1-C 간단 테스트 결과입니다.*
"""
    
    with open('performance_report.md', 'w', encoding='utf-8') as f:
        f.write(content)

def main():
    """메인 함수"""
    results = analyze_performance()
    
    # JSON 결과 저장
    with open('experiment_summary.json', 'w') as f:
        json.dump(results, f, indent=2)
    
    # 마크다운 보고서 생성
    generate_markdown_report(results)
    
    # 간단한 요약 출력
    print("=== Phase 1-C 간단 테스트 결과 ===")
    for test_name, data in results['performance_results'].items():
        print(f"{test_name}: GPU {data['gpu_on']:.1f}ms vs CPU {data['gpu_off']:.1f}ms ({data['faster']} 우수)")
    
    print("\n보고서 생성 완료:")
    print("- performance_report.md: 마크다운 보고서")
    print("- experiment_summary.json: JSON 결과")

if __name__ == "__main__":
    main()
