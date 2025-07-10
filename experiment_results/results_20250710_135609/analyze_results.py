#!/usr/bin/env python3
import pandas as pd
import sys

def analyze_results(csv_file):
    try:
        df = pd.read_csv(csv_file)
        
        print("=== PG-Strom 성능 분석 결과 ===\n")
        
        # 테스트별 성능 비교
        for test_name in df['test_name'].unique():
            test_data = df[df['test_name'] == test_name]
            
            gpu_on = test_data[test_data['gpu_enabled'] == 'on']['execution_time_ms'].values
            gpu_off = test_data[test_data['gpu_enabled'] == 'off']['execution_time_ms'].values
            
            if len(gpu_on) > 0 and len(gpu_off) > 0:
                gpu_time = gpu_on[0]
                cpu_time = gpu_off[0]
                
                improvement = ((cpu_time - gpu_time) / cpu_time) * 100
                
                print(f"테스트: {test_name}")
                print(f"  GPU 시간: {gpu_time:.1f}ms")
                print(f"  CPU 시간: {cpu_time:.1f}ms")
                print(f"  성능 향상: {improvement:+.1f}%")
                print()
        
        print("=== 요약 ===")
        print(f"총 테스트 수: {len(df['test_name'].unique())}")
        print(f"GPU 우위 테스트: {len([t for t in df['test_name'].unique() if get_improvement(df, t) > 0])}")
        print(f"CPU 우위 테스트: {len([t for t in df['test_name'].unique() if get_improvement(df, t) < 0])}")
        
    except Exception as e:
        print(f"분석 중 오류 발생: {e}")

def get_improvement(df, test_name):
    test_data = df[df['test_name'] == test_name]
    gpu_on = test_data[test_data['gpu_enabled'] == 'on']['execution_time_ms'].values
    gpu_off = test_data[test_data['gpu_enabled'] == 'off']['execution_time_ms'].values
    
    if len(gpu_on) > 0 and len(gpu_off) > 0:
        return ((gpu_off[0] - gpu_on[0]) / gpu_off[0]) * 100
    return 0

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("사용법: python3 analyze_results.py <csv_file>")
        sys.exit(1)
    
    analyze_results(sys.argv[1])
