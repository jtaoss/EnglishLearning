"""Build the isolated P6-C core-meaning pilot from the formal CSV.

The formal meaning_zh field is only read. Nothing here writes the vocabulary
CSV, Notion, or a learning database.
"""

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SELECTION = ROOT / "docs" / "p6" / "p6c" / "selection.json"
OUT = ROOT / "docs" / "p6" / "p6c" / "core_meanings_pilot.json"

MODEL_VERSION = "p6c-core-1"
PROMPT_VERSION = "p6c-prompt-1"

POS_LABEL = re.compile(
    r"^(名词|动词|形容词|副词|介词|连词|代词|数词|限定词|助动词|系动词|情态动词|感叹词|名词和动词)[:：](.+)$"
)


def atoms(meaning):
    found = []
    for segment in meaning.split("；"):
        segment = segment.strip()
        if not segment:
            continue
        match = POS_LABEL.match(segment)
        body = match.group(2) if match else segment
        for gloss in body.split("，"):
            gloss = gloss.strip()
            if gloss:
                found.append(gloss)
    return found


def group(layer, pos, glosses):
    return {
        "layer": layer,
        "part_of_speech": pos,
        "glosses": glosses,
        "origin": "formal_gloss",
    }


def source_hash(row):
    payload = f"{row['entry_id']}\n{row['meaning_zh']}\n{row['part_of_speech']}"
    return hashlib.sha256(payload.encode()).hexdigest()


