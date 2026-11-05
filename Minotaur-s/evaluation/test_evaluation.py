import copy
import json
import tempfile
import unittest
from pathlib import Path
from calibrate import fit, softmax
from dataset import import_quiz, read, split_records, validate
from metrics import evaluate, wilson
from release_gate import check
from train_domain import prepare_records
from select_policy import select

def record(identifier="case-1", split="calibration"):
    return {"id": identifier, "claim": "Uma afirmação usada somente neste teste unitário.",
            "event_id": identifier, "family_id": identifier, "reference_date": "2026-11-04",
            "review_status": "reviewed", "reviewers": ["fixture-reviewer-A", "fixture-reviewer-B"],
            "verdict": "CONFIRMADO", "split": split,
            "evidence": [{"id": identifier + "-e", "url": "https://g1.globo.com/" + identifier, "text": "O levantamento mostrou o resultado."}],
            "sufficient_evidence_sets": [[identifier + "-e"]],
            "pairs": [{"premise": "O levantamento mostrou o resultado.", "hypothesis": "O resultado foi apresentado.", "label": "entailment"}]}

class EvaluationTests(unittest.TestCase):
    def test_pending_claims_are_never_gold(self):
        row = record(); row["review_status"] = "pending"
        with self.assertRaises(ValueError): validate([row], require_reviewed=True)

    def test_independent_review_required(self):
        row = record(); row["reviewers"] = ["one", "one"]
        with self.assertRaises(ValueError): validate([row])

    def test_split_leakage_via_family_event_or_same_source(self):
        for key in ("family_id", "event_id"):
            a, b = record("a", "train"), record("b", "test")
            b[key] = a[key]
            with self.assertRaises(ValueError): validate([a, b])
        a, b = record("a", "train"), record("b", "test")
        b["evidence"][0]["url"] = a["evidence"][0]["url"] + "?utm_source=test"
        with self.assertRaises(ValueError): validate([a, b])

    def test_exact_split_never_pads_or_breaks_groups(self):
        with self.assertRaises(ValueError): split_records([record()])
        rows = [record(str(i)) for i in range(1200)]
        split = split_records(rows)
        self.assertEqual({s: sum(r["split"] == s for r in split) for s in ("train", "calibration", "test")},
                         {"train": 600, "calibration": 300, "test": 300})

    def test_correct_verdict_without_evidence_is_not_an_end_to_end_success(self):
        row = record()
        report = evaluate([row], [{"id": row["id"], "verdict": "CONFIRMADO", "evidence": []}])
        self.assertEqual(report["directional_precision"]["value"], 0)
        self.assertEqual(report["end_to_end_accuracy"]["value"], 0)

    def test_claim_cannot_disappear_from_metrics(self):
        with self.assertRaises(ValueError): evaluate([record()], [])

    def test_execution_failure_stays_in_denominator_and_is_not_no_coverage(self):
        report = evaluate([record()], [{"id": "case-1", "error": "readingIncomplete", "verdict": None}])
        self.assertEqual(report["count"], 1)
        self.assertEqual(report["execution_failures"], 1)
        self.assertEqual(report["end_to_end_accuracy"]["value"], 0)
        self.assertEqual(report["confusion"]["CONFIRMADO"]["ERROR"], 1)
        self.assertEqual(report["confusion"]["CONFIRMADO"]["NAO_ENCONTRADO"], 0)

    def test_evidence_requires_correct_text_and_url_not_only_id(self):
        row = record()
        p = {"id": row["id"], "verdict": row["verdict"], "evidence": copy.deepcopy(row["evidence"])}
        self.assertEqual(evaluate([row], [p])["end_to_end_accuracy"]["value"], 1)
        p["evidence"][0]["text"] = "Uma frase completamente diferente."
        self.assertEqual(evaluate([row], [p])["end_to_end_accuracy"]["value"], 0)

    def test_zero_denominator_is_unknown_not_perfect_accuracy(self):
        row = record(); row["verdict"] = "SEM_INFORMACAO"
        report = evaluate([row], [{"id": row["id"], "verdict": "SEM_INFORMACAO"}])
        self.assertIsNone(report["directional_precision"]["value"])
        self.assertIsNone(report["resolvable_coverage"]["value"])
        self.assertEqual(wilson(0, 0), None)
        self.assertIsNone(report["high_confidence_errors"])

    def test_temperature_cannot_use_test_or_single_review(self):
        row = {"claim_id": "x", "logits": [3, 1, 0], "label": "entailment", "split": "test", "reviewers": ["a", "b"]}
        with self.assertRaises(ValueError): fit([row])
        row.update(split="calibration", reviewers=["a"])
        with self.assertRaises(ValueError): fit([row])

    def test_temperature_fit_never_worsens_calibration_nll(self):
        rows = [{"claim_id": str(i), "logits": [8, 0, -2], "label": "entailment" if i < 8 else "neutral",
                 "split": "calibration", "reviewers": ["a", "b"]} for i in range(10)]
        result = fit(rows)
        self.assertLessEqual(result["nll_after"], result["nll_before"])
        self.assertEqual(len(result["claim_ids"]), 10)
        with self.assertRaises(ValueError): softmax([float("nan"), 1, 0])

    def test_training_rejects_blind_test_before_importing_torch(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "test.jsonl"; p.write_text(json.dumps(record(split="test")) + "\n")
            with self.assertRaises(ValueError): prepare_records(p)

    def test_quiz_import_remains_pending_and_tolerates_blank_rows(self):
        with tempfile.TemporaryDirectory() as d:
            source, target = Path(d) / "input.tsv", Path(d) / "output.jsonl"
            source.write_text("ID\tURL\tTítulo\tBinário\n1\thttps://g1.globo.com/x\tUma afirmação\tFATO\n\n2\n")
            self.assertEqual(import_quiz(source, target), 1)
            self.assertIsNone(read(target)[0]["verdict"])

    def test_policy_selection_does_not_touch_test_or_accept_mismatched_temperature(self):
        with self.assertRaises(ValueError): select([record(split="test")], [], {}, "model", minimum_claims=1)
        with self.assertRaises(ValueError): select([record()], [], {"claim_ids": ["other"]}, "model", minimum_claims=1)

    def test_release_requires_both_device_and_evidence_gates(self):
        metric = {"directional_precision": {"value": 1}, "resolvable_coverage": {"value": 1},
                  "end_to_end_accuracy": {"value": .9}, "total_coverage": {"value": .7}}
        baseline = copy.deepcopy(metric); baseline["end_to_end_accuracy"]["value"] = .8
        report = {"candidate": metric, "baseline": baseline}
        self.assertTrue(check(report))

if __name__ == "__main__": unittest.main()
