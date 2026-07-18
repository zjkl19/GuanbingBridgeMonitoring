from __future__ import annotations


THRESHOLD_MODULE_LABELS = {
    "temperature": "温度",
    "humidity": "湿度",
    "rainfall": "雨量",
    "wind": "风速风向",
    "wind_speed": "风速",
    "earthquake": "地震动",
    "deflection": "挠度",
    "bearing_displacement": "支座位移",
    "tilt": "倾角",
    "gnss": "GNSS",
    "acceleration": "加速度",
    "cable_accel": "索力加速度",
    "strain": "应变",
    "dynamic_strain": "动应变高通",
    "dynamic_strain_highpass": "动应变高通",
    "dynamic_strain_lowpass": "动应变低通",
    "crack": "裂缝",
}


def threshold_module_label(value: object) -> str:
    key = str(value or "").strip()
    return THRESHOLD_MODULE_LABELS.get(key, key)


__all__ = ["THRESHOLD_MODULE_LABELS", "threshold_module_label"]
