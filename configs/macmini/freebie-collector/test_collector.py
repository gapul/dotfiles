#!/usr/bin/env python3
import json
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


HERE = Path(__file__).parent
COLLECTOR = HERE / "collector.py"


class CollectorTest(unittest.TestCase):
    def test_ingest_extracts_annexes_and_preserves_provenance(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            repo = root / "assets"
            inbox = root / "inbox"
            state = root / "state"
            repo.mkdir()
            inbox.mkdir()
            subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.name", "Collector Test"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.email", "collector@example.invalid"], cwd=repo, check=True)
            subprocess.run(["git", "annex", "init", "test"], cwd=repo, check=True, stdout=subprocess.DEVNULL)

            payload = inbox / "Example.zip"
            with zipfile.ZipFile(payload, "w") as archive:
                archive.writestr("Example/Example.otf", b"test font bytes")
            manifest = {
                "file": payload.name,
                "title": "Example Font",
                "vendor": "Example Foundry",
                "source": "https://example.invalid/font",
                "deadline": "2026-09-15T23:59:00+09:00",
                "category": "fonts/free",
                "asset_type": "font",
                "license": "OFL",
                "acquired_price": "0-JPY"
            }
            (inbox / "Example.zip.freebie.json").write_text(json.dumps(manifest))
            config = root / "sources.json"
            config.write_text('{"feeds":[],"seed_offers":[],"direct_downloads":[]}')

            result = subprocess.run([
                "python3", str(COLLECTOR), "ingest", "--config", str(config),
                "--state", str(state), "--repo", str(repo), "--inbox", str(inbox)
            ], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True)
            report = json.loads(result.stdout)
            self.assertEqual(len(report["ingested"]), 1)
            dest = repo / "fonts/free/Example-Foundry/Example-Font"
            self.assertTrue((dest / "original/Example.zip").is_symlink())
            self.assertTrue((dest / "files/Example/Example.otf").is_symlink())
            meta = subprocess.run(
                ["git", "annex", "metadata", str(dest / "files/Example/Example.otf")],
                cwd=repo, text=True, stdout=subprocess.PIPE, check=True
            ).stdout
            self.assertIn("offer-type=limited-time-free", meta)
            self.assertIn("asset-type=font", meta)
            self.assertIn("license=OFL", meta)


if __name__ == "__main__":
    unittest.main()
