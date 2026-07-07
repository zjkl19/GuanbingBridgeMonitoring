# Report Templates

This directory keeps only current official report templates under version control.
Generated reports, temporary drafts, old revisions, reference spreadsheets, and PDFs should stay outside Git.

## Tracked Templates

- `洪塘大桥健康监测周期报模板-自动报告.docx`
  - Current Hongtang period/quarter auto-report template.
  - Based on the manually checked 2026 Q2 report, with revisions accepted and generator-owned content refreshed in place.
- `洪塘大桥健康监测2026年第一季季报-改4.docx`
  - Legacy Hongtang period/quarter report template retained for compatibility
    and Q1 reference.
- `洪塘大桥健康监测月报模板.docx`
  - Current Hongtang monthly report template.
- `九龙江大桥健康监测2026年3月份月报_修订5.docx`
  - Current Jiulongjiang monthly report template.
  - Used by `reporting/build_jlj_monthly_report.py`.
- `水仙花大桥健康监测月报模板.docx`
  - Current Shuixianhua monthly report template.
  - Used by `reporting/build_shuixianhua_monthly_report.py` and the report GUI.
- `assets/shuixianhua_layouts/`
  - Cropped Shuixianhua layout figures extracted from the as-built drawing PDF.
  - Used by the Shuixianhua monthly report generator for measurement layout figures.

## Local Files

Keep these local-only unless there is a clear reason to track them:

- generated `*_自动生成_*.docx`
- temporary cleaned templates
- old company-review drafts
- reference PDFs
- warning-threshold spreadsheets

If a new template becomes official, add it explicitly and update this README plus `.gitignore`.
