import shutil
import subprocess
import sys
from pathlib import Path

# ===== 설정 =====
SRC = Path(r"D:\01.업무데이터\A07.2026년 Project\20.역삼동 678-11 업무시설_26.10.15~")
WORK = Path(r"D:\_CAD2015")               # 경로 길이 절약을 위해 짧은 경로 사용
OUT_VERSION = "ACAD2013"                  # AutoCAD 2013~2017 공용 포맷 (2015에서 열림)
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
    tmp_in, out = WORK / "in", WORK / "out"
    tmp_in.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)

    targets, skipped = [], 0
    for p in SRC.rglob("*"):
        if p.suffix.lower() != ".dwg" or WORK in p.parents:
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
    print(f"완료: {done}/{len(targets)}개 (returncode={r.returncode}) → {out}")

if __name__ == "__main__":
    main()
