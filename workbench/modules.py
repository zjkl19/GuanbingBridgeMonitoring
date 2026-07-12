from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ModuleSpec:
    key: str
    option_field: str
    label: str
    category: str = "analysis"


MODULE_SPECS: tuple[ModuleSpec, ...] = (
    ModuleSpec("zip_precheck", "precheck_zip_count", "预检查压缩包数量", "preprocess"),
    ModuleSpec("unzip", "doUnzip", "批量解压", "preprocess"),
    ModuleSpec("rename_csv", "doRenameCsv", "批量重命名CSV", "preprocess"),
    ModuleSpec("remove_header", "doRemoveHeader", "批量去除表头", "preprocess"),
    ModuleSpec("resample", "doResample", "批量重采样", "preprocess"),
    ModuleSpec("lowfreq_sync", "doLowfreqSync", "基康低频同步", "preprocess"),
    ModuleSpec("temperature", "doTemp", "温度分析"),
    ModuleSpec("humidity", "doHumidity", "湿度分析"),
    ModuleSpec("rainfall", "doRainfall", "雨量分析"),
    ModuleSpec("gnss", "doGNSS", "GNSS分析"),
    ModuleSpec("wind", "doWind", "风速风向分析"),
    ModuleSpec("earthquake", "doEq", "地震动分析"),
    ModuleSpec("wim", "doWIM", "WIM"),
    ModuleSpec("deflection", "doDeflect", "挠度分析"),
    ModuleSpec("bearing_displacement", "doBearingDisplacement", "支座位移分析"),
    ModuleSpec("tilt", "doTilt", "倾角分析"),
    ModuleSpec("acceleration", "doAccel", "加速度分析"),
    ModuleSpec("cable_accel", "doCableAccel", "索力加速度分析"),
    ModuleSpec("accel_spectrum", "doAccelSpectrum", "加速度频谱"),
    ModuleSpec("cable_accel_spectrum", "doCableAccelSpectrum", "索力加速度频谱"),
    ModuleSpec("rename_crk", "doRenameCrk", "裂缝重命名", "preprocess"),
    ModuleSpec("crack", "doCrack", "裂缝分析"),
    ModuleSpec("strain", "doStrain", "应变分析"),
    ModuleSpec("dynamic_strain_highpass", "doDynStrainBoxplot", "动应变分析（高通）"),
    ModuleSpec("dynamic_strain_lowpass", "doDynStrainLowpassBoxplot", "动应变分析（低通）"),
)

MODULE_BY_KEY = {spec.key: spec for spec in MODULE_SPECS}


def options_for_modules(selected: list[str] | tuple[str, ...] | set[str]) -> dict[str, bool]:
    selected_keys = {str(item) for item in selected}
    unknown = sorted(selected_keys.difference(MODULE_BY_KEY))
    if unknown:
        raise ValueError(f"Unknown analysis modules: {', '.join(unknown)}")
    return {spec.option_field: spec.key in selected_keys for spec in MODULE_SPECS}
