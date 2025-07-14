#!/usr/bin/env python3
"""
PG-Strom 실험 결과 자동 보고서 생성 스크립트
재솔님과 함께 작성 - 의존성 최소화 버전
"""

import os
import sys
import json
import csv
from datetime import datetime
from pathlib import Path
import re

class PGStromReportGenerator:
    def __init__(self, result_dir):
        self.result_dir = Path(result_dir)
        self.timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        self.report_data = {}
        
    def analyze_results(self):
        """실험 결과 분석"""
        print("[INFO] 실험 결과 분석 중...")
        
        # CSV 파일 읽기
        csv_file = self.result_dir / "summary.csv"
        if not csv_file.exists():
            print(f"[ERROR] 결과 파일을 찾을 수 없습니다: {csv_file}")
            return False
            
        try:
            results = {}
            with open(csv_file, 'r') as f:
                reader = csv.DictReader(f)
                
                # 데이터 그룹화 (8회 반복 데이터 처리)
                test_data = {}
                for row in reader:
                    # 헤더 중복 건너뛰기
                    if row['test_name'] == 'test_name':
                        continue
                        
                    test_name = row['test_name']
                    gpu_enabled = row['gpu_enabled']
                    exec_time = float(row['execution_time_ms'])
                    
                    if test_name not in test_data:
                        test_data[test_name] = {}
                    if gpu_enabled not in test_data[test_name]:
                        test_data[test_name][gpu_enabled] = []
                    
                    test_data[test_name][gpu_enabled].append(exec_time)
                
                # 성능 비교 계산 (8회 평균 사용)
                for test_name, data in test_data.items():
                    if 'on' in data and 'off' in data:
                        # 8회 실행 결과의 평균 계산
                        gpu_on_avg = sum(data['on']) / len(data['on'])
                        gpu_off_avg = sum(data['off']) / len(data['off'])
                        
                        # 표준편차 및 분산 계산
                        gpu_on_var = sum((x - gpu_on_avg) ** 2 for x in data['on']) / len(data['on'])
                        gpu_off_var = sum((x - gpu_off_avg) ** 2 for x in data['off']) / len(data['off'])
                        gpu_on_std = gpu_on_var ** 0.5
                        gpu_off_std = gpu_off_var ** 0.5
                        
                        improvement = ((gpu_off_avg - gpu_on_avg) / gpu_off_avg) * 100
                        
                        results[test_name] = {
                            'gpu_on': gpu_on_avg,
                            'gpu_off': gpu_off_avg,
                            'gpu_on_std': gpu_on_std,
                            'gpu_off_std': gpu_off_std,
                            'gpu_on_var': gpu_on_var,
                            'gpu_off_var': gpu_off_var,
                            'gpu_on_cv': (gpu_on_std / gpu_on_avg) * 100 if gpu_on_avg > 0 else 0,
                            'gpu_off_cv': (gpu_off_std / gpu_off_avg) * 100 if gpu_off_avg > 0 else 0,
                            'gpu_on_min': min(data['on']),
                            'gpu_on_max': max(data['on']),
                            'gpu_off_min': min(data['off']),
                            'gpu_off_max': max(data['off']),
                            'improvement_percent': improvement,
                            'faster': 'GPU' if gpu_on_avg < gpu_off_avg else 'CPU',
                            'runs_count': len(data['on'])
                        }
            
            self.report_data['performance_results'] = results
            return True
            
        except Exception as e:
            print(f"[ERROR] 결과 분석 중 오류 발생: {e}")
            return False
    
    def extract_system_info(self):
        """시스템 정보 추출"""
        print("[INFO] 시스템 정보 추출 중...")
        
        system_file = self.result_dir / "system_info.txt"
        if not system_file.exists():
            print(f"[WARN] 시스템 정보 파일을 찾을 수 없습니다: {system_file}")
            return
            
        try:
            with open(system_file, 'r') as f:
                content = f.read()
                
            # CUDA 버전 추출 (12.9 지원)
            cuda_match = re.search(r'CUDA 버전: ([\d.]+)', content)
            if not cuda_match:
                cuda_match = re.search(r'CUDA Version: ([\d.]+)', content)
            cuda_version = cuda_match.group(1) if cuda_match else "Unknown"
            
            # GPU 모델 추출 (L40S 지원)
            gpu_match = re.search(r'NVIDIA (L40S|GeForce RTX \d+|A\d+|H\d+)', content)
            gpu_model = gpu_match.group(0) if gpu_match else "NVIDIA GPU"
            
            # GPU 개수 추출
            gpu_count_match = re.search(r'GPU 개수: (\d+)', content)
            gpu_count = gpu_count_match.group(1) if gpu_count_match else "1"
            
            # 메모리 정보 추출 (46GB L40S 지원)
            memory_match = re.search(r'(\d+)MiB', content)
            if memory_match:
                memory_mb = int(memory_match.group(1))
                gpu_memory = f"{memory_mb}MB"
                if memory_mb > 40000:  # 40GB 이상이면 GB 단위로 표시
                    gpu_memory = f"{memory_mb//1024}GB"
            else:
                gpu_memory = "Unknown"
            
            self.report_data['system_info'] = {
                'cuda_version': cuda_version,
                'gpu_model': gpu_model,
                'gpu_count': gpu_count,
                'gpu_memory': gpu_memory,
                'timestamp': self.timestamp
            }
            
        except Exception as e:
            print(f"[WARN] 시스템 정보 추출 중 오류: {e}")
            self.report_data['system_info'] = {
                'cuda_version': 'Unknown',
                'gpu_model': 'NVIDIA GPU',
                'gpu_count': '1',
                'gpu_memory': 'Unknown',
                'timestamp': self.timestamp
            }
    
    def analyze_detailed_results(self):
        """상세 실험 결과 분석"""
        print("[INFO] 상세 결과 분석 중...")
        
        detailed_analysis = {}
        
        # 각 테스트 파일에서 GPU 처리량 추출
        for test_file in self.result_dir.glob("*_on.txt"):
            test_name = test_file.stem.replace("_on", "")
            
            try:
                with open(test_file, 'r') as f:
                    content = f.read()
                
                # GPU 실행 정보 추출
                gpu_exec_match = re.search(r'exec: (\d+)', content)
                if gpu_exec_match:
                    gpu_exec_count = int(gpu_exec_match.group(1))
                    detailed_analysis[test_name] = {
                        'gpu_exec_count': gpu_exec_count,
                        'gpu_utilized': gpu_exec_count > 0
                    }
                
            except Exception as e:
                print(f"[WARN] {test_file} 분석 중 오류: {e}")
        
        self.report_data['detailed_analysis'] = detailed_analysis
    
    def generate_markdown_report(self):
        """마크다운 보고서 생성"""
        print("[INFO] 마크다운 보고서 생성 중...")
        
        system_info = self.report_data.get('system_info', {})
        gpu_model = system_info.get('gpu_model', 'NVIDIA GPU')
        gpu_memory = system_info.get('gpu_memory', 'Unknown')
        gpu_count = system_info.get('gpu_count', '1')
        cuda_version = system_info.get('cuda_version', 'Unknown')
        
        report_content = f"""# PG-Strom GPU 가속 성능 분석 보고서

**작성자**: 신재솔  
**작성일**: {self.timestamp}  
**실험 환경**: {gpu_model} x{gpu_count} (CUDA {cuda_version})

## 1. 실험 개요

본 실험은 PG-Strom을 사용한 PostgreSQL GPU 가속 성능을 분석하기 위해 수행되었습니다.

### 실험 방법론
- 매 실행 전 PostgreSQL shared_buffers 및 OS 페이지 캐시 클리어
- 통계적 신뢰성을 위한 다중 반복 실행
- 평균, 표준편차, 분산, 변동계수 산출

### 실험 환경
- GPU: {gpu_model} x{gpu_count}
- GPU 메모리: {gpu_memory} (per GPU)
- CUDA 버전: {cuda_version}
- 실험 일시: {self.timestamp}

## 2. 실험 결과

### 성능 비교 결과 (반복 실행 평균)

| 테스트 케이스 | GPU 활성화 (ms) | GPU 비활성화 (ms) | 성능 향상 | 우수한 방식 |
|---------------|----------------|------------------|-----------|------------|
"""
        
        # 성능 결과 테이블 생성
        performance_results = self.report_data.get('performance_results', {})
        for test_name, result in performance_results.items():
            test_display = test_name.replace('_', ' ').title()
            gpu_on = f"{result['gpu_on']:.1f}±{result['gpu_on_std']:.1f}"
            gpu_off = f"{result['gpu_off']:.1f}±{result['gpu_off_std']:.1f}"
            improvement = f"{result['improvement_percent']:.1f}%"
            faster = result['faster']
            
            report_content += f"| {test_display} | {gpu_on} | {gpu_off} | {improvement} | {faster} |\n"
        
        report_content += """
### 상세 통계 정보

"""
        
        # 상세 통계 정보 추가
        for test_name, result in performance_results.items():
            test_display = test_name.replace('_', ' ').title()
            report_content += f"""
#### {test_display}
- **GPU 활성화**: 평균 {result['gpu_on']:.1f}ms
  - 표준편차: {result['gpu_on_std']:.1f}ms, 분산: {result['gpu_on_var']:.1f}ms²
  - 변동계수: {result['gpu_on_cv']:.1f}%
  - 최소: {result['gpu_on_min']:.1f}ms, 최대: {result['gpu_on_max']:.1f}ms
- **GPU 비활성화**: 평균 {result['gpu_off']:.1f}ms
  - 표준편차: {result['gpu_off_std']:.1f}ms, 분산: {result['gpu_off_var']:.1f}ms²
  - 변동계수: {result['gpu_off_cv']:.1f}%
  - 최소: {result['gpu_off_min']:.1f}ms, 최대: {result['gpu_off_max']:.1f}ms
- **반복 횟수**: {result['runs_count']}회
"""
        
        report_content += """
## 3. 상세 분석

### GPU 활용도 분석
"""
        
        # GPU 활용도 분석
        detailed_analysis = self.report_data.get('detailed_analysis', {})
        for test_name, analysis in detailed_analysis.items():
            test_display = test_name.replace('_', ' ').title()
            gpu_exec = analysis.get('gpu_exec_count', 0)
            utilized = "활용됨" if analysis.get('gpu_utilized', False) else "활용되지 않음"
            
            report_content += f"- **{test_display}**: GPU 처리량 {gpu_exec:,}건 ({utilized})\n"
        
        report_content += """
## 4. 결론 및 권장사항

### 주요 발견사항
"""
        
        # 성능 분석 결론
        if performance_results:
            gpu_wins = sum(1 for r in performance_results.values() if r['faster'] == 'GPU')
            cpu_wins = sum(1 for r in performance_results.values() if r['faster'] == 'CPU')
            
            report_content += f"- 총 {len(performance_results)}개 테스트 중 GPU가 {gpu_wins}개, CPU가 {cpu_wins}개 테스트에서 우수한 성능을 보였습니다.\n"
            
            # 최고 성능 향상 찾기
            gpu_tests = [(name, result) for name, result in performance_results.items() if result['faster'] == 'GPU']
            if gpu_tests:
                best_gpu_test = max(gpu_tests, key=lambda x: x[1]['improvement_percent'])
                report_content += f"- GPU 가속이 가장 효과적인 테스트: {best_gpu_test[0].replace('_', ' ').title()} ({best_gpu_test[1]['improvement_percent']:.1f}% 향상)\n"
        
        report_content += """
### 권장사항
- 단순 조인 작업의 경우 CPU가 더 효율적일 수 있습니다.
- 실제 워크로드에 따라 GPU 활성화 여부를 결정하는 것이 중요합니다.

## 5. 기술적 세부사항

### 실험 설정
- 테스트 데이터: 최대 5,000만 행
- 측정 방법: PostgreSQL EXPLAIN ANALYZE
- 반복 횟수: 각 테스트 GPU ON/OFF 각 1회

### 측정 지표
- 실행 시간 (ms)
- GPU 처리량 (exec count)
- 메모리 사용량

---
*이 보고서는 PG-Strom 자동화 시스템에 의해 생성되었습니다.*
"""
        
        # 보고서 저장
        report_file = self.result_dir / "performance_report.md"
        with open(report_file, 'w', encoding='utf-8') as f:
            f.write(report_content)
        
        print(f"[INFO] 보고서 생성 완료: {report_file}")
        return report_file
    
    def generate_json_summary(self):
        """JSON 형태의 요약 데이터 생성"""
        print("[INFO] JSON 요약 생성 중...")
        
        summary_file = self.result_dir / "experiment_summary.json"
        with open(summary_file, 'w', encoding='utf-8') as f:
            json.dump(self.report_data, f, indent=2, ensure_ascii=False)
        
        print(f"[INFO] JSON 요약 생성 완료: {summary_file}")
        return summary_file
    
    def generate_quick_summary(self):
        """빠른 요약 생성"""
        print("[INFO] 빠른 요약 생성 중...")
        
        performance_results = self.report_data.get('performance_results', {})
        if not performance_results:
            return
        
        summary_content = f"""PG-Strom 실험 결과 요약 ({self.timestamp})
{'='*50}

"""
        
        for test_name, result in performance_results.items():
            test_display = test_name.replace('_', ' ').title()
            gpu_on = result['gpu_on']
            gpu_off = result['gpu_off']
            gpu_on_std = result['gpu_on_std']
            gpu_off_std = result['gpu_off_std']
            improvement = result['improvement_percent']
            faster = result['faster']
            runs_count = result['runs_count']
            
            summary_content += f"{test_display} ({runs_count}회 반복):\n"
            summary_content += f"  GPU ON:  {gpu_on:.1f}±{gpu_on_std:.1f}ms (CV: {result['gpu_on_cv']:.1f}%)\n"
            summary_content += f"  GPU OFF: {gpu_off:.1f}±{gpu_off_std:.1f}ms (CV: {result['gpu_off_cv']:.1f}%)\n"
            summary_content += f"  성능 향상: {improvement:.1f}% ({faster} 우수)\n\n"
        
        # 요약 저장
        summary_file = self.result_dir / "quick_summary.txt"
        with open(summary_file, 'w', encoding='utf-8') as f:
            f.write(summary_content)
        
        print(f"[INFO] 빠른 요약 생성 완료: {summary_file}")
        return summary_file
    
    def run(self):
        """전체 보고서 생성 프로세스 실행"""
        print(f"[INFO] 보고서 생성 시작: {self.result_dir}")
        
        if not self.analyze_results():
            return False
        
        self.extract_system_info()
        self.analyze_detailed_results()
        
        report_file = self.generate_markdown_report()
        summary_file = self.generate_json_summary()
        quick_summary_file = self.generate_quick_summary()
        
        print(f"[INFO] 보고서 생성 완료!")
        print(f"[INFO] 마크다운 보고서: {report_file}")
        print(f"[INFO] JSON 요약: {summary_file}")
        print(f"[INFO] 빠른 요약: {quick_summary_file}")
        
        return True

def main():
    if len(sys.argv) != 2:
        print("사용법: python generate_report.py <결과_디렉토리>")
        sys.exit(1)
    
    result_dir = sys.argv[1]
    if not os.path.exists(result_dir):
        print(f"[ERROR] 결과 디렉토리가 존재하지 않습니다: {result_dir}")
        sys.exit(1)
    
    generator = PGStromReportGenerator(result_dir)
    success = generator.run()
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main() 