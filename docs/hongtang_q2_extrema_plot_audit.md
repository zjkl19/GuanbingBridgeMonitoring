# Hongtang Q2 Plot Extrema Audit

Last updated: 2026-07-06

## Trigger

The Hongtang Q2 earthquake section exposed a consistency problem: the statistics
table used the full-resolution absolute peak, while the visible time-history plot
could be generated from downsampled points and the old marker logic used the
largest positive plotted value. A negative absolute peak or a peak sample dropped
by downsampling could therefore make the report text, stats table, and figure
look contradictory.

## Fix Scope

The correction is intentionally applied at shared plotting boundaries rather
than only in the earthquake module.

| Measurement/output type | Shared path now protected |
| --- | --- |
| Deflection, bearing displacement, tilt | `StructuralTimeSeriesPlotService` -> `prepare_plot_series` |
| Crack width and crack temperature | `CrackAnalysisPipeline` -> `StructuralTimeSeriesPlotService` |
| Temperature, humidity, rainfall | `ScalarSeriesPipeline` -> `prepare_plot_series` |
| GNSS | `GnssAnalysisPipeline` -> `prepare_plot_series` |
| Static strain time series | `StrainPlotService` -> `prepare_plot_series` |
| Static strain boxplots | `StrainPlotService.buildBoxplotMatrix` |
| Dynamic strain high-pass/low-pass time series | `DynamicStrainPlotService` -> `prepare_plot_series` |
| Dynamic strain boxplots | existing dynamic-strain boxplot extrema-preserving sampling |
| Acceleration and cable acceleration | `DynamicSeriesService.limitSeriesPoints` and `DynamicAccelerationPlotService` |
| Wind speed, wind direction, 10 min wind speed | `WindSeriesService.limitSeriesPoints` and `WindPlotService` |
| Earthquake motion | `EarthquakeSeriesService`, `EarthquakeAnalysisPipeline`, `prepare_plot_series` |
| Acceleration/cable-acceleration frequency and cable-force time histories | `SpectrumPlotService` -> `prepare_plot_series` |
| Lightweight `.fig` saved for every module | `save_plot_bundle` line simplification |

The common rule is: when a plotted or saved series must be capped, the retained
sample set must include finite minimum, finite maximum, and finite maximum
absolute-value samples in addition to evenly spaced samples. This makes the
image and `.fig` files suitable for checking report statistics.

## Earthquake-Specific Rule

- `eq_stats.xlsx` now contains both `Peak` (absolute value) and `PeakSigned`
  (the signed value at the same sample).
- `PeakTime` is computed from the same full-resolution sample as `Peak`.
- Time-history figures place the red marker at `PeakTime, PeakSigned`.
- The marker label shows `|a|` so a negative signed peak is not confused with a
  positive maximum.
- Earthquake alarm lines are drawn at both positive and negative levels because
  the threshold is an absolute acceleration threshold.

## QA Rule

For production reports, do not only check that a figure exists. For each
representative report figure with a stated max/min/peak in the text or table,
verify that:

1. the stats table value maps to the intended point/component;
2. the visible marker or curve contains the same extrema after rounding;
3. the timestamp is consistent at the displayed precision;
4. the rendered DOCX/PDF text uses the regenerated stats, not stale report text.

For Hongtang Q2 earthquake figures, the accepted tolerance is the display
precision currently exported by the pipeline: `Peak`/`PeakSigned` are rounded to
3 decimals and `PeakTime` is written to whole seconds, while the `.fig` object
can retain sub-second sampling time.

## Validation

Local focused MATLAB tests passed after the fix:

```matlab
addpath(pwd);
run('tests/test_prepare_plot_series_gap_mode.m');
results = runtests({'tests/test_dynamic_series_service.m', ...
    'tests/test_earthquake_series_service.m', ...
    'tests/test_earthquake_analysis_pipeline.m', ...
    'tests/test_structural_time_series_plot_service.m', ...
    'tests/test_strain_analysis_pipeline.m', ...
    'tests/test_wind_analysis_pipeline.m', ...
    'tests/test_bms_services.m', ...
    'tests/test_writer_plot_manifest_services.m', ...
    'tests/test_dynamic_strain_boxplot_service.m'});
assertSuccess(results);
```

Remote 133 verification reran the Hongtang Q2 earthquake module and opened the
generated `.fig` files. `EQ-X`, `EQ-Y`, and `EQ-Z` all matched the regenerated
`eq_stats.xlsx` rows for curve point, red marker, and label text within the
exported display precision.
