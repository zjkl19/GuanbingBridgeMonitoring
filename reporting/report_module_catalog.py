from __future__ import annotations

MODULE_STATS = {
    "temperature": "temp_stats.xlsx",
    "humidity": "humidity_stats.xlsx",
    "rainfall": "rainfall_stats.xlsx",
    "wind": "wind_stats.xlsx",
    "earthquake": "eq_stats.xlsx",
    "deflection": "deflection_stats.xlsx",
    "bearing_displacement": "bearing_displacement_stats.xlsx",
    "gnss": "gnss_stats.xlsx",
    "acceleration": "accel_stats.xlsx",
    "accel_spectrum": "accel_spec_stats.xlsx",
    "cable_accel": "cable_accel_stats.xlsx",
    "cable_accel_spectrum": "cable_accel_spec_stats.xlsx",
    "tilt": "tilt_stats.xlsx",
    "crack": "crack_stats.xlsx",
    "strain": "strain_stats.xlsx",
    "dynamic_strain_highpass": "dynamic_strain_highpass_stats.xlsx",
    "dynamic_strain_lowpass": "dynamic_strain_lowpass_stats.xlsx",
}

MODULE_DIRS = {
    "temperature": ["时程曲线_温度"],
    "humidity": ["时程曲线_湿度", "频次分布_湿度"],
    "rainfall": ["时程曲线_雨量"],
    "wind": ["风速风向结果"],
    "earthquake": ["地震动结果"],
    "deflection": ["时程曲线_挠度_原始", "时程曲线_挠度_滤波", "时程曲线_挠度_组图_原始", "时程曲线_挠度_组图_滤波"],
    "bearing_displacement": ["时程曲线_支座位移_原始", "时程曲线_支座位移_滤波", "时程曲线_支座位移_组图_原始", "时程曲线_支座位移_组图_滤波"],
    "gnss": ["时程曲线_GNSS"],
    "acceleration": ["时程曲线_加速度", "时程曲线_加速度_RMS10min"],
    "accel_spectrum": ["频谱峰值曲线_加速度"],
    "cable_accel": ["时程曲线_索力加速度", "时程曲线_索力加速度_RMS10min"],
    "cable_accel_spectrum": ["频谱峰值曲线_索力加速度"],
    "tilt": ["时程曲线_倾角"],
    "crack": ["时程曲线_裂缝宽度"],
    "strain": ["时程曲线_应变", "时程曲线_应变_组图", "箱线图_应变"],
    "dynamic_strain_highpass": ["动应变箱线图_高通滤波"],
    "dynamic_strain_lowpass": ["时程曲线_动应变_低通滤波"],
}

BRIDGE_DIR_OVERRIDES = {
    "hongtang": {
        "wind": ["风速风向结果"],
        "strain": ["时程曲线_应变", "箱线图_应变"],
    },
    "shuixianhua": {
        "humidity": ["频次分布_湿度"],
        "strain": ["时程曲线_应变_组图", "箱线图_应变"],
    },
    "zhishan": {
        "bearing_displacement": ["时程曲线_梁端纵向位移_原始", "时程曲线_梁端纵向位移_滤波", "时程曲线_梁端纵向位移_组图_原始", "时程曲线_梁端纵向位移_组图_滤波"],
        "acceleration": ["时程曲线_加速度", "时程曲线_加速度_组图", "时程曲线_加速度_RMS10min", "时程曲线_加速度_RMS10min_组图"],
        "accel_spectrum": ["频谱峰值曲线_加速度", "频谱峰值曲线_结构加速度_组图"],
        "cable_accel": ["时程曲线_索力加速度", "时程曲线_索力加速度_RMS10min", "时程曲线_索力加速度_组图"],
        "cable_accel_spectrum": ["PSD_备查_索力加速度", "频谱峰值曲线_索力加速度", "索力时程图"],
        "strain": ["时程曲线_应变", "时程曲线_应变_组图", "箱线图_应变"],
        "dynamic_strain_highpass": ["时程曲线_动应变_高通滤波", "时程曲线_动应变_高通滤波_组图", "动应变箱线图_高通滤波"],
        "dynamic_strain_lowpass": ["时程曲线_动应变_低通滤波", "时程曲线_动应变_低通滤波_组图", "动应变箱线图_低通滤波"],
    },
}


def _unique(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        if not item or item in seen:
            continue
        seen.add(item)
        result.append(item)
    return result


def expected_stats_files(modules: list[str], *, extra: list[str] | None = None) -> list[str]:
    names = [MODULE_STATS[module] for module in modules if module in MODULE_STATS and MODULE_STATS[module]]
    if extra:
        names.extend(extra)
    return _unique(names)


def expected_result_dirs(bridge_id: str, modules: list[str], *, extra: list[str] | None = None) -> list[str]:
    override = BRIDGE_DIR_OVERRIDES.get(bridge_id, {})
    dirs: list[str] = []
    for module in modules:
        dirs.extend(override.get(module, MODULE_DIRS.get(module, [])))
    if extra:
        dirs.extend(extra)
    return _unique(dirs)
