#!/usr/bin/env python3
"""Fail the app build if its local inference assets are absent or mismatched."""
import argparse
import hashlib
import json
from pathlib import Path


def verify(resources, bundle=None):
    manifest_path = resources / "Verification/VerificationModelManifest.json"
    manifest = json.loads(manifest_path.read_text())
    if manifest["modelVersion"] != "bertimbau-base-plue-spike9":
        raise ValueError("Model version requires a reviewed manifest/policy update")
    files = manifest["files"]
    for model in ("NLI", "Embeddings"):
        for required in ("model.mil", "coremldata.bin", "weights/weight.bin"):
            if model + ".mlmodelc/" + required not in files:
                raise ValueError("Incomplete model manifest: " + model)
    for relative, expected in files.items():
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts:
            raise ValueError("Invalid manifest path")
        source = resources / ("Models" if len(path.parts) > 1 else "Tokenizers") / path
        candidates = [source]
        if bundle:
            candidates.append(bundle / path)
        for candidate in candidates:
            digest = hashlib.sha256()
            with candidate.open("rb") as handle:
                for block in iter(lambda: handle.read(1024 * 1024), b""):
                    digest.update(block)
            if digest.hexdigest() != expected:
                raise ValueError("Model/tokenizer integrity mismatch: " + str(candidate))
    if bundle:
        if (bundle / manifest_path.name).read_bytes() != manifest_path.read_bytes():
            raise ValueError("Bundled model manifest differs from source")
    print("Verified local models, tokenizers and packaged assets (" + manifest["modelVersion"] + ")")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--resources", type=Path, required=True)
    parser.add_argument("--bundle", type=Path)
    args = parser.parse_args()
    try:
        verify(args.resources, args.bundle)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, "error: Local analysis cannot run: " + str(error)
                    + ". Restore the validated assets with bash scripts/sync-models.sh.\n")
