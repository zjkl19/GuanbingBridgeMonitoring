from __future__ import annotations

import sys
from pathlib import Path
from typing import Any


def _load_layered_config_function():
    try:
        from workbench.config_layers import load_layered_config
    except ModuleNotFoundError:
        project_root = Path(__file__).resolve().parents[1]
        value = str(project_root)
        if value not in sys.path:
            sys.path.insert(0, value)
        from workbench.config_layers import load_layered_config
    return load_layered_config


def load_report_config(path: Path) -> dict[str, Any]:
    """Load the exact merged configuration used by the analysis workbench."""
    config, _dependencies = _load_layered_config_function()(Path(path))
    return config
