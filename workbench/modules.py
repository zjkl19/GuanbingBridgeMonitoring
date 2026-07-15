from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ModuleSpec:
    key: str
    option_field: str
    label: str
    category: str = "analysis"
    icon_asset: str = ""
    description: str = ""


MODULE_SPECS: tuple[ModuleSpec, ...] = (
    ModuleSpec("zip_precheck", "precheck_zip_count", "预检查压缩包数量", "preprocess", "archive-check.svg"),
    ModuleSpec(
        "unzip",
        "doUnzip",
        "批量解压",
        "preprocess",
        "archive-extract.svg",
        "安全解压并校验 ZIP；并发数量可在“配置与预警值 → 解压并发”中设置。",
    ),
    ModuleSpec("rename_csv", "doRenameCsv", "批量重命名CSV", "preprocess", "document-rename.svg"),
    ModuleSpec("remove_header", "doRemoveHeader", "批量去除表头", "preprocess", "table-header-remove.svg"),
    ModuleSpec("resample", "doResample", "批量重采样", "preprocess", "resample.svg"),
    ModuleSpec(
        "cache_prebuild",
        "doCachePrebuild",
        "预生成分析缓存",
        "preprocess",
        "cache-prebuild.svg",
        "按桥梁数据格式选择缓存方式；只读取配置中分析模块实际使用的已解压 CSV，生成或复用 MAT 分析缓存。默认保留 CSV；仅在任务中明确启用并确认后，才按天删除已验证且可由原 ZIP 恢复的 CSV。",
    ),
    ModuleSpec("lowfreq_sync", "doLowfreqSync", "基康低频同步", "preprocess", "acquisition-sync.svg"),
    ModuleSpec("temperature", "doTemp", "温度分析", icon_asset="thermometer.svg"),
    ModuleSpec("humidity", "doHumidity", "湿度分析", icon_asset="droplet.svg"),
    ModuleSpec("rainfall", "doRainfall", "雨量分析", icon_asset="rainfall.svg"),
    ModuleSpec("gnss", "doGNSS", "GNSS分析", icon_asset="satellite.svg"),
    ModuleSpec("wind", "doWind", "风速风向分析", icon_asset="wind.svg"),
    ModuleSpec("earthquake", "doEq", "地震动分析", icon_asset="earthquake.svg"),
    ModuleSpec("wim", "doWIM", "WIM", icon_asset="truck-scale.svg"),
    ModuleSpec("deflection", "doDeflect", "挠度分析", icon_asset="deflection.svg"),
    ModuleSpec("bearing_displacement", "doBearingDisplacement", "支座位移分析", icon_asset="bearing.svg"),
    ModuleSpec("tilt", "doTilt", "倾角分析", icon_asset="tilt.svg"),
    ModuleSpec("acceleration", "doAccel", "加速度分析", icon_asset="acceleration.svg"),
    ModuleSpec("cable_accel", "doCableAccel", "索力加速度分析", icon_asset="cable-vibration.svg"),
    ModuleSpec("accel_spectrum", "doAccelSpectrum", "加速度频谱", icon_asset="spectrum.svg"),
    ModuleSpec("cable_accel_spectrum", "doCableAccelSpectrum", "索力加速度频谱", icon_asset="cable-spectrum.svg"),
    ModuleSpec("rename_crk", "doRenameCrk", "裂缝重命名", "preprocess", "crack-rename.svg"),
    ModuleSpec("crack", "doCrack", "裂缝分析", icon_asset="crack.svg"),
    ModuleSpec("strain", "doStrain", "应变分析", icon_asset="strain.svg"),
    ModuleSpec("dynamic_strain_highpass", "doDynStrainBoxplot", "动应变分析（高通）", icon_asset="highpass.svg"),
    ModuleSpec("dynamic_strain_lowpass", "doDynStrainLowpassBoxplot", "动应变分析（低通）", icon_asset="lowpass.svg"),
)

MODULE_BY_KEY = {spec.key: spec for spec in MODULE_SPECS}


def options_for_modules(selected: list[str] | tuple[str, ...] | set[str]) -> dict[str, bool]:
    selected_keys = {str(item) for item in selected}
    unknown = sorted(selected_keys.difference(MODULE_BY_KEY))
    if unknown:
        raise ValueError(f"Unknown analysis modules: {', '.join(unknown)}")
    return {spec.option_field: spec.key in selected_keys for spec in MODULE_SPECS}
