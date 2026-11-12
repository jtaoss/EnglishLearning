"""Explicit, read-only reference collection for the selected 100-word pilot.

No package installation, commercial dictionary scraping, or model API calls.
WordNet is Princeton's redistributable reference, not an exam/frequency source.
"""

import hashlib
import html
import json
import re
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/p6/p6c"
CACHE = ROOT / "private/p6c/reference"
WORDNET_URL = "https://wordnetcode.princeton.edu/wn3.1.dict.tar.gz"
PRICING_URL = "https://developers.openai.com/api/docs/pricing"


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "EnglishLearning-P6C/2"})
    with urllib.request.urlopen(request, timeout=40) as response:
        return response.read()


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    archive = CACHE / "wn3.1.dict.tar.gz"
    if not archive.exists():
        archive.write_bytes(fetch(WORDNET_URL))
    selected = json.loads((OUT / "selection.json").read_text(encoding="utf-8"))
    heads = {r["word"].lower() for group in selected["groups"].values() for r in group}
    senses = {head: [] for head in sorted(heads)}
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            if Path(member.name).name not in {"data.noun", "data.verb", "data.adj", "data.adv"}:
                continue
            for raw in tar.extractfile(member):
                line = raw.decode("utf-8").strip("\r\n")
                if not line or line.startswith(" "):
                    continue
                header, gloss = line.split("|", 1)
                parts = header.split()
                count = int(parts[3], 16)
                lemmas = [parts[4 + i * 2].split("(")[0] for i in range(count)]
                for head in heads.intersection(lemmas):
                    senses[head].append({
                        "evidence_id": f"wn31:{parts[2]}:{parts[0]}",
                        "pos": parts[2],
                        "definition_en": gloss.strip(),
                    })
    evidence = {
        "source": WORDNET_URL,
        "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
        "license": "assets/vocabulary/WORDNET_3_1_LICENSE.txt",
        "scope": "selected_100_only",
        "limitations": "Definitions establish sense/POS compatibility, never usage frequency or official exam focus. English definitions are licensed WordNet text; Chinese decisions are separate AI judgments.",
        "headwords": senses,
    }
    (OUT / "wordnet_evidence.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    page = fetch(PRICING_URL)
    text = page.decode("utf-8")
    text = re.sub(r"<script\b[^>]*>.*?</script>|<style\b[^>]*>.*?</style>", "", text, flags=re.S)
    text = html.unescape(re.sub(r"\s+", " ", re.sub("<[^>]+>", " ", text)))
    start = text.index("Flagship models")
    section = text[start:text.index("Regional processing", start)]
    rates = {}
    for model in ("gpt-6.1-sol", "gpt-6-luna"):
        match = re.search(re.escape(model) + r" \$([\d.]+) \$([\d.]+)", section)
        if match is None:
            raise ValueError(f"Pricing format changed: {model}; do not guess rates")
        rates[model] = {"input_usd_per_million": float(match[1]), "output_usd_per_million": float(match[2])}
    pricing = {
        "source": PRICING_URL,
        "accessed_date_asia_shanghai": "2026-11-12",
        "page_sha256": hashlib.sha256(page).hexdigest(),
        "mode": "Standard, short context; no caching, batch, or promotional assumptions",
        "rates": rates,
    }
    (OUT / "pricing_reference.json").write_text(json.dumps(pricing, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"selected_heads": len(senses), "matched_heads": sum(bool(v) for v in senses.values()), "rates": rates}))


if __name__ == "__main__":
    main()
