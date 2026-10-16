import shutil
import subprocess
import sys
from pathlib import Path

# ===== 설정 =====
# 대상 폴더: 폴더를 .bat 위로 끌어놓거나, 인자로 지정. 미지정 시 이 스크립트가 있는 폴더.
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
WORK = Path(SRC.anchor) / "_CAD2015_tmp"  # 임시 작업 폴더(끝나면 자동 삭제)
OUT_VERSION = "ACAD2013"                  # AutoCAD 2013~2017 공용 포맷 (2015에서 열림)
BACKUP = False                            # True: 덮어쓰기 전 원본을 SRC\\_백업_변환전 에 보관
OK_HEADERS = {b"AC1027", b"AC1024", b"AC1021", b"AC1018", b"AC1015",
              b"AC1014", b"AC1012", b"AC1009"}   # 2013 이하: 2015에서 이미 열림
# ================

def header(p: Path) -> bytes:
    with open(p, "rb") as f:
        return f.read(6)

def find_oda() -> Path:
    for base in (Path(r"C:\Program Files\ODA"), Path(r"C:\Program Files (x86)\ODA")):
        if base.exists():
            hits = sorted(base.glob("ODAFileConverter*/ODAFileConverter.exe"))
            if hits:
                return hits[-1]
    sys.exit("ODA File Converter 미설치: https://www.opendesign.com 에서 설치 후 재실행하세요.")

def main():
    if not SRC.exists():
        sys.exit(f"원본 폴더 없음: {SRC}")
    print(f"대상 폴더: {SRC}")
    tmp_in, out = WORK / "in", WORK / "out"
    tmp_in.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)

    targets, skipped = [], 0
    for p in SRC.rglob("*"):
        if p.suffix.lower() != ".dwg" or "_백업_변환전" in p.parts:
            continue
        h = header(p)
        if h in OK_HEADERS:
            skipped += 1
        else:
            targets.append((p, h))

    print(f"변환 대상(2015 미호환): {len(targets)}개 / 이미 호환: {skipped}개")
    for p, h in targets:
        rel = p.relative_to(SRC)
        dst = tmp_in / rel
        dst.parent.mkdir(parents=True, exist_ok=True)   # 하위 폴더 생성(핵심)
        shutil.copy2(p, dst)
        print(f"  복사 [{h.decode(errors='replace')}] {rel}")
    if not targets:
        return

    r = subprocess.run([str(find_oda()), str(tmp_in), str(out),
                        OUT_VERSION, "DWG", "1", "1", "*.DWG"])
    done = len([x for x in out.rglob("*") if x.suffix.lower() == ".dwg"])
    print(f"변환 완료: {done}/{len(targets)}개 (returncode={r.returncode})")

    # 변환 성공 파일만 원본 위치에 덮어쓰기
    ok = fail = 0
    for p, _ in targets:
        rel = p.relative_to(SRC)
        conv = out / rel
        if not conv.exists() or header(conv) != b"AC1027":
            print(f"  [실패-원본유지] {rel}")
            fail += 1
            continue
        if BACKUP:
            bak = SRC / "_백업_변환전" / rel
            bak.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, bak)
        shutil.copy2(conv, p)
        ok += 1
    print(f"덮어쓰기: 성공 {ok}개 / 실패(원본 유지) {fail}개")

if __name__ == "__main__":
    try:
        main()
    finally:
        shutil.rmtree(WORK, ignore_errors=True)   # 임시 폴더 정리
