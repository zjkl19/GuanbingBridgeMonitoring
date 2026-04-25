# Report Templates

This directory keeps only current official report templates under version control.
Generated reports, temporary drafts, old revisions, reference spreadsheets, and PDFs should stay outside Git.

## Tracked Templates

- `洪塘大桥健康监测2026年第一季季报-改4.docx`
  - Current Hongtang period/quarter report template.
  - Used by `reporting/build_period_report.py` and the report GUI period-report mode.
- `洪塘大桥健康监测月报模板.docx`
  - Current Hongtang monthly report template.
- `九龙江大桥健康监测2026年3月份月报_修订5.docx`
  - Current Jiulongjiang monthly report template.
  - Used by `reporting/build_jlj_monthly_report.py`.

## Local Files

Keep these local-only unless there is a clear reason to track them:

- generated `*_自动生成_*.docx`
- temporary cleaned templates
- old company-review drafts
- reference PDFs
- warning-threshold spreadsheets

If a new template becomes official, add it explicitly and update this README plus `.gitignore`.
