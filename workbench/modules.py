from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ModuleSpec:
    key: str
    option_field: str
    label: str
    category: str = "analysis"
    icon_name: str = ""


MODULE_SPECS: tuple[ModuleSpec, ...] = (
    ModuleSpec("zip_precheck", "precheck_zip_count", "预检查压缩包数量", "preprocess", "SP_DialogApplyButton"),
    ModuleSpec("unzip", "doUnzip", "批量解压", "preprocess", "SP_DirOpenIcon"),
    ModuleSpec("rename_csv", "doRenameCsv", "批量重命名CSV", "preprocess", "SP_FileIcon"),
    ModuleSpec("remove_header", "doRemoveHeader", "批量去除表头", "preprocess", "SP_TrashIcon"),
    ModuleSpec("resample", "doResample", "批量重采样", "preprocess", "SP_BrowserReload"),
    ModuleSpec("lowfreq_sync", "doLowfreqSync", "基康低频同步", "preprocess", "SP_MediaSeekForward"),
    ModuleSpec("temperature", "doTemp", "温度分析", icon_name="SP_MessageBoxInformation"),
    ModuleSpec("humidity", "doHumidity", "湿度分析", icon_name="SP_DriveNetIcon"),
    ModuleSpec("rainfall", "doRainfall", "雨量分析", icon_name="SP_ArrowDown"),
    ModuleSpec("gnss", "doGNSS", "GNSS分析", icon_name="SP_ComputerIcon"),
    ModuleSpec("wind", "doWind", "风速风向分析", icon_name="SP_BrowserReload"),
    ModuleSpec("earthquake", "doEq", "地震动分析", icon_name="SP_MessageBoxWarning"),
    ModuleSpec("wim", "doWIM", "WIM", icon_name="SP_DriveHDIcon"),
    ModuleSpec("deflection", "doDeflect", "挠度分析", icon_name="SP_ArrowDown"),
    ModuleSpec("bearing_displacement", "doBearingDisplacement", "支座位移分析", icon_name="SP_ArrowRight"),
    ModuleSpec("tilt", "doTilt", "倾角分析", icon_name="SP_TitleBarShadeButton"),
    ModuleSpec("acceleration", "doAccel", "加速度分析", icon_name="SP_ArrowUp"),
    ModuleSpec("cable_accel", "doCableAccel", "索力加速度分析", icon_name="SP_CommandLink"),
    ModuleSpec("accel_spectrum", "doAccelSpectrum", "加速度频谱", icon_name="SP_FileDialogDetailedView"),
    ModuleSpec("cable_accel_spectrum", "doCableAccelSpectrum", "索力加速度频谱", icon_name="SP_FileDialogDetailedView"),
    ModuleSpec("rename_crk", "doRenameCrk", "裂缝重命名", "preprocess", "SP_FileIcon"),
    ModuleSpec("crack", "doCrack", "裂缝分析", icon_name="SP_MessageBoxCritical"),
    ModuleSpec("strain", "doStrain", "应变分析", icon_name="SP_FileDialogInfoView"),
    ModuleSpec("dynamic_strain_highpass", "doDynStrainBoxplot", "动应变分析（高通）", icon_name="SP_ArrowUp"),
    ModuleSpec("dynamic_strain_lowpass", "doDynStrainLowpassBoxplot", "动应变分析（低通）", icon_name="SP_ArrowDown"),
)

MODULE_BY_KEY = {spec.key: spec for spec in MODULE_SPECS}


def options_for_modules(selected: list[str] | tuple[str, ...] | set[str]) -> dict[str, bool]:
    selected_keys = {str(item) for item in selected}
    unknown = sorted(selected_keys.difference(MODULE_BY_KEY))
    if unknown:
        raise ValueError(f"Unknown analysis modules: {', '.join(unknown)}")
    return {spec.option_field: spec.key in selected_keys for spec in MODULE_SPECS}
