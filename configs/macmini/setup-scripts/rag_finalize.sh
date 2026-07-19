#!/bin/bash
while ! grep -q RAG_DL_DONE /tmp/rag_dl.log 2>/dev/null; do sleep 20; done
sleep 3
echo "=== モデルサイズ ==="; du -sh ~/rag-models/* 2>/dev/null
echo "=== 検証 ==="
~/rag-venv/bin/python ~/rag_test.py 2>&1 | grep -vE "warning|Warning|^\s*$" | tail -20
echo "=== RAG FINALIZE DONE ==="