# Explicit layouts. Every formal gloss atom must appear.
# review_required stays true whenever the order is a model judgment rather
# than something the formal field itself proves.
LAYOUTS = {
    "double": [
        group("core", "形容词", ["双倍的", "成双的"]),
        group("extended", "动词", ["使加倍"]),
        group("extended", "名词", ["两倍"]),
        group("extended", "副词", ["加倍地"]),
        group("other", "名词", ["替身"]),
    ],
    "brief": [
        group("core", "形容词", ["简短的"]),
        group("extended", "名词", ["概要"]),
        group("other", "动词", ["向……介绍情况"]),
    ],
    "close": [
        group("core", "动词", ["关闭"]),
        group("extended", "形容词", ["近的"]),
        group("extended", "副词", ["靠近"]),
        group("other", "形容词", ["亲密的"]),
    ],
    "rear": [
        group("core", "名词", ["后部"]),
        group("extended", "形容词", ["后面的"]),
        group("other", "动词", ["养育"]),
    ],
    "back": [
        group("core", "名词", ["背部", "后面"]),
        group("extended", "副词", ["返回", "向后"]),
        group("other", "动词", ["支持"]),
    ],
    "void": [
        group("core", "形容词", ["无效的"]),
        group("core", "形容词", ["空的"]),
        group("extended", "动词", ["使无效"]),
        group("other", "名词", ["空白"]),
    ],
    "present": [
        group("core", "名词", ["礼物"]),
        group("core", "形容词", ["当前的"]),
        group("extended", "名词", ["现在"]),
        group("extended", "形容词", ["在场的"]),
        group("extended", "动词", ["呈交", "展示"]),
    ],
    "major": [
        group("core", "形容词", ["主要的"]),
        group("extended", "名词", ["专业"]),
        group("extended", "动词", ["主修"]),
    ],
    "mean": [
        group("core", "动词", ["意味着"]),
        group("core", "动词", ["打算"]),
        group("extended", "形容词", ["平均的"]),
        group("extended", "名词", ["平均数"]),
        group("other", "形容词", ["吝啬的"]),
    ],
    "parallel": [
        group("core", "形容词", ["平行的"]),
        group("extended", "形容词", ["相似的"]),
        group("extended", "名词", ["相似情况"]),
        group("extended", "动词", ["与……相似或并行"]),
    ],
    "slack": [
        group("core", "形容词", ["松弛的"]),
        group("extended", "形容词", ["不严格的"]),
        group("extended", "动词", ["懈怠", "放松"]),
        group("other", "名词", ["松弛部分"]),
    ],
    "model": [
        group("core", "名词", ["模型"]),
        group("extended", "名词", ["模特"]),
        group("extended", "名词", ["典范"]),
        group("extended", "形容词", ["模范的"]),
        group("other", "动词", ["建模", "模仿"]),
    ],
    "light": [
        group("core", "名词", ["光", "灯"]),
        group("core", "形容词", ["轻的"]),
        group("extended", "形容词", ["明亮的"]),
        group("extended", "动词", ["点燃"]),
    ],
    "well": [
        group("core", "副词", ["好地"]),
        group("extended", "形容词", ["健康的"]),
        group("extended", "名词", ["井"]),
    ],
    "subject": [
        group("core", "名词", ["学科"]),
        group("core", "名词", ["主题"]),
        group("extended", "名词", ["对象"]),
        group("other", "动词", ["使遭受"]),
        group("other", "形容词", ["受……约束的"]),
    ],
    "tender": [
        group("core", "形容词", ["温柔的"]),
        group("extended", "形容词", ["嫩的"]),
        group("other", "名词", ["投标"]),
        group("other", "动词", ["提出", "投标"]),
    ],
    "reverse": [
        group("core", "形容词", ["相反的"]),
        group("core", "动词", ["颠倒"]),
        group("extended", "动词", ["倒车"]),
        group("extended", "名词", ["反面"]),
        group("other", "名词", ["倒退"]),
    ],
    "fake": [
        group("core", "形容词", ["假的"]),
        group("extended", "名词", ["赝品"]),
        group("extended", "动词", ["伪造"]),
    ],
    "abstract": [
        group("core", "形容词", ["抽象的"]),
        group("extended", "名词", ["摘要"]),
        group("extended", "动词", ["概括"]),
        group("other", "动词", ["提取"]),
    ],
    "minor": [
        group("core", "形容词", ["较小的", "次要的"]),
        group("extended", "名词", ["未成年人"]),
        group("other", "动词", ["辅修"]),
    ],
    "volume": [
        group("core", "名词", ["体积"]),
        group("core", "名词", ["音量"]),
        group("extended", "名词", ["卷册"]),
    ],
    "bank": [
        group("core", "名词", ["银行"]),
        group("extended", "名词", ["河岸"]),
    ],
    "run": [
        group("core", "动词", ["跑"]),
        group("extended", "动词", ["经营"]),
    ],
    "date": [
        group("core", "名词", ["日期"]),
        group("extended", "名词", ["约会"]),
    ],
    "yard": [
        group("core", "名词", ["院子"]),
        group("extended", "名词", ["码"]),
    ],
    "miss": [
        group("core", "动词", ["错过"]),
        group("core", "动词", ["想念"]),
    ],
    "quarter": [
        group("core", "名词", ["四分之一"]),
        group("core", "名词", ["一刻钟"]),
        group("extended", "名词", ["季度"]),
        group("other", "名词", ["地区"]),
    ],
    "get": [
        group("core", "动词", ["得到"]),
        group("core", "动词", ["变得"]),
        group("extended", "动词", ["到达"]),
        group("other", "动词", ["理解"]),
    ],
    "term": [
        group("core", "名词", ["术语"]),
        group("core", "名词", ["学期"]),
        group("extended", "名词", ["期限"]),
        group("other", "名词", ["条款"]),
    ],
    "bill": [
        group("core", "名词", ["账单"]),
        group("extended", "名词", ["钞票"]),
        group("extended", "名词", ["法案"]),
        group("other", "名词", ["鸟嘴"]),
    ],
    "keep": [
        group("core", "动词", ["保持"]),
        group("extended", "动词", ["继续"]),
        group("extended", "动词", ["保管"]),
        group("other", "动词", ["饲养"]),
    ],
    "shot": [
        group("core", "名词", ["射击"]),
        group("extended", "名词", ["照片"]),
        group("extended", "名词", ["尝试"]),
        group("other", "名词", ["注射"]),
    ],
    "division": [
        group("core", "名词", ["划分"]),
        group("extended", "名词", ["部门"]),
        group("extended", "名词", ["除法"]),
        group("other", "名词", ["分歧"]),
    ],
    "course": [
        group("core", "名词", ["课程"]),
        group("extended", "名词", ["过程"]),
        group("extended", "名词", ["路线"]),
        group("extended", "名词", ["一道菜"]),
    ],
    "case": [
        group("core", "名词", ["情况"]),
        group("core", "名词", ["箱子"]),
        group("extended", "名词", ["案例"]),
        group("extended", "名词", ["案件"]),
    ],
    "raise": [
        group("core", "动词", ["举起"]),
        group("extended", "动词", ["提高"]),
        group("extended", "动词", ["养育"]),
        group("other", "动词", ["筹集"]),
    ],
    "hold": [
        group("core", "动词", ["握住"]),
        group("extended", "动词", ["保持"]),
        group("extended", "动词", ["举行"]),
        group("other", "动词", ["容纳"]),
    ],
    "resolution": [
        group("core", "名词", ["决心"]),
        group("extended", "名词", ["解决"]),
        group("extended", "名词", ["决议"]),
        group("other", "名词", ["分辨率"]),
    ],
    "tone": [
        group("core", "名词", ["语气"]),
        group("extended", "名词", ["音调"]),
        group("extended", "名词", ["色调"]),
    ],
    "aisle": [
        group("core", "名词", ["过道", "狭长通道"]),
        group("other", "名词", ["林中小径"]),
    ],
    "procedure": [
        group("core", "名词", ["程序", "手续"]),
        group("extended", "名词", ["过程"]),
    ],
    "presence": [
        group("core", "名词", ["存在"]),
        group("extended", "名词", ["出席"]),
    ],
    "extension": [
        group("core", "名词", ["扩展", "延长"]),
        group("other", "名词", ["分机"]),
    ],
    "engage": [
        group("core", "动词", ["从事", "从事于"]),
        group("extended", "动词", ["实行"]),
    ],
    "payment": [
        group("core", "名词", ["付款"]),
        group("extended", "名词", ["报酬"]),
    ],
    "settlement": [
        group("core", "名词", ["解决"]),
        group("extended", "名词", ["结算"]),
        group("other", "名词", ["定居点"]),
    ],
    "worthy": [
        group("core", "形容词", ["值得的"]),
        group("extended", "形容词", ["值得尊敬的"]),
    ],
    "advanced": [
        group("core", "形容词", ["高级的", "先进的"]),
        group("extended", "形容词", ["处于较后阶段的"]),
    ],
    "agent": [
        group("core", "名词", ["代理人", "经纪人"]),
        group("extended", "名词", ["起作用的因素"]),
    ],
    "react": [
        group("core", "动词", ["作出反应", "起反应"]),
        group("extended", "动词", ["反对"]),
    ],
    "adapt": [
        group("core", "动词", ["使适应"]),
        group("extended", "动词", ["改编"]),
        group("extended", "动词", ["调整"]),
    ],
    "anxious": [
        group("core", "形容词", ["焦虑的"]),
        group("extended", "形容词", ["渴望的"]),
    ],
    "stewardess": [
        group("core", "名词", ["女乘务员"]),
        group("extended", "名词", ["空中小姐（带性别色彩的旧称）"]),
    ],
    "graphic": [
        group("core", "形容词", ["图形的"]),
        group("extended", "形容词", ["生动的"]),
    ],
    "chamber": [
        group("core", "名词", ["室"]),
        group("extended", "名词", ["议院"]),
    ],
    "carve": [
        group("core", "动词", ["雕刻"]),
        group("extended", "动词", ["切开"]),
    ],
    "flush": [
        group("core", "动词", ["冲洗"]),
        group("extended", "动词", ["脸红"]),
        group("extended", "名词", ["红晕"]),
        group("extended", "名词", ["冲洗"]),
    ],
    "knock": [
        group("core", "动词", ["敲"]),
        group("extended", "动词", ["碰撞"]),
    ],
    "cripple": [
        group("core", "动词", ["使残疾"]),
        group("extended", "动词", ["使瘫痪"]),
    ],
    "chop": [
        group("core", "动词", ["砍", "切"]),
        group("extended", "名词", ["排骨"]),
    ],
    "layer": [
        group("core", "名词", ["层"]),
        group("extended", "动词", ["分层放置"]),
    ],
    "consumption": [
        group("core", "名词", ["消费", "消耗"]),
        group("extended", "名词", ["摄入量"]),
    ],
    "notify": [
        group("core", "动词", ["通知"]),
        group("extended", "动词", ["使注意"]),
    ],
    "fuss": [
        group("core", "名词", ["大惊小怪"]),
        group("extended", "动词", ["过分操心"]),
    ],
}

