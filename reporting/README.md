# Reporting / 报告生成

## Scope / 范围

The report builder supports both monthly reports and period reports.
报告生成程序同时支持月报和周期报。

Hongtang period reports use real Word `PAGE` and `NUMPAGES` fields in the
header. The generator audits that exactly one of each field is present and
does not calculate or write a fixed total-page number. Accepted proofreading
corrections can be reapplied idempotently with:

```powershell
python reporting/calibrate_hongtang_period_template.py
```

- `月报 / Monthly Report`
- `周期报（含 WIM） / Period Report (with WIM)`

## Hongtang Typhoon Brief / 洪塘台风快报

`build_hongtang_typhoon_brief.py` builds a lightweight staged brief directly
from the daily Donghua waveform and feature ZIP files. It keeps the actual data
cutoff explicit, uses raw W1/W2 waveforms for 10-minute wind statistics, and
uses all configured girder/tower/cable feature-peak channels for structural
trend screening.

```powershell
python reporting/build_hongtang_typhoon_brief.py `
  --source-root F:\path\to\source_exports `
  --output-dir F:\path\to\brief_output
```

The generated manifest records per-ZIP/per-entry coverage, row counts, rejected
rows, method details, summary statistics, source links, and missing-entry QC.
The staged brief must not be described as a landfall or post-event assessment
unless the source coverage actually includes those periods.

For an owner-facing formal report based on the accepted Hongtang period-report
layout, use `build_hongtang_typhoon_template_report.py`. It preserves the cover,
signatures, engineering overview, sensor layout, alarm thresholds, headers and
footers, then replaces the old period results with a source-audited typhoon
chapter. The generator reports both raw gust maxima and threshold-comparable
10-minute mean maxima, includes their occurrence times and concurrent wind
directions, compares pre/post-landfall wind and structural-response stages, and
writes a JSON manifest beside the DOCX.

```powershell
python reporting/build_hongtang_typhoon_template_report.py `
  --template F:\path\to\accepted_period_report.docx `
  --source-root F:\path\to\source_exports `
  --output-dir F:\path\to\formal_report `
  --window-start 2026-07-10T23:20:00 `
  --landfall-time 2026-07-11T23:20:00 `
  --export-days 2026-07-11,2026-07-12
```

The template may store multilevel numbering directly on existing heading
paragraphs. New Chapter 4 subsections copy that numbering contract explicitly.
The generator also removes a redundant empty section-break paragraph before
the result chapter to prevent a blank page after the alarm-threshold table.
Always update Word fields/TOC and render every page before delivery.

## Unified Platform / 统一工作平台

Starting with v1.8, operators generate reports from the `报告生成` tab of
`桥梁健康监测工作平台.exe`.  The report engine runs as a hidden worker of
the same application, so no second report-builder window or standalone report
executable is part of the production package.

从 v1.8 开始，用户统一在 `桥梁健康监测工作平台.exe` 的“报告生成”页生成报告。
报告内核以同一应用程序的隐藏后台任务运行，生产包不再包含第二个报告窗口或独立报告 EXE。

The schema-v3 `release_manifest.json` must declare:

- `report_runtime = embedded_headless_worker`
- `standalone_report_builder_included = false`
- `analysis_runner_failure_exit_smoke = true`
- successful embedded report job, report-condition, and visual-QA checks

The compatibility field `includes_report_builder = true` means that report
capability is embedded in the workbench; it does **not** authorize packaging a
standalone `BridgeReportBuilder.exe`.

### Audited disclosures / 可审计缺项披露

The unified frontend and background worker use the same report-gate audit.
Bridge/date/config mismatch, manifest corruption or hash drift, analysis
failure, provenance-count mismatch, and incorrect media binding are hard
failures and cannot be manually waived. Explicitly closed source-coverage gaps
and supported no-data/not-applicable omissions can become disclosures only
when the selected report adapter has a tested safe action for stale template
content.

Each disclosure has a stable ID. Operator confirmation is bound to the exact
analysis-manifest SHA-256 and policy version; any manifest change invalidates
it. Newly discovered builder omissions cause a `disclosure_required` terminal
result on the first pass. A second pass may publish only if it reproduces the
exact confirmed candidate set. The formal report then records
`passed_with_disclosures`, appends a body disclosure section, and writes the
item count, reasons, actions, confirmation timestamps, analysis SHA and output
hash to the report manifest and QC. `jlj_monthly` and
`shuixianhua_monthly` currently support the tested builder/module omission
actions. Unsupported report types remain fail-closed.

统一前端与后台 worker 共用同一门禁。红色硬阻塞不可人工放行；黄色项必须逐项确认，
且确认精确绑定分析清单 SHA。第一次发现新的报告构建缺项只返回
`disclosure_required`，不得发布正式报告；第二次构建必须复现完全相同的已确认集合。
正式交付使用 `passed_with_disclosures`，同时把缺项原因与处置写入正文、生成清单和 QC。

Version `v1.8.0` makes the embedded runtime the only production report entry.
Shuixianhua and Jiulongjiang monthly generation now rejects stale-period text,
figures and source summaries, clears unmatched template patrol material,
removes unused template media, and fails closed when report QC cannot complete.
Microsoft Word remains the authoritative renderer for combined
`STYLEREF`/`SEQ` caption fields.

Jiulongjiang patrol sources remain month-bound. `reporting.patrol.required`
defaults to `true`; a bridge configuration may set it to `false` when patrol
attachments are not a mandatory monthly-report input. In that case, a missing
period-matched source clears stale template content and inserts
`本期巡查资料未提供。`, while the report manifest records the source as
`not_available` without treating it as a blocking omission. An explicitly
supplied source from another month is always rejected.
The standard Jiulongjiang profile explicitly uses `required=false`; this does
not relax any period, statistics, figure, configuration or source-data gate.

版本 `v1.8.0` 将内嵌运行时作为唯一生产报告入口；水仙花和九龙江月报会拒绝
旧月份文字、图件及来源摘要，清除不匹配的模板巡检资料，移除未使用的模板媒体，
且报告质检无法完成时直接阻断。组合 `STYLEREF`/`SEQ` 题注域以 Microsoft Word
渲染结果为准。

Build and verify the unified application from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_workbench_exe.ps1
```

The build and GitHub-release scripts scan both the distribution tree and the
final ZIP and fail if a retired standalone report entry is present.  Historical
developer-only entrypoints under `reporting/` remain available for isolated
backend diagnostics and template regression; they are not operator or release
entrypoints and must not be copied to a production package.

生产机更新时，应整体替换统一工作平台目录，保留现场的 `config/` 和数据根目录，
再由工作平台内置的配置检查、分析结果检查和逐页版面检查完成报告交付。

## Data Root / 数据根目录

Templates stay under `reports/`. Runtime outputs stay under the data root.
模板放在 `reports/`，运行产物放在数据根目录。

Recommended layout.
推荐目录如下。

```text
E:/洪塘大桥数据/2026年1-3月/
  lowfreq/
    data.xlsx
  WIM/
    HS_Data_202601.bcp
    HS_Data_202601.fmt
    HS_Data_202602.bcp
    HS_Data_202602.fmt
    HS_Data_202603.bcp
    HS_Data_202603.fmt
    results/
      hongtang/
        202601/
        202602/
        202603/
  stats/
    strain_stats.xlsx
    tilt_stats.xlsx
    bearing_displacement_stats.xlsx
    wind_stats.xlsx
  run_logs/
  自动报告/
```

## GUI Fields / GUI 字段说明

- `报告类型 / Report Type`
  - `月报` 或 `周期报（含 WIM）`
- `模板文件 / Template`
  - Monthly default: `洪塘大桥健康监测月报模板.docx`
  - Period default: `洪塘大桥健康监测2026年第一季季报-改4.docx`
  - The current automatic period-report layout assumes this default template.
  - 当前自动周期报布局默认按这份模板适配。
- `配置文件 / Config`
  - Prefer machine-specific override when present.
  - 存在机器专用配置时优先使用。
- `数据/结果根目录 / Data and Result Root`
  - Contains plots, `stats/`, `run_logs/`, and `自动报告/`.
  - 用于存放图片、`stats/`、`run_logs/` 和 `自动报告/`。
  - For period reports, section `1.4 健康监测系统运行状况` is only accurate when this root also contains the raw source data needed for missing-data checks.
  - 对周期报，`1.4 健康监测系统运行状况` 只有在该目录同时包含原始数据时才准确。
- `程序根目录（高级） / Program Root (Advanced)`
  - Compatibility fallback for code and template lookup.
  - 用于代码、模板的兼容查找，通常保持程序所在目录即可。
- `WIM 结果目录 / WIM Result Root`
  - Usually `<数据/结果根目录>/WIM/results/hongtang`.
  - 通常是 `<数据/结果根目录>/WIM/results/hongtang`。
- `输出目录 / Output Directory`
  - Usually `<数据/结果根目录>/自动报告`.
  - 通常是 `<数据/结果根目录>/自动报告`。

## Config Keys Used Directly / 直接影响报告生成的配置项

The report generator reads these config sections directly.
报告程序会直接读取以下配置项。

- `plot_styles.*.output_dir`
- `plot_styles.*.boxplot_output_dir`
- `plot_styles.*.group_output_dir`
- `reporting.*`
- `wim.*`
- `wim_db.*`

Thresholds, zero-offset corrections, and alarm bounds affect reports indirectly through regenerated analysis outputs.
阈值、零点修正和预警值通过分析结果间接影响报告。

## Monthly Report / 月报

Use a single result directory for one monitoring period.
月报使用单个监测周期的结果目录。

## Period Report / 周期报

Use the period template, result root, WIM monthly results, and a date range.
周期报需要周期模板、结果根目录、WIM 月结果和起止日期。

Important note for period reports:
周期报的重要说明：

- Non-WIM sections are assembled from the result root.
- WIM is still inserted month by month from `WIM/results/hongtang/<yyyymm>/`.
- `1.4 健康监测系统运行状况` checks raw missing/no-file/no-record conditions. If the result root contains only derived outputs but not raw data, this section will report many missing items.

- 非 WIM 章节从结果根目录读取。
- WIM 仍按月从 `WIM/results/hongtang/<yyyymm>/` 插入。
- `1.4 健康监测系统运行状况` 统计的是原始缺失/无文件/无记录。如果结果根目录只有处理结果而没有原始数据，该节会显示大量缺失。
- GUI 中的 `监测时间` 是报告显示文字，可人工调整，例如 `2026年01月01日~2026年03月31日`；`开始日期` 和 `结束日期` 用于推导 WIM 月份范围。

CLI debugging example:
CLI 调试示例：

```powershell
python reporting\build_period_report.py `
  --template reports\洪塘大桥健康监测2026年第一季季报-改4.docx `
  --config config\hongtang_config.json `
  --result-root "E:\洪塘大桥数据\2026年1-3月" `
  --wim-root "E:\洪塘大桥数据\2026年1-3月\WIM\results\hongtang" `
  --monitoring-range "2026年01月01日~2026年03月31日" `
  --start-date 2026-01-01 `
  --end-date 2026-03-31 `
  --debug-section cable_force
