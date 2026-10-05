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


DEFAULT_MIDDLEWARE_SPECS: tuple[MiddlewareSpec, ...] = (
    # Required: a rollout with a broken module stalls on readiness instead of serving unmasked.
    MiddlewareSpec("secret-masking", "custom_callbacks.middleware.secret_masking.secret_masking", "secret_masking"),
    MiddlewareSpec(
        "ratelimit-headers",
        "custom_callbacks.middleware.ratelimit_headers.ratelimit_headers",
        "ratelimit_headers",
        required=False,
    ),
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