REASONS = {
    "light": "正式释义把形容词“轻的，明亮的”写在同一组，但重量和亮度不是同一个意思，试点拆开。优先记忆保留“光、灯”和“轻的”。这不是使用频率统计。",
    "void": "“无效的”和“空的”在正式字段里用逗号连在一起，语义不同，不能合并。",
    "mean": "动词的“意味着”和“打算”、形容词的“吝啬的”和“平均的”都是不同意思。平均义放在扩展层，吝啬义保留在其他层。",
    "present": "礼物、当前、在场、呈交不是一个意思。优先记忆先放礼物和“当前的”，因为这是面向初学的建议，不是考纲结论。",
    "close": "“近的”和“亲密的”相关但范围不同，没有按原文字段合成一个义项。",
    "model": "模型、模特、典范是三个名词义，正式字段用逗号连写。试点分开，不把模特当成模型的同义词。",
    "rear": "动词“养育”和名词“后部”无关。词性分开后，“养育”不进入优先记忆。",
    "bill": "“鸟嘴”保留，但不放在优先记忆。正式字段把它和账单、法案、钞票并列，试点认为它不是 PETS-3 初学时首先要记的义项。这一排序需要人工确认。",
    "aisle": "正式字段把“林中小径”写在最前。试点改把更通用的“过道”放进优先记忆，并把“林中小径”放到其他层。这是相对原文字段顺序的调整，必须人工审核。",
    "quarter": "四分之一和一刻钟都保留为优先记忆。地区义较窄，放到其他层，不删除。",
    "get": "得到、变得、到达、理解都保留。优先两项是模型对初学适用性的判断，没有语料频率证据。",
    "miss": "错过和想念都是常用且不同的动词义，所以优先记忆放了两组。",
    "bank": "银行和河岸都保留。银行放在前面沿用了正式字段顺序，并按日常英语教学里更常见的义项来建议；不是考研词频，也不是官方重点。",
    "notify": "正式字段先写“使注意”。试点把更直接的“通知”放到优先记忆，这是顺序调整，需要审核。",
    "flush": "脸红和冲洗不是同一个动词义。正式字段用逗号连写，试点拆开，冲洗放在优先记忆只是建议。",
    "settlement": "定居点、解决、结算是三个名词义。解决放在优先记忆是建议，另外两个都保留。",
    "extension": "分机和扩展不是同义词。分机留在其他层。",
    "presence": "出席和存在不是同义词。",
    "stewardess": "优先记忆用“女乘务员”。正式字段里的括注说明“空中小姐”是带性别色彩的旧称，该括注原样留在扩展层。",
    "well": "好地、健康的、井是三个不同词性的常用义。优先记忆只先放副词，另外两个进入扩展层。排序没有频率证据。",
}

