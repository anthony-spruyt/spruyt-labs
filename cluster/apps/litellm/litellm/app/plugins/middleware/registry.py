from __future__ import annotations

import importlib
from dataclasses import dataclass
from typing import Any, Iterable


@dataclass(frozen=True)
class MiddlewareSpec:
    name: str
    module: str
    attribute: str
    required: bool = True


DEFAULT_MIDDLEWARE_SPECS = (
    # Ordering is intentional:
    # 1. Hindsight may inject memory into Anthropic ``system``.
    # 2. ChatGPT then translates all final system content to OpenAI developer role.
    MiddlewareSpec(
        name="hindsight",
        module="custom_callbacks.hindsight.hindsight_plugin",
        attribute="hindsight_middleware",
    ),
    # MiddlewareSpec(
    #     name="chatgpt",
    #     module="custom_callbacks.chatgpt.chatgpt_plugin",
    #     attribute="chatgpt_middleware",
    # ),
)


def load_middlewares(specs: Iterable[MiddlewareSpec], logger: Any = None) -> tuple[Any, ...]:
    loaded = []
    for spec in specs:
        try:
            module = importlib.import_module(spec.module)
            loaded.append(getattr(module, spec.attribute))
        except Exception as exc:  # noqa: BLE001 - one optional middleware must not disable all
            if spec.required:
                raise RuntimeError(
                    f"failed to load required {spec.name} middleware"
                ) from exc
            if logger is not None:
                logger.warning("failed to load %s middleware: %s", spec.name, exc)
    return tuple(loaded)


def load_default_middlewares(logger: Any = None) -> tuple[Any, ...]:
    return load_middlewares(DEFAULT_MIDDLEWARE_SPECS, logger=logger)
