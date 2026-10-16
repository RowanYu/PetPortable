# -*- coding: utf-8 -*-
"""Kokoro TTS 服务测试：不依赖真实模型，只验证路由契约。"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from fastapi.testclient import TestClient

import server.kokoro_tts_server as srv

client = TestClient(srv.app)


def test_ping():
    r = client.get("/ping")
    assert r.status_code == 200
    assert r.json() == {"ok": True, "voice": srv.DEFAULT_VOICE}


def test_tts_empty_text_rejected():
    r = client.post("/tts", json={"text": "   "})
    assert r.status_code == 400


def test_tts_missing_voice_uses_default():
    """不传 voice 时应回退 DEFAULT_VOICE 而不是 422。"""
    # 仅验证请求模型缺省值，不触发真实合成（text 为空会被 400 拦下，
    # 但若 voice 缺省值错误，FastAPI 会先返回 422）。
    r = client.post("/tts", json={"text": "   "})
    assert r.status_code == 400


def test_merge_audio_chunks_skips_none():
    """分段拼接必须跳过 audio=None 的分段（标点/换行段可能产出 None）。"""
    import numpy as np

    a = np.array([0.1, 0.2], dtype=np.float32)
    b = np.array([0.3], dtype=np.float32)
    out = srv.merge_audio_chunks([a, None, b, None])
    assert out.shape == (3,)


def test_merge_audio_chunks_all_none_raises():
    import numpy as np

    try:
        srv.merge_audio_chunks([None, None])
        assert False, "应抛出 RuntimeError"
    except RuntimeError:
        pass
