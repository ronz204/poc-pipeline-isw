# syntax=docker/dockerfile:1

FROM ghcr.io/astral-sh/uv:0.12.1 AS uv

FROM python:3.12-slim AS build

COPY --from=uv /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-install-project

COPY source ./source
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-editable

FROM python:3.12-slim

ENV PATH="/app/.venv/bin:$PATH"

RUN useradd --system --create-home --uid 10001 piper \
    && mkdir -p /app/reports /app/logs \
    && chown piper:piper /app/reports /app/logs

WORKDIR /app
COPY --from=build --chown=piper:piper /app/.venv /app/.venv

USER piper
ENTRYPOINT ["piper"]
