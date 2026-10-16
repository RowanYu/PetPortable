# -*- coding: utf-8 -*-
"""
Kokoro TTS 服务（PC 端 / 可部署云服务器）
- GET  /ping  -> {"ok": true, "voice": DEFAULT_VOICE}
- POST /tts   请求体 {"text": str, "voice": str(缺省 DEFAULT_VOICE)} -> WAV 二进制
- 监听 0.0.0.0:6792（避开 relay 6791 / img 6790）

首次运行会从 HuggingFace 下载模型（约 300MB + 中文 G2P 词库）；
国内网络需提前设置环境变量 HF_ENDPOINT=https://hf-mirror.com
"""
import io
from typing import Optional

import numpy as np
import soundfile as sf
from fastapi import FastAPI, HTTPException, Response
from pydantic import BaseModel

DEFAULT_VOICE = 'zm_yunxia'  # Kokoro 中文少年音（狗宠物）
SAMPLE_RATE = 24000
LISTEN_PORT = 6792

app = FastAPI(title='kokoro-tts-server')

_pipeline = None  # 懒加载单例，进程内缓存


class TtsRequest(BaseModel):
    text: str
    voice: str = DEFAULT_VOICE


def get_pipeline():
    """首次调用时初始化 KPipeline（中文 lang_code='z' 需 misaki[zh]）。"""
    global _pipeline
    if _pipeline is None:
        from kokoro import KPipeline
        _pipeline = KPipeline(lang_code='z', repo_id='hexgrad/Kokoro-82M')
    return _pipeline


def synthesize(text: str, voice: str) -> bytes:
    """合成整段文本为 WAV 字节：Kokoro 按句分段产出，必须拼接全部音频。"""
    pipeline = get_pipeline()
    chunks: list[np.ndarray] = []
    for _gs, _ps, audio in pipeline(text, voice=voice, speed=1.0):
        chunks.append(np.asarray(audio, dtype=np.float32))
    if not chunks:
        raise RuntimeError('合成结果为空')
    merged = chunks[0] if len(chunks) == 1 else np.concatenate(chunks)
    buf = io.BytesIO()
    sf.write(buf, merged, SAMPLE_RATE, format='WAV')
    return buf.getvalue()


@app.get('/ping')
def ping():
    return {'ok': True, 'voice': DEFAULT_VOICE}


@app.post('/tts')
def tts(req: TtsRequest):
    text = (req.text or '').strip()
    if not text:
        raise HTTPException(status_code=400, detail='text 不能为空')
    voice = (req.voice or '').strip() or DEFAULT_VOICE
    try:
        wav_bytes = synthesize(text, voice)
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001 - 统一转 500，避免推理栈异常直接崩溃连接
        raise HTTPException(status_code=500, detail=str(e)) from e
    return Response(content=wav_bytes, media_type='audio/wav')


if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='0.0.0.0', port=LISTEN_PORT)
