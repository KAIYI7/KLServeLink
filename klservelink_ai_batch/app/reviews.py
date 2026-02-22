from __future__ import annotations
from typing import Tuple, List, Optional
import re
from collections import Counter

from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer

_analyzer = SentimentIntensityAnalyzer()

def _tokenize(text: str) -> List[str]:
    t = (text or "").lower()

    # phrase-level traits (catch "on time", "good value", etc.)
    phrases = []
    if re.search(r"\bon\s*time\b", t):
        phrases.append("Punctual")
    if re.search(r"\bgood\s*value\b", t):
        phrases.append("Good Value")
    if re.search(r"\bhighly\s+recommend\b", t):
        phrases.append("Recommended")

    # normalize to a-z words
    t = re.sub(r"[^a-z\s]", " ", t)
    words = [w for w in t.split() if len(w) >= 3]

    stop = set([
        # common stopwords
        "the","and","for","with","this","that","was","were","very","have","has","had","but","not","too",
        "they","you","your","our","their","from","into","out","over","under","after","before",
        # review filler / low-signal words
        "could","would","should","overall","also","really","just","still","even","quite","well",
        "will","can","cant","cannot","able","much","many","more","most","less",
        # generic service words (Not helpful as “traits”)
        "work","works","working","job","service","services","provider","staff","team","company","people","person",
        "done","did","does","doing","get","got","make","made","come","came","give","gave",
        "thank","thanks","acceptable","fine","task"
    ])

    # Canonical trait mapping
    trait_syn = {
        "Punctual": {"punctual","timely","prompt"},
        "Late": {"late","delay","delayed"},
        "Friendly": {"friendly","polite","kind","courteous","nice"},
        "Professional": {"professional","skilled","expert","knowledgeable"},
        "Clean": {"clean","tidy","neat"},
        "Fast": {"fast","quick","speedy"},
        "Slow": {"slow"},
        "Affordable": {"affordable","cheap","reasonable"},
        "Expensive": {"expensive","pricey","overpriced"},
        "Responsive": {"responsive","communicative","reply","replied","response","communicate","communication"},
        "Careful": {"careful","thorough","meticulous","detailed"},
        "Reliable": {"reliable","dependable","trustworthy","completed","complete"},
    }
    syn_to_trait = {syn: trait for trait, syns in trait_syn.items() for syn in syns}

    out: List[str] = []
    out.extend(phrases)

    for w in words:
        if w in stop:
            continue
        trait = syn_to_trait.get(w)
        if trait:
            out.append(trait)
        else:
            out.append(w)

    # If found any traits, prefer returning only traits/phrases
    trait_set = set(trait_syn.keys()) | {"Good Value", "Recommended"}
    traits_only = [x for x in out if x in trait_set]
    final = traits_only if traits_only else out

    # Title Case everything for UI chips
    final = [" ".join(p.capitalize() for p in x.split()) for x in final]
    return final

def analyze_service_reviews(service_doc) -> Tuple[Optional[float], List[str], int]:
    ref = service_doc.reference
    reviews = list(ref.collection("reviews").stream())
    if not reviews:
        return None, [], 0

    scores: List[float] = []
    tokens: List[str] = []

    for r in reviews:
        d = r.to_dict() or {}

        # ----- stars score (0..100) -----
        stars = d.get("stars")
        stars_score: Optional[float] = None
        if isinstance(stars, (int, float)):
            s = float(stars)
            if 0.0 <= s <= 5.0:
                stars_score = (s / 5.0) * 100.0

        # ----- text score (0..100) -----
        text = str(d.get("text", "")).strip()
        text_score: Optional[float] = None
        if text:
            vs = _analyzer.polarity_scores(text)
            compound = float(vs.get("compound", 0.0))
            text_score = (compound + 1.0) * 50.0  # -1..1 -> 0..100
            tokens.extend(_tokenize(text))

        # ----- combine -----
        if text_score is not None and stars_score is not None:
            final = 0.70 * text_score + 0.30 * stars_score
        elif text_score is not None:
            final = text_score
        elif stars_score is not None:
            final = stars_score
        else:
            continue

        scores.append(float(final))

    reviews_analyzed = len(scores)
    score = float(sum(scores) / len(scores)) if scores else None
    kws = [w for w, _ in Counter(tokens).most_common(8)] if tokens else []
    return score, kws, reviews_analyzed