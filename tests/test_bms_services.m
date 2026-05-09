classdef test_bms_services < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'config'), fullfile(proj, 'pipeline'), fullfile(proj, 'analysis'), fullfile(proj, 'scripts'));
        end
    end

    methods (Test)
        function configPatchSetsNestedPath(tc)
            cfg = struct();
            cfg = bms.config.ConfigPatch.setPath(cfg, 'plot_common.gap_mode', 'connect');
            cfg.plot_common.enabled = 'yes';
            cfg.plot_common.limit = '12.5';
            [tf, value] = bms.config.ConfigPatch.getPath(cfg, 'plot_common.gap_mode');
            tc.verifyTrue(tf);
            tc.verifyEqual(value, 'connect');
            tc.verifyEqual(bms.config.ConfigReader.get(cfg, 'plot_common.gap_mode', 'break'), 'connect');
            tc.verifyEqual(bms.config.ConfigReader.get(cfg, 'missing.value', 42), 42);
            tc.verifyEqual(bms.config.ConfigReader.getStruct(cfg, 'missing.struct'), struct());
            tc.verifyTrue(bms.config.ConfigReader.getBool(cfg, 'plot_common.enabled', false));
            tc.verifyEqual(bms.config.ConfigReader.getNumeric(cfg, 'plot_common.limit', 0), 12.5);
            tc.verifyEqual(bms.config.ConfigReader.getField(cfg.plot_common, 'missing', 'x'), 'x');
            merged = bms.config.ConfigReader.mergeStruct(struct('a', 1, 'b', 2), struct('b', 3));
            tc.verifyEqual(merged.a, 1);
            tc.verifyEqual(merged.b, 3);
        end

        function schemaValidatorFindsThresholdIssue(tc)
            cfg = struct('defaults', struct(), 'subfolders', struct(), 'file_patterns', struct(), 'points', struct(), 'plot_styles', struct());
            cfg.per_point.strain.PT1.thresholds = struct('min', 10, 'max', -10);
            warns = bms.config.SchemaValidator.validate(cfg);
            tc.verifyTrue(any(contains(warns, 'min > max')));
        end

        function pointAndTimeResolversWork(tc)
            tc.verifyEqual(bms.data.PointResolver.safeId('A-1'), 'A_1');
            cfg = struct('points', struct('wind', {{'W1','W2'}}));
            tc.verifyEqual(bms.data.PointResolver.fromConfig(cfg, 'wind', {'fallback'}), {'W1'; 'W2'});
            tc.verifyEqual(bms.data.PointResolver.fromConfig(cfg, 'missing', {'fallback'}), {'fallback'});
            cfg.points.wind = {};
            tc.verifyEmpty(bms.data.PointResolver.fromConfig(cfg, 'wind', {'fallback'}));
            groups = bms.data.PointResolver.normalizeGroups(struct('G1', {{'A-1', 'A-1'}}, 'G2', {{'B-1'}}));
            tc.verifyEqual(groups.G1, {'A-1'});
            tc.verifyTrue(bms.data.PointResolver.hasGroups(groups));
            tc.verifyEqual(bms.data.PointResolver.flattenGroups(groups), {'A-1'; 'B-1'});
            days = bms.data.TimeRangeResolver.daysBetween('2026-01-01', '2026-01-03');
            tc.verifyEqual(numel(days), 3);
            months = bms.data.TimeRangeResolver.monthKeys('2026-01-15', '2026-03-01');
            tc.verifyEqual(months, {'202601','202602','202603'});

            root = tempname;
            statsPath = bms.data.DataLayoutResolver.statsFile(root, 'unit.xlsx');
            tc.verifyTrue(endsWith(statsPath, fullfile('stats', 'unit.xlsx')));
            tc.verifyTrue(isfolder(fileparts(statsPath)));
        end

        function dataLayoutAdaptersDiscoverFolders(tc)
            tmp = tempname;
            mkdir(tmp);
            cleanup = onCleanup(@() cleanup_temp_dir(tmp)); %#ok<NASGU>

            datedSub = fullfile(tmp, '2026-01-01', 'wave');
            mkdir(datedSub);
            tc.verifyTrue(bms.data.DatedFolderAdapter.hasDateFolders(tmp));
            datedFolders = bms.data.DatedFolderAdapter.dateFolders(tmp, '2026-01-01', '2026-01-02');
            tc.verifyEqual(numel(datedFolders), 1);
            datedDirs = bms.data.DatedFolderAdapter.candidateDirs(tmp, 'wave', '2026-01-01', '2026-01-02');
            tc.verifyEqual(numel(datedDirs), 1);
            tc.verifyEqual(datedDirs{1}, char(java.io.File(datedSub).getCanonicalPath()));

            zipCsv = fullfile(tmp, 'data_sxh_2026-03-23', 'data', 'sxh', 'csv');
            mkdir(zipCsv);
            fclose(fopen(fullfile(zipCsv, 'PT-1.csv'), 'w'));
            cfg = struct('vendor', 'shuixianhua');
            tc.verifyTrue(bms.data.ZipDailyExportAdapter.hasExtracted(tmp, cfg));
            csvDirs = bms.data.ZipDailyExportAdapter.csvDirs(tmp, '2026-03-23', '2026-03-23', cfg);
            tc.verifyEqual(numel(csvDirs), 1);
            csvRecords = bms.data.ZipDailyExportAdapter.collectCsvPointIds(tmp, '2026-03-23', '2026-03-23', cfg);
            tc.verifyEqual(csvRecords{1}.point_id, 'PT-1');
            info = bms.data.DataLayoutResolver.describe(tmp, cfg);
            tc.verifyEqual(info.layout, 'jlj_daily_export');
            tc.verifyEqual(info.adapter, 'bms.data.ZipDailyExportAdapter');

            lowfreqSub = fullfile(tmp, 'lowfreq', 'strain');
            mkdir(lowfreqSub);
            tc.verifyTrue(bms.data.PeriodFolderAdapter.hasPeriodLayout(tmp));
            periodDirs = bms.data.PeriodFolderAdapter.candidateDirs(tmp, 'strain', '2026-01-01', '2026-03-31');
            tc.verifyEqual(numel(periodDirs), 1);
            tc.verifyEqual(periodDirs{1}, char(java.io.File(lowfreqSub).getCanonicalPath()));
        end

        function bridgeProfilesValidateAndSummarize(tc)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            profiles = bms.profile.BridgeProfileRegistry.catalog(projectRoot);
            ids = arrayfun(@(p) p.BridgeId, profiles, 'UniformOutput', false);
            tc.verifyTrue(all(ismember({'guanbing','hongtang','jiulongjiang','shuixianhua'}, ids)));

            validation = bms.profile.BridgeProfileRegistry.validateCatalog(projectRoot);
            tc.verifyEmpty(validation.errors);
            tc.verifyGreaterThanOrEqual(validation.profile_count, 4);

            p = bms.profile.BridgeProfileRegistry.fromId('shuixianhua', projectRoot);
            tc.verifyEqual(p.DefaultStartDate, '2026-03-23');
            tc.verifyEqual(p.DefaultEndDate, '2026-03-31');
            text = bms.gui.GuiRunController.profileSummary(p);
            tc.verifyTrue(contains(text, 'shuixianhua_config.json'));
            tc.verifyTrue(contains(text, '2026-03-23'));
        end

        function runPreflightWritesJsonAndKeepsCoverage(tc)
            tmp = tempname;
            mkdir(tmp);
            cleanup = onCleanup(@() cleanup_temp_dir(tmp)); %#ok<NASGU>
            cfg = struct();
            cfg.vendor = 'shuixianhua';
            cfg.defaults = struct();
            cfg.subfolders = struct();
            cfg.file_patterns = struct();
            cfg.points = struct();
            cfg.plot_styles = struct();
            cfg.points.temperature = {'PT-1'};
            cfg.subfolders.temperature = '';
            csvDir = fullfile(tmp, 'data_sxh_2026-03-23', 'data', 'sxh', 'csv');
            mkdir(csvDir);
            fclose(fopen(fullfile(csvDir, 'PT-1.csv'), 'w'));
            opts = struct('doTemp', true, 'buildRunHealthReport', true);
            request = bms.app.RunRequest.fromLegacy(tmp, '2026-03-23', '2026-03-23', opts, cfg);
            preflight = bms.app.RunPreflight.check(request);
            jsonPath = bms.app.RunPreflight.writeJson(request, preflight);
            tc.verifyTrue(isfile(jsonPath));
            payload = jsondecode(fileread(jsonPath));
            rows = bms.app.ManifestReader.recordsToCell(payload.point_coverage);
            tc.verifyEqual(rows{1}.found_count, 1);
            tc.verifyTrue(isfield(payload, 'data_index_path'));
            tc.verifyTrue(isfile(payload.data_index_path));
            tc.verifyTrue(isfield(payload, 'data_index_summary_path'));
            tc.verifyTrue(isfile(payload.data_index_summary_path));
            tc.verifyEqual(payload.data_index.summary.found_point_count, 1);
            tc.verifyTrue(isfield(payload, 'stats_inventory_summary_path'));
            tc.verifyTrue(isfile(payload.stats_inventory_summary_path));
            tc.verifyTrue(isfield(payload, 'run_health_report_summary_path'));
            tc.verifyTrue(isfile(payload.run_health_report_summary_path));
            tc.verifyGreaterThanOrEqual(payload.run_health_report.issue_counts.total, 1);
        end

        function plotServiceHandlesTimeAxis(tc)
            fig = figure('Visible', 'off');
            cleaner = onCleanup(@() close(fig)); %#ok<NASGU>
            t = datetime(2026,1,1,0,0,0) + minutes(0:2);
            plot(t, [1 2 3]);
            bms.plot.PlotService.setTimeAxis([NaT; t(:); NaT]);
            ax = gca;
            tc.verifyEqual(ax.XLim(1), t(1));
            tc.verifyEqual(ax.XLim(2), t(end));

            tc.verifyWarningFree(@() bms.plot.PlotService.setTimeAxis(NaT(3,1)));
        end

        function plotServiceNormalizesStyleValues(tc)
            ylims.PT_1 = [-1 1];
            ylims.items = struct('name', 'P-2', 'ylim', [0 2]);
            tc.verifyEqual(bms.plot.PlotService.resolveNamedYLim(ylims, 'PT-1', []), [-1 1]);
            tc.verifyEqual(bms.plot.PlotService.resolveNamedYLim(ylims.items, 'P-2', []), [0 2]);
            tc.verifyTrue(bms.plot.PlotService.isValidYLim([0 Inf]));
            tc.verifyFalse(bms.plot.PlotService.isValidYLim([1 0]));

            c = bms.plot.PlotService.normalizeColors([1 0 0; 0 1 0], {});
            tc.verifyTrue(iscell(c));
            tc.verifyEqual(numel(c), 2);
            tc.verifyEqual(c{1}, [1 0 0]);

            defaults = [0 0 1; 1 0 1];
            m = bms.plot.PlotService.normalizeColors({'bad'}, defaults);
            tc.verifyEqual(m, defaults);
        end

        function statsWriterCreatesParentAndWrites(tc)
            tmp = tempname;
            cleanup = onCleanup(@() cleanup_temp_dir(tmp)); %#ok<NASGU>
            out = fullfile(tmp, 'nested', 'stats.xlsx');
            T = table((1:2)', ["a"; "b"], 'VariableNames', {'ID', 'Name'});
            bms.io.StatsWriter.writeTable(T, out);
            tc.verifyTrue(isfile(out));
            R = readtable(out, 'VariableNamingRule', 'preserve');
            tc.verifyEqual(height(R), 2);

            out2 = fullfile(tmp, 'nested', 'module_stats.xlsx');
            bms.io.StatsWriter.writeModuleTableChecked(T, out2, 'unit');
            tc.verifyTrue(isfile(out2));
        end

        function statsSchemaAndWarningEvaluatorWork(tc)
            schema = bms.io.StatsSchema.forModule('deflection');
            tc.verifyEqual(bms.io.StatsSchema.decimalsFor(schema, 'FiltMax_mm'), 1);
            T = table([1.234; 5.678], [2.345; 6.789], 'VariableNames', {'FiltMin_mm', 'FiltMax_mm'});
            T = bms.io.StatsSchema.normalizeTable(T, 'deflection');
            tc.verifyEqual(T.FiltMin_mm(1), 1.2);
            tc.verifyEqual(T.FiltMax_mm(2), 6.8);

            r = bms.core.WarningEvaluator.evaluateRange(-1, 12, -10, 10, -20, 20, 'unit');
            tc.verifyEqual(r.status, 'exceeded');
            tc.verifyEqual(r.level, 2);
            rows = struct('PointID', {'P1','P2'}, 'Min', {-1,-30}, 'Max', {1, 2});
            results = bms.core.WarningEvaluator.evaluateRows(rows, 'Min', 'Max', -10, 10, -20, 20);
            summary = bms.core.WarningEvaluator.summarize(results);
            tc.verifyEqual(summary.exceeded, 1);
            tc.verifyEqual(summary.max_level, 3);
        end

        function statsInventoryScansExpectedFiles(tc)
            tmp = tempname;
            mkdir(tmp);
            cleanup = onCleanup(@() cleanup_temp_dir(tmp)); %#ok<NASGU>
            statsDir = fullfile(tmp, 'stats');
            mkdir(statsDir);
            T = table({'PT-1'}, 1.2, 3.4, 2.3, 'VariableNames', {'PointID','Min','Max','Mean'});
            writetable(T, fullfile(statsDir, 'temp_stats.xlsx'));

            inventory = bms.io.StatsInventory.build(tmp, struct('doTemp', true, 'doHumidity', true), struct());
            tc.verifyEqual(inventory.summary.stats_expected_count, 2);
            tc.verifyEqual(inventory.summary.stats_existing_count, 1);
            tc.verifyEqual(inventory.summary.stats_missing_count, 1);

            rows = bms.io.StatsInventory.rows(inventory);
            tc.verifyEqual(height(rows), 2);
            tc.verifyTrue(any(strcmp(rows.status, 'ok')));
            tc.verifyTrue(any(strcmp(rows.status, 'missing')));

            jsonPath = bms.io.StatsInventory.write(tmp, inventory, 'unit');
            xlsxPath = bms.io.StatsInventory.writeSummary(tmp, inventory, 'unit');
            tc.verifyTrue(isfile(jsonPath));
            tc.verifyTrue(isfile(xlsxPath));
        end

        function runHealthReportSummarizesIssues(tc)
            preflight = struct();
            preflight.status = 'warning';
            preflight.root = 'R';
            preflight.start_date = '2026-01-01';
            preflight.end_date = '2026-01-31';
            preflight.errors = {};
            preflight.warnings = {'sample warning'};
            preflight.point_coverage = {struct('key', 'temperature', 'designed_count', 2, 'found_count', 1, 'missing_count', 1)};
            preflight.data_index = struct('summary', struct('point_count', 2), ...
                'modules', {{struct('key', 'temperature', 'point_count', 2, 'missing_point_count', 1)}});
            preflight.stats_inventory = struct('summary', struct('stats_expected_count', 1), ...
                'modules', {{struct('key', 'temperature', 'status', 'missing', 'message', 'missing stats')}});

            report = bms.app.RunHealthReport.build(preflight);
            tc.verifyEqual(report.issue_counts.warning, 4);
            rows = bms.app.RunHealthReport.issueRows(report);
            tc.verifyEqual(height(rows), 4);
            tc.verifyTrue(any(strcmp(rows.issue_type, 'stats_missing')));
        end

        function manifestWriterAddsSchemaAndMissingStats(tc)
            tmp = tempname;
            mkdir(tmp);
            cleanup = onCleanup(@() rmdir(tmp, 's'));
            ctx = bms.core.AnalysisContext(tmp, '2026-01-01', '2026-01-01', struct(), struct(), 'RunId', 'manifest_unit');
            details = struct('expected_stats_files', {{fullfile(tmp, 'stats', 'missing.xlsx')}}, ...
                'module_logs', {{}}, 'stats_files', {{}}, ...
                'run_preflight', struct('data_index_path', 'index.json', 'data_index_summary_path', 'index.xlsx', ...
                'stats_inventory_path', 'stats.json', 'stats_inventory_summary_path', 'stats.xlsx', ...
                'run_health_report_path', 'health.json', 'run_health_report_summary_path', 'health.xlsx'));
            manifestPath = bms.app.ManifestWriter.write(ctx, 'ok', details);
            tc.verifyTrue(isfile(manifestPath));
            manifest = jsondecode(fileread(manifestPath));
            tc.verifyEqual(manifest.schema_version, 2);
            tc.verifyEqual(manifest.manifest_type, 'analysis_run');
            tc.verifyTrue(isfield(manifest, 'stats_schema_registry'));
            tc.verifyEqual(manifest.data_index_summary_path, 'index.xlsx');
            tc.verifyEqual(manifest.stats_inventory_summary_path, 'stats.xlsx');
            tc.verifyEqual(manifest.run_health_report_summary_path, 'health.xlsx');
            tc.verifyEqual(numel(manifest.missing_expected_stats), 1);
            clear cleanup;
        end
    end
end

function cleanup_temp_dir(p)
    if exist(p, 'dir')
        rmdir(p, 's');
    end
end