RISKS = {
    "light": ["source_merged_different_senses"],
    "void": ["source_merged_different_senses"],
    "mean": ["source_merged_different_senses", "uncertain_rank"],
    "present": ["source_merged_different_senses", "uncertain_rank"],
    "close": ["source_merged_different_senses"],
    "model": ["source_merged_different_senses"],
    "parallel": ["source_merged_different_senses"],
    "tender": ["source_merged_different_senses"],
    "slack": ["source_merged_different_senses"],
    "flush": ["source_merged_different_senses", "uncertain_rank"],
    "bill": ["rare_sense_not_first", "uncertain_rank"],
    "aisle": ["reordered_from_source", "rare_sense_not_first"],
    "quarter": ["rare_sense_not_first", "uncertain_rank"],
    "notify": ["reordered_from_source"],
    "get": ["uncertain_rank"],
    "hold": ["uncertain_rank"],
    "case": ["uncertain_rank"],
    "resolution": ["uncertain_rank"],
    "shot": ["uncertain_rank"],
    "course": ["uncertain_rank"],
    "well": ["uncertain_rank"],
    "subject": ["uncertain_rank"],
    "back": ["uncertain_rank"],
    "double": ["rare_sense_not_first"],
    "knock": ["pos_not_marked_on_gloss"],
    "settlement": ["uncertain_rank"],
    "graphic": ["source_merged_different_senses"],
}


def default_layout(row):
    pos_parts = row["pos_parts"]
    fallback_pos = pos_parts[0] if len(pos_parts) == 1 else ""
    blocks = []
    for segment in row["meaning_zh"].split("；"):
        segment = segment.strip()
        if not segment:
            continue
        match = POS_LABEL.match(segment)
        if match:
            pos = match.group(1)
            glosses = [item.strip() for item in match.group(2).split("，") if item.strip()]
        else:
            pos = fallback_pos
            glosses = [item.strip() for item in segment.split("，") if item.strip()]
        blocks.append((pos, glosses))
    layers = []
    for index, (pos, glosses) in enumerate(blocks):
        layer = "core" if index == 0 else "extended" if index == 1 else "other"
        layers.append(group(layer, pos, glosses))
    return layers


