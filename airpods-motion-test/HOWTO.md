# 다시 돌리는 법

모든 경로는 이 폴더(`airpods-motion-test/`) 기준 상대 경로라서, 저장소를 어디에 내려받아도 그대로 돌아갑니다.
파이썬 코드는 numpy, pandas, scipy, matplotlib 이 필요합니다.

## 1. 분석 · 그래프 다시 만들기 (아이폰 없이)

```bash
python3 tools/analyze_bgtest.py                 # 백그라운드 실험: 센서 값이 끊긴 구간 표
python3 tools/analyze_stretch.py                # 동작 구분: 같은 동작 vs 다른 동작 거리 비교
python3 analysis.py                             # 센서 값 표 + pitch 그래프 (csv/ 폴더의 기록 3개)
cd summary && python3 build_summary.py          # 실험별 표(data/*.csv)와 그래프(charts/*.png)를 다시 만듦
```

## 2. 앱을 내 아이폰에 설치

```bash
cd techtest-app
./build_and_install.sh <내 Team ID> <내 Bundle ID>        # 예: ./build_and_install.sh ABCDE12345 com.myname.techtest
./build_and_install.sh <Team ID> <Bundle ID> --build-only  # 설치 없이 빌드만
```

- Team ID: Xcode > Settings > Accounts 에서 확인하는 10자리 값. Bundle ID: 본인이 쓸 수 있는 아무 이름.
- 아이폰은 케이블로 연결하고 잠금을 풀고, 개발자 모드를 켜 둡니다. 처음 실행할 때 설정 > 일반 > VPN 및 기기 관리에서 개발자 앱을 신뢰합니다.
- 서명 값은 명령어로만 넘기고 프로젝트 파일은 바뀌지 않습니다. (필요 환경: Xcode, iOS 26.1 이상 아이폰. AlarmKit 화면은 iOS 26.1 이상에서만 동작)
- 앱 안에서 하는 테스트와 확인 항목은 `techtest-app/TESTING.md`, `techtest-app/TESTING_BGM.md` 에 있습니다.

## 3. 테스트 로그를 아이폰에서 가져와 분석

```bash
cd techtest-app
./pull_logs.sh <내 Bundle ID>        # 앱의 로그를 summary/data/raw_logs/ 로 복사
cd .. && python3 tools/analyze_bgtest.py
```

## 4. BGM 음원 바꾸기

- 앱은 `techtest-app/AirPodsProMotion/Audio/bgm.caf` 파일 하나만 재생합니다. 이 파일을 다른 곡으로 바꾸고 2번을 다시 하면 됩니다.
- 기본 곡은 직접 합성한 것이며 `python3 tools/make_bgm.py` 로 다시 만들 수 있습니다.

## 5. 스트레칭 가이드 동작 바꾸기

- `techtest-app/AirPodsProMotion/TechTest/StretchMission.swift` 의 `keyframes` 배열만 고치면 됩니다.
