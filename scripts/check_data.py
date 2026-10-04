#!/usr/bin/env python3
"""Exercise disk persistence and backups using actual app code in a temporary library."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
sources = ["PromptModels", "PromptStorage", "PromptArchive", "PromptLibrary", "PromptTransfer", "PromptSearch"]
with tempfile.TemporaryDirectory(prefix="otato-release-data-") as temporary:
    directory = Path(temporary)
    binary = directory / "checks"
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-D", "DEBUG", "-O",
                    *[str(root / "oTATo Prompt" / (name + ".swift")) for name in sources],
                    str(root / "tests/ReleaseDataChecks.swift"), "-o", str(binary)], check=True)
    environment = os.environ.copy()
    environment["OTATO_QA_LIBRARY_ROOT"] = str(directory / "library")
    for phase in ("seed", "reopen", "restore", "verify-restored"):
        subprocess.run([str(binary), phase], env=environment, check=True)