def explanation_for(word, layers):
    if word in REASONS:
        return REASONS[word]
    core = [gloss for item in layers if item["layer"] == "core" for gloss in item["glosses"]]
    if len(layers) == 1 and len(core) == 1:
        return f"正式释义只有“{core[0]}”，核心层原样保留。"
    if len(layers) == 1:
        return "这些中文写在同一组，试点视为同一优先记忆组，没有删去任何原文字。"
    return "优先记忆采用上面的核心义。其余义项仍保留在扩展或其他层，正式释义原文没有删除。"


def reason_for(word, row, layers):
    if word in REASONS:
        return REASONS[word]
    if len(layers) == 1 and len(row["sense_segments"]) == 1:
        return "正式字段只有一个义项和一个词性。核心层复制该义项，不另造含义。"
    if len(layers) == 1:
        return "正式字段用分号或逗号列出的文字被视为同一组近义表达。没有证据把它们分成不同语义，因此不拆开，也不声称哪一个更常考。"
    return "多项义项都保留。未单独写明的排序沿用正式字段顺序，只作为建议，不是使用频率证据。"


def confidence_for(word, layers, review_required):
    if word in {"light", "bill", "aisle", "mean", "present", "get", "flush"}:
        return 0.55
    if review_required:
        return 0.6
    if len(layers) == 1:
        return 0.8
    return 0.7


def review_required_for(word, row, layers):
    if word in RISKS or word in REASONS:
        return True
    if len(row["sense_segments"]) > 1 or len(row["pos_parts"]) > 1:
        return True
    return False


def build_record(row):
    word = row["word"]
    layers = LAYOUTS.get(word.lower(), default_layout(row))
    missing = [
        atom
        for atom in atoms(row["meaning_zh"])
        if atom not in {gloss for item in layers for gloss in item["glosses"]}
    ]
    if missing:
        raise SystemExit(f"{word} dropped formal glosses: {missing}")
    review_required = review_required_for(word, row, layers)
    example = None
    if row["example_en"].strip():
        example = {
            "en": row["example_en"].strip(),
            "zh": row["example_zh"].strip(),
            "origin": "formal_example",
        }
    return {
        "stable_id": row["entry_id"],
        "headword": word,
        "part_of_speech": row["part_of_speech"],
        "book_category": row["book_category"],
        "library_class": row["library_class"],
        "cohort": row["cohort"],
        "original_meaning_zh": row["meaning_zh"],
        "core_meanings": [item for item in layers if item["layer"] == "core"],
        "extended_meanings": [item for item in layers if item["layer"] == "extended"],
        "other_meanings": [item for item in layers if item["layer"] == "other"],
        "core_explanation": explanation_for(word.lower(), layers),
        "usage_example": example,
        "selection_reason": reason_for(word.lower(), row, layers),
        "confidence": confidence_for(word.lower(), layers, review_required),
        "review_required": review_required,
        "model_added_senses": [],
        "risk_flags": RISKS.get(word.lower(), []),
        "model_version": MODEL_VERSION,
        "prompt_version": PROMPT_VERSION,
        "source_hash": source_hash(row),
        "lexical_sources": row["lexical_sources"],
        "pets2015_status": row["pets2015_status"],
        "official_exam_focus": False,
    }


def main():
    selection = json.loads(SELECTION.read_text(encoding="utf-8"))
    records = []
    for rows in selection["groups"].values():
        records.extend(build_record(row) for row in rows)
    ids = [record["stable_id"] for record in records]
    if len(ids) != 100 or len(set(ids)) != 100:
        raise SystemExit(f"expected 100 unique ids, got {len(ids)} / {len(set(ids))}")
    cohorts = {}
    for record in records:
        cohorts[record["cohort"]] = cohorts.get(record["cohort"], 0) + 1
    payload = {
        "model_version": MODEL_VERSION,
        "prompt_version": PROMPT_VERSION,
        "source": "docs/p5a/public/formal_learning_vocabulary.csv",
        "record_count": len(records),
        "cohort_counts": cohorts,
        "rules": [
            "不覆盖正式 meaning_zh。",
            "每个正式义项目都必须出现在核心、扩展或其他层。",
            "模型没有新增义项。model_added_senses 为空。",
            "不把考研词频当作义项使用频率。",
            "不标记官方考试重点。",
            "排序没有独立语料证据时 review_required 为 true。",
            "confidence 只是模型自评，不能单独证明释义正确。",
        ],
        "records": records,
    }
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    flagged = sum(record["review_required"] for record in records)
    print("wrote", OUT, "review_required", flagged)


if __name__ == "__main__":
    main()
