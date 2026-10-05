"""Reads the pod's image, plugin mounts and callbacks from the same manifests Flux applies."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import yaml

APP_DIR = Path(__file__).resolve().parents[3]
CALLBACKS_ROOT = "/app/custom_callbacks"
PLUGIN_CONFIGMAP = "litellm-middleware-plugin"
# Only settings the test proxy can honour without the pod's DB, Redis and network.
MIRRORED_GENERAL_SETTINGS = ("include_call_id_in_error_body",)


@dataclass(frozen=True)
class PodLayout:
    image: str
    pythonpath: str
    callbacks: tuple[str, ...]
    general_settings: dict[str, object]
    # container path -> repo source file
    mounts: dict[str, Path]


def load() -> PodLayout:
    values = yaml.safe_load((APP_DIR / "values.yaml").read_text())
    kustomization = yaml.safe_load((APP_DIR / "kustomization.yaml").read_text())
    container = values["controllers"]["litellm"]["containers"]["litellm"]

    generator = next(g for g in kustomization["configMapGenerator"] if g["name"] == PLUGIN_CONFIGMAP)
    sources = dict(entry.split("=", 1) for entry in generator["files"])
    volume = next(v for v in values["persistence"].values() if v.get("name") == PLUGIN_CONFIGMAP)
    mounts = {m["path"]: APP_DIR / sources[m["subPath"]] for m in volume["advancedMounts"]["litellm"]["litellm"]}

    config = yaml.safe_load(values["configMaps"]["litellm-config"]["data"]["config.yaml"])
    callbacks = tuple(c for c in config["litellm_settings"]["callbacks"] if c.startswith("custom_callbacks."))
    general_settings = {k: v for k, v in config["general_settings"].items() if k in MIRRORED_GENERAL_SETTINGS}

    return PodLayout(
        image=f'{container["image"]["repository"]}:{container["image"]["tag"]}',
        pythonpath=container["env"]["PYTHONPATH"],
        callbacks=callbacks,
        general_settings=general_settings,
        mounts=mounts,
    )


def stage(layout: PodLayout, dest: Path) -> None:
    """Builds the custom_callbacks tree the init container and subPath mounts produce."""
    (dest / "__init__.py").touch()
    for path, source in layout.mounts.items():
        target = dest / Path(path).relative_to(CALLBACKS_ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read_bytes())
        target.chmod(0o644)
