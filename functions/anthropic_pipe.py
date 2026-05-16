"""
title: Anthropic
author: kostenyang
author_url: https://github.com/kostenyang/openwebui
version: 0.1.0
license: MIT
description: Anthropic Claude provider for Open WebUI (Opus / Sonnet / Haiku 4.x)
"""

import json
import os
from typing import Generator, Iterator, Union

import requests
from pydantic import BaseModel, Field


class Pipe:
    class Valves(BaseModel):
        ANTHROPIC_API_KEY: str = Field(default="", description="Anthropic API key")
        ANTHROPIC_API_BASE: str = Field(default="https://api.anthropic.com/v1")
        MAX_TOKENS: int = Field(default=8192, description="Default max_tokens")

    def __init__(self):
        self.type = "manifold"
        self.id = "anthropic"
        self.name = "anthropic/"
        self.valves = self.Valves(
            ANTHROPIC_API_KEY=os.getenv("ANTHROPIC_API_KEY", ""),
        )

    def pipes(self):
        return [
            {"id": "claude-opus-4-7",   "name": "Claude Opus 4.7"},
            {"id": "claude-sonnet-4-6", "name": "Claude Sonnet 4.6"},
            {"id": "claude-haiku-4-5",  "name": "Claude Haiku 4.5"},
        ]

    def pipe(self, body: dict) -> Union[str, Generator, Iterator]:
        if not self.valves.ANTHROPIC_API_KEY:
            return "Error: ANTHROPIC_API_KEY not set. Open WebUI → Functions → Anthropic → Valves."

        model_id = body["model"].split(".", 1)[-1]

        system_parts: list[str] = []
        msgs: list[dict] = []
        for m in body.get("messages", []):
            role = m.get("role")
            content = m.get("content") or ""
            if role == "system":
                if content:
                    system_parts.append(content)
            elif role in ("user", "assistant"):
                msgs.append({"role": role, "content": content})

        payload = {
            "model": model_id,
            "max_tokens": body.get("max_tokens") or self.valves.MAX_TOKENS,
            "messages": msgs,
            "stream": body.get("stream", True),
        }
        if system_parts:
            payload["system"] = "\n".join(system_parts)

        headers = {
            "x-api-key": self.valves.ANTHROPIC_API_KEY,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        }
        url = f"{self.valves.ANTHROPIC_API_BASE}/messages"

        if payload["stream"]:
            return self._stream(url, headers, payload)

        r = requests.post(url, json=payload, headers=headers, timeout=180)
        r.raise_for_status()
        data = r.json()
        return "".join(b.get("text", "") for b in data.get("content", []))

    def _stream(self, url, headers, payload) -> Generator:
        with requests.post(url, json=payload, headers=headers, stream=True, timeout=180) as r:
            r.raise_for_status()
            for raw in r.iter_lines():
                if not raw or not raw.startswith(b"data: "):
                    continue
                data = raw[6:].decode("utf-8", "replace")
                try:
                    evt = json.loads(data)
                except json.JSONDecodeError:
                    continue
                t = evt.get("type")
                if t == "content_block_delta":
                    delta = evt.get("delta", {})
                    if delta.get("type") == "text_delta":
                        yield delta.get("text", "")
                elif t == "message_stop":
                    break
