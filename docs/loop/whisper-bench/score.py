#!/usr/bin/env python3
"""Score WhisperKit outputs on the ko20 set: swear recall, false swears, sentence-ending register.
Usage: score.py <model> [<model> ...]  (reads phrases.tsv and rep-<model>/*.json)"""
import json, re, sys, pathlib
HERE = pathlib.Path(__file__).parent
VARIANTS = {"씨발": ["씨발","시발","씨팔","시팔","ㅅㅂ"], "존나": ["존나","졸라","존내"], "개짜증": ["개짜증"],
            "병신": ["병신","븅신"], "미친": ["미친"], "닥쳐": ["닥쳐"], "좆": ["좆","좃"], "꺼져": ["꺼져"]}
ALL = [v for vs in VARIANTS.values() for v in vs]
POLITE_END = re.compile(r"(요|니다|니까|세요|죠)[\s.?!]*$")
def register(text): return "polite" if POLITE_END.search(text.strip()) else "casual"
def load_texts(model):
    texts = {}
    for p in sorted((HERE / f"rep-{model}").glob("*.json")):
        data = json.loads(p.read_text()); m = re.search(r"(p\d\d)", p.name)
        if m and "text" in data: texts[m.group(1)] = data["text"]
    return texts
def main(models):
    rows = [l.split("\t") for l in (HERE / "phrases.tsv").read_text().splitlines() if l.strip()]
    for model in models:
        texts = load_texts(model); hit = miss = false = reg_ok = n = 0
        for pid, _voice, _truth, swear, reg in rows:
            out = texts.get(pid, "").replace(" ", "")  # bench only: the expected swear is known to be present
            n += 1
            if swear != "-":
                ok = any(v in out for v in VARIANTS[swear]); hit += ok; miss += not ok
            else:
                false += any(v in out for v in ALL)
            reg_ok += register(out) == reg
        print(f"{model}: transcribed {len(texts)}/{n}, swear recall {hit}/{hit+miss} = {hit/(hit+miss):.2f}, "
              f"false swears {false}, ending accuracy {reg_ok}/{n} = {reg_ok/n:.2f}")
if __name__ == "__main__": main(sys.argv[1:])