```

`--debug-section` can print `cable_force`, `vibration`, `wim`, or `health_status` from the generated manifest.
`--debug-section` 可输出生成清单中的 `cable_force`、`vibration`、`wim` 或 `health_status`，便于核查图片路径、统计值和缺失项。

The GUI performs a preflight check before generating a period report and warns when:
生成周期报前，GUI 会做输入校验，并在以下情况给出警告：

- `lowfreq/data.xlsx` is missing
- no raw `YYYY-MM-DD` directories are found under the selected data root
- `stats/` is missing
- WIM monthly result folders are missing for some months

- 缺少 `lowfreq/data.xlsx`
- 所选数据根目录下没有 `YYYY-MM-DD` 形式的原始数据目录
- 缺少 `stats/`
- 部分月份缺少 WIM 月结果目录


## Embedded report runtime / 内嵌报告运行时

The only operator entry is the **报告生成** page in `桥梁健康监测工作平台.exe`.
`report_gui.py` retains headless report contracts and developer self-tests, but
it cannot open a standalone window. The separate EXE build and package scripts
have been removed and must not be restored into the unified release.

用户唯一入口是 `桥梁健康监测工作平台.exe` 的“报告生成”页。`report_gui.py` 仅保留
后台报告契约和开发自测，不能再打开独立窗口；独立 EXE 构建和打包脚本已经删除，
不得重新放回统一发布包。

生产入口统一为 `桥梁健康监测工作平台.exe` 内的“报告生成”页面。以下内容只作为历史实现
和隔离兼容测试资料保留；旧界面、旧 EXE 构建和旧打包脚本默认拒绝运行，且不得进入统一
发布包。

Version `v1.7.39` adds the Hongtang typhoon full-data and quick-report workflows, Q2-template augmentation, audited acceleration RMS unit handling, and final caption/page-total locking. Version `v1.7.38` adds a guarded WPS Writer fallback that restores the original DOCX when field refresh creates broken references, plus OOXML reference-field and TOC-page staticization for stable locked delivery. Version `v1.7.37` adds the Hongtang W1/W2 wind diagnostic memo builder and lets legacy period templates pass precheck on their original deck-wind caption before the generator replaces it with the location-aware W1/W2 caption. Version `v1.7.36` reserves wind-rose title clearance above north and gives radial percentage labels a readable background. Version `v1.7.35` moves wind-rose radial percentage labels into the north-east interior so they do not overlap the east compass label. Version `v1.7.34` corrects wind-rose compass labels to the meteorological north-up/east-right orientation. Version `v1.7.33` rebuilds Hongtang wind calendar days from rolling D+D1 exports, rejects negative wind speed, carries source provenance into all report-facing wind plots, distinguishes bridge-deck W1 from tower-top W2, and clears stale template wind rows when a point is absent. Version `v1.7.32` adds configuration-backed Zhishan low-pass strain alarm wording, replacing fixed no-abnormality text with measured excursions and a raw-data/sensor/site-review qualification when a configured point boundary is exceeded; strict locked-media behavior is unchanged. Version `v1.7.31` adds an audited Zhishan source-quality note that is inserted into data coverage and monitoring summary text and recorded in the build manifest. Version `v1.7.30` keeps the report GUI/package version aligned with the Zhishan SX-5 low-pass retention correction. Version `v1.7.29` keeps the report GUI/package version aligned with the dynamic-strain source-retention correction. Version `v1.7.28` keeps the report GUI/package version aligned with the Zhishan CF-5 processing correction; report-generation behavior remains the strict v1.7.27 implementation. Version `v1.7.27` makes manifest-backed point-image lookup enforce exact point-token boundaries. This prevents prefix collisions such as `CS1` selecting the newer `CS12` figure (and `CX1` selecting `CX12`) in Hongtang period reports.

Version `v1.7.26` adds optional `require_source_provenance: true` bindings. When enabled, locked-media planning and application require each full plot series to carry pinned source sample/day counts and an explicit completeness scope, rejecting legacy plots that were labelled full only after upstream truncation. Explicitly disclosed incomplete source days remain admissible.

Version `v1.7.25` extends the locked-media workflow with plan schema v2 and an explicit `dimension_policy: "same_aspect_or_larger"` option for a higher-resolution source placed into an unchanged OOXML drawing extent. The candidate must keep the same format, stay at least as large in both dimensions, and remain within `max_aspect_ratio_error` (default `0.001`, hard maximum `0.01`). Candidate dimensions are pinned in the plan, candidate bytes are rechecked against their SHA-256 immediately before output, and legacy v1 plans remain exact-only.

Version `v1.7.24` adds a strict locked-media DOCX workflow. It compiles explicit baseline/member/candidate bindings, validates package and image hashes plus exact pixel dimensions, atomically replaces approved `word/media/*` members, and rejects any non-media OOXML change.

When an analysis manifest is supplied, every candidate image and its same-basename `.plot.json` must belong to the same manifest artifact record. All provenance series must be `full`, unreduced, and have matching finite/plotted counts; otherwise plan compilation and application both fail.

Version `v1.7.23` keeps the report GUI aligned with the Zhishan Q2 tight-clean rerun and rendered QA workflow. Report-builder behavior is unchanged from `v1.7.22`; the accepted reports were regenerated after rerunning the affected analysis modules and checking high-frequency key images.

Version `v1.7.22` adds the official Hongtang period-report auto template, derives quarterly report numbers, generalizes WIM anchors, validates copied WIM template tables before reuse, and removes stale picture blocks around target captions before inserting fresh figures. This lets a manually checked Hongtang Q2 report serve as the template base without duplicate figures or WIM continuation-table failures.

Version `v1.7.21` keeps the report GUI aligned with the MATLAB analysis release that preserves plot extrema across downsampled outputs and fixes earthquake peak/stat/marker consistency. The Hongtang Q2 report should be regenerated after rerunning the earthquake module so the summary and figures use the same full-resolution peak.

Version `v1.7.20` fixes Hongtang Q2 period reports so table 1-2 is regenerated from the Q2 maintenance log, earthquake peak summaries map `EQ` + component stats rows to `EQ-X/Y/Z`, and bearing-displacement cleaning removes values outside each point's level-2 alarm bounds before rerun/reporting.
Version `v1.7.19` restores Hongtang Q2 SG-6/SL-8 strain thresholds after the points recovered, makes the Hongtang low-frequency raw absolute-value guard sensor-specific so offset-corrected strain is not pre-filtered, switches Hongtang low-frequency cache to raw-only `__raw_v3.mat` files, documents the legacy inverted-threshold suppression workaround, fixes bearing-displacement raw-image lookup for `*_Orig.jpg` filenames, and converts static period-report figure/table captions to Word auto-number fields while preserving cross-reference bookmarks in the final build pass.
Version `v1.7.18` updates Hongtang period-report generation so WIM table/figure captions use Word auto-number fields, table 4-1 describes overload counts explicitly as 1.5/2.0-times thresholds, and bearing-displacement report images are read from the raw output folder after the analysis pipeline splits raw/filtered bearing-displacement figures.
Version `v1.7.17` aligns the GUI version with the Hongtang Q2 wind/earthquake timestamp-filename fallback fix. Report-builder behavior is unchanged from `v1.7.16`; the production report was regenerated after refreshing wind and earthquake figures through 2026-06-30.
Version `v1.7.16` fixes rendered period-report page totals when the template stores the total page count inside Word header/footer text boxes. Word COM field updates now repaginate, update header/footer shape fields, emit the computed page count, and patch stale hard-coded total-page text before final acceptance rendering.
Version `v1.7.14` hardens Hongtang period-report generation for Q2 reruns: Word field updates now fall back from missing Python COM to PowerShell Word COM, field-update failures are surfaced as manifest warnings, and the generated report should be rendered or exported for visual QA before acceptance.
Version `v1.7.12` commits the ShuiXianHua monthly builder period-label parsing and output filename generalization so CLI runs, smoke tests, and packaged exe builds use the same source revision.
版本 `v1.7.12` 提交水仙花月报生成器的监测期标签解析与输出文件名通用化修正，使 CLI、烟测和打包 exe 构建使用同一份源码。
Version `v1.7.11` fixes the packaged report-builder distribution so `config/bridge_profiles.json` and profile config files are copied next to the exe; packaged self-tests and default config discovery now work from `reporting/dist/BridgeReportBuilder`.
版本 `v1.7.11` 修复报告生成器打包产物，`config/bridge_profiles.json` 及各桥梁 profile 配置会复制到 exe 目录；打包版自测和默认配置发现可从 `reporting/dist/BridgeReportBuilder` 正常运行。
Version `v1.7.10` hardens the Jiulongjiang monthly report builder for production reruns: missing optional stats sheets no longer abort the build, the default Jiulongjiang template now uses the accepted 0508 report, and the profile default includes static strain output.
版本 `v1.7.10` 增强九龙江月报生成器的生产补跑稳定性：缺少可选统计表时不再中断生成，九龙江默认模板改用已确认的 0508 版本，profile 默认模块纳入静态应变输出。
Version `v1.7.9` refreshes Zhishan monthly report filling for month labels, data-availability wording, offline temperature/humidity placeholders, and config/result-aligned summary text while preserving the existing template-driven layout.
版本 `v1.7.9` 完善芝山月报生成器的月份标题、数据可用性说明、温湿度离线占位和与配置/结果一致的汇总文字，继续保持基于模板的版式回填方式。

Version `v1.7.8` reads Zhishan structural-vibration theoretical/search-frequency wording from the active config, keeping report summaries aligned with per-point spectrum peak-order settings.
版本 `v1.7.8` 会从当前配置读取芝山结构振动理论频率和搜索频率说明，使报告汇总文字与按测点频谱找峰配置保持一致。
Version `v1.7.7` upgrades the Zhishan monthly report generator to use main-analysis output figures for fallback-friendly report assembly and adds packaged-exe Zhishan self-test coverage.
版本 `v1.7.7` 升级芝山月报生成器，改用主分析程序输出图件完成便于人工兜底的报告组装，并补充打包 exe 的芝山自测覆盖。
Version `v1.7.6` keeps the report GUI version aligned with the Chongyangxi March processing/runtime package release; report-builder behavior is unchanged from v1.7.5.
版本 `v1.7.6` 与崇阳溪 3 月数据处理/运行时打包发布同步；报告生成器行为沿用 v1.7.5。
Version `v1.7.5` keeps the report GUI aligned with the Zhishan March data-processing release and documents the new Zhishan analysis/report asset workflow.
Version `v1.7.4` reads MATLAB analysis reporting contracts in report build manifests and reuses shared OOXML helpers for template table/text filling.
Version `v1.7.3` refactors Shuixianhua template-table updates around caption anchors, moves result-readiness checks into a profile/module catalog, and adds a packaged-exe self-test entry with `BridgeReportBuilder.exe --self-test-shuixianhua`.
版本 `v1.7.3` 将水仙花模板表格更新改为按题注锚点定位，结果就绪检查收口到 profile/module 目录，并新增 `BridgeReportBuilder.exe --self-test-shuixianhua` 打包程序自测入口。
Version `v1.7.2` fills the Shuixianhua section 2.2 monthly data-availability table from the acquisition summary when present, and falls back to deterministic config/stats-derived rows when that Excel is absent.
版本 `v1.7.2` 会在水仙花月报 2.2“本月监测数据情况”中优先读取测点获取统计表；缺少该 Excel 时，回退到配置和 stats 自动推导数据获取情况行。

Version `v1.7.1` updates the Shuixianhua monthly builder to copy the accepted template, refresh deterministic statistics/text in place, preserve Word auto-numbering/layout, and emit DOCX/PDF without tracked changes.
版本 `v1.7.1` 将水仙花月报生成改为复制已接受修订的模板后原位刷新可复现统计与文字，保留 Word 自动编号和版式，并输出不带修订痕迹的 DOCX/PDF。

Version `v1.7.0` aligns the report GUI with the main MATLAB GUI after the ShuiXianHua data-processing release, including standardized deflection group-plot folders and updated result-readiness checks.
版本 `v1.7.0` 与 MATLAB 数据分析 GUI 同步，覆盖水仙花数据处理发布内容，包括标准化挠度组图目录和更新后的结果就绪检查。

Version `v1.6.11` adds the Shuixianhua monthly report mode and keeps the GUI version aligned with the main MATLAB analysis GUI.
版本 `v1.6.11` 增加水仙花月报模式，并与 MATLAB 数据分析 GUI 版本号保持一致。

Version `v1.6.3` also replaces Guanbing monthly deflection/tilt figures from result images and refreshes the related statistics text.
版本 `v1.6.3` 进一步支持管柄月报按结果图替换挠度/倾角插图，并刷新相关统计文字。

Version `v1.6.2` separates report modes explicitly, writes template precheck reports, and writes missing-content summaries after generation.
版本 `v1.6.2` 已明确拆分报告类型，会输出模板预检报告，并在生成后输出缺失内容清单。

1. Select report type first: `洪塘月报`, `洪塘周期报（含WIM）`, or `九龙江月报`.
2. Confirm the auto-switched template, config, and data/result root.
3. Click `检查模板/目录` before generation.
4. If the check has no blocking error, click `生成报告`.
5. Review `<输出目录>/precheck/` when the GUI reports template anchors or result folders are missing.

1. 先选择报告类型：`洪塘月报`、`洪塘周期报（含WIM）` 或 `九龙江月报`。
2. 确认程序自动切换后的模板、配置和数据/结果根目录。
3. 生产机生成前先点击 `检查模板/目录`。
4. 没有阻断错误后再点击 `生成报告`。
5. 如果提示模板锚点或结果目录缺失，到 `<输出目录>/precheck/` 查看 txt/json 预检报告。

Report mode notes.
报告类型说明。

- `洪塘月报`: legacy Hongtang monthly-report pipeline for one calculated month.
- `洪塘周期报（含WIM）`: Hongtang period/quarter report, including WIM monthly insertion and section 1.4 raw-missing checks.
- `九龙江月报`: independent Jiulongjiang monthly-report pipeline for main bridge and ramp-bridge sections.

- `洪塘月报`：旧洪塘月报流程，适用于单月已计算结果。
- `洪塘周期报（含WIM）`：洪塘周期/季报流程，包含 WIM 按月插入和 1.4 原始数据缺失统计。
- `九龙江月报`：九龙江独立月报流程，按主桥和匝道桥章节生成。

## Output Locations / 输出位置

- Report document / 报告文档: `<result-root>/自动报告/`
- Precheck reports / 模板预检报告: `<result-root>/自动报告/precheck/`
- Missing-content summaries / 缺失内容清单: next to the generated report as `*_missing_summary.txt` and `*_missing_summary.xlsx`
- Stats workbooks / 统计表: `<result-root>/stats/`
- Run logs / 运行日志: `<result-root>/run_logs/`
- WIM monthly results / WIM 月结果: `<result-root>/WIM/results/hongtang/<yyyymm>/`

## Template Precheck / 模板预检

The precheck verifies key headings, table captions, figure-caption anchors, and auto-number fields before generation.
预检会在生成前检查关键标题、表题、图题插入锚点和自动编号域。

GUI checks write both text and JSON reports under `<输出目录>/precheck/`.
GUI 检查会在 `<输出目录>/precheck/` 同时写入 txt 和 json 报告。

CLI examples.
CLI 示例。

```powershell
python reporting\template_precheck.py `
  --kind hongtang_period `
  --template reports\洪塘大桥健康监测2026年第一季季报-改4.docx `
  --output-dir tmp\report_precheck

python reporting\smoke_report_generation.py --kind all
```

## Missing Content Summary / 缺失内容清单

After a report is generated, the builder writes a txt and an xlsx summary next to the generated docx.
报告生成后，程序会在生成的 docx 同目录输出 txt 和 xlsx 缺失内容清单。

The summary lists sections with no effective data, missing images/resources, and WIM warnings.
清单会列出无有效数据章节、缺失图片/资源和 WIM 警告。

## Unit Tests / 单元测试

Run the lightweight Python tests before packaging report-builder changes.
报告生成器改动打包前，先运行轻量 Python 单元测试。

```powershell
.\reporting\.venv\Scripts\python.exe -m unittest discover -s tests_py -v
python reporting\smoke_report_generation.py --kind all
```

## WIM SQL Troubleshooting / WIM SQL 故障排查

Common WIM SQL failures are classified explicitly.
WIM SQL 常见故障现在会明确分类显示。

- `WIM:SQL:Instance`
  - Cannot connect to the SQL Server instance.
  - Check `wim_db.server`, `wim_db.service_name`, and whether the SQL Server service is running.
  - 无法连接 SQL Server 实例；检查 `wim_db.server`、`wim_db.service_name` 和 SQL Server 服务状态。

- `WIM:SQL:Permission`
  - The current Windows user does not have enough SQL Server or bulk import permissions.
  - Re-run `scripts/setup_wim_sql.ps1` or grant SQL permissions manually.
  - 当前 Windows 用户缺少 SQL Server 或 bulk import 权限；可重新运行 `scripts/setup_wim_sql.ps1` 或手工授权。

- `WIM:SQL:DatabaseMissing`
  - The configured database cannot be opened or does not exist.
  - Check `wim_db.database` and create `HighSpeed_PROC` first.
  - 目标数据库不存在或无法打开；检查 `wim_db.database` 并先创建 `HighSpeed_PROC`。

- `WIM:Input:MissingFmt`
  - The monthly `HS_Data_YYYYMM.fmt` file is missing.
  - For Hongtang, the default raw WIM directory is `<data-root>/WIM`.
  - Check `wim.input.zhichen.dir` and the month-specific input files.
  - 缺少当月 `HS_Data_YYYYMM.fmt`；洪塘默认原始称重目录为 `<数据根目录>/WIM`，请检查 `wim.input.zhichen.dir` 和对应月份文件。

- `WIM:Input:MissingBcp`
  - The monthly `HS_Data_YYYYMM.bcp` file is missing.
  - For Hongtang, the default raw WIM directory is `<data-root>/WIM`.
  - Check `wim.input.zhichen.dir` and the month-specific input files.
  - 缺少当月 `HS_Data_YYYYMM.bcp`；洪塘默认原始称重目录为 `<数据根目录>/WIM`，请检查 `wim.input.zhichen.dir` 和对应月份文件。

