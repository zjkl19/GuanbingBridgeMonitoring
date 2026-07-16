classdef test_bms_services < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'config'), fullfile(proj, 'pipeline'), fullfile(proj, 'analysis'), fullfile(proj, 'scripts'));
        end
    end

    methods (Test)
        function loggerPublishesCompleteJsonWithoutTempResidue(tc)
            folder = tempname;
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's')); %#ok<NASGU>
            path = fullfile(folder, 'status.json');
            for generation = 1:5
                payload = struct( ...
                    'status', 'running', ...
                    'generation', generation, ...
                    'message', sprintf('完整状态-%d', generation));
                bms.core.Logger.writeJson(path, payload);
                decoded = jsondecode(fileread(path));
                tc.verifyEqual(decoded.generation, generation);
                tc.verifyEqual(decoded.message, payload.message);
                tc.verifyEmpty(dir(fullfile(folder, '*.json.tmp')));
            end

            % MATLAB represents non-BMP characters differently across text
            % readers.  The byte-level publication check must nevertheless
            % accept and publish valid UTF-8 JSON instead of comparing decoded
            % character-vector lengths.
            emoji = native2unicode(uint8([240 159 152 128]), 'UTF-8');
            bms.core.Logger.writeJson(path, struct( ...
                'status', 'running', 'generation', 6, 'message', emoji));
            decoded = jsondecode(fileread(path));
            tc.verifyEqual(decoded.generation, 6);
            tc.verifyEmpty(dir(fullfile(folder, '*.json.tmp')));
        end

        function loggerLargeJsonIsCompactAndRoundTripsPastOneMiCharacter(tc)
            folder = tempname;
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's')); %#ok<NASGU>
            path = fullfile(folder, 'large_manifest.json');
            payload = struct( ...
                'status', 'failed', ...
                'body', repmat('x', 1, 1200000), ...
                'tail_marker', 'END_MARKER');

            bms.core.Logger.writeJson(path, payload);

            raw = fileread(path);
            tc.verifyGreaterThan(numel(raw), 1048576);
            tc.verifyFalse(contains(raw, newline));
            decoded = jsondecode(raw);
            tc.verifyEqual(decoded.tail_marker, payload.tail_marker);
            tc.verifyEqual(numel(decoded.body), numel(payload.body));
            tc.verifyEmpty(dir(fullfile(folder, '*.json.tmp')));
        end

        function artifactCollectorBindsExactBytesAndSha256(tc)
            folder = tempname;
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, 's')); %#ok<NASGU>
            path = fullfile(folder, 'artifact.png');
            fid = fopen(path, 'wb');
            fwrite(fid, uint8([0 1 2 3 254 255]), 'uint8');
            fclose(fid);

            record = bms.data.ArtifactCollector.record('figure', path, 'time_history');
            tc.verifyTrue(record.exists);
            tc.verifyEqual(record.bytes, 6);
            tc.verifyEqual(record.sha256, bms.io.JsonFile.sha256(path));
            tc.verifyEqual(numel(record.sha256), 64);
            tc.verifyNotEmpty(regexp(record.sha256, '^[0-9a-f]{64}$', 'once'));
        end

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
            rawPoint = 'GLYB-05-10#Pier-X';
            legacyKey = bms.data.PointResolver.legacySafeId(rawPoint);
            safeKey = bms.data.PointResolver.safeId(rawPoint);
            tc.verifyNotEqual(safeKey, legacyKey);
            tc.verifyNotEqual( ...
                bms.data.PointResolver.safeId('P-1#A'), ...
                bms.data.PointResolver.safeId('P-1/A'));

            cfgForPoint = struct();
            cfgForPoint.points = struct('strain', {{rawPoint}});
            cfgForPoint.per_point = struct('strain', struct());
            cfgForPoint.per_point.strain.(legacyKey) = struct( ...
                'thresholds', struct('min', -1, 'max', 1));
            [ok, pointCfg, matchedKey] = bms.data.PointResolver.getPointConfig( ...
                cfgForPoint.per_point.strain, rawPoint, cfgForPoint);
            tc.verifyTrue(ok);
            tc.verifyEqual(matchedKey, legacyKey);
            tc.verifyEqual(pointCfg.thresholds.min, -1);
            tc.verifyEqual(bms.data.PointResolver.originalId(legacyKey, cfgForPoint), rawPoint);

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

        function loadConfigRecoversDisplayIdsFromConfiguredPoints(tc)
            tmp = [tempname '.json'];
            cleanup = onCleanup(@() cleanup_file(tmp)); %#ok<NASGU>
            rawPoint = 'GLYB-05-10#Pier-X';
            legacyKey = bms.data.PointResolver.legacySafeId(rawPoint);
            fid = fopen(tmp, 'wt', 'n', 'UTF-8');
            fprintf(fid, ['{"vendor":"unit","defaults":{"header_marker":"time"},' ...
                '"subfolders":{},"file_patterns":{},"groups":{"strain":{"G1":["%s"]}},' ...
                '"plot_styles":{},"per_point":{"strain":{"%s":{"thresholds":[{"min":-1,"max":1}]}}}}'], ...
                rawPoint, legacyKey);
            fclose(fid);

            cfg = load_config(tmp);
            tc.verifyTrue(isfield(cfg, 'name_map_global'));
            tc.verifyEqual(cfg.name_map_global.(legacyKey), rawPoint);
            tc.verifyEqual(bms.data.PointResolver.originalId(legacyKey, cfg), rawPoint);
        end

        function saveConfigRoundTripsRawPointKeys(tc)
            tmp = [tempname '.json'];
            cleanup = onCleanup(@() cleanup_file(tmp)); %#ok<NASGU>
            rawPoint = 'GLYB-05-10#Pier-X';
            safeKey = bms.data.PointResolver.configKey(rawPoint);

            cfg = struct();
            cfg.vendor = 'unit';
            cfg.defaults = struct('header_marker', 'time');
            cfg.subfolders = struct();
            cfg.file_patterns = struct();
            cfg.groups = struct('strain', struct('G1', {{rawPoint}}));
            cfg.plot_styles = struct();
            cfg.per_point = struct('strain', struct());
            cfg.per_point.strain.(safeKey) = struct( ...
                'thresholds', struct('min', -1, 'max', 1));
            cfg.name_map_global = struct();
            cfg.name_map_global.(safeKey) = rawPoint;

            save_config(cfg, tmp, false);
            txt = fileread(tmp);
            tc.verifyTrue(contains(txt, ['"' rawPoint '":']));
            loaded = load_config(tmp);
            [ok, pointCfg] = bms.data.PointResolver.getPointConfig( ...
                loaded.per_point.strain, rawPoint, loaded);
            tc.verifyTrue(ok);
            tc.verifyEqual(pointCfg.thresholds.max, 1);
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

        function preparePlotSeriesLimitsLargeSeries(tc)
            t = (datetime(2026,1,1,0,0,0) + seconds(0:99)).';
            y = (1:100).';

            [tp, yp] = prepare_plot_series(t, y, struct('gap_mode', 'connect', 'fig_max_points', 10));

            tc.verifyLessThanOrEqual(numel(tp), 10);
            tc.verifyEqual(tp(1), t(1));
            tc.verifyEqual(tp(end), t(end));
            tc.verifyEqual(yp(1), y(1));
            tc.verifyEqual(yp(end), y(end));
        end

        function structuralDateAxisHandlesNumericDateAxes(tc)
            fig = figure('Visible', 'off');
            cleaner = onCleanup(@() close(fig)); %#ok<NASGU>
            dt0 = datetime(2026,4,1);
            dt1 = datetime(2026,6,30);
            plot(datenum(dt0 + days(0:2)), [1 2 3]);

            tc.verifyWarningFree(@() bms.analyzer.StructuralTimeSeriesPlotService.applyDateAxis(dt0, dt1));
            ax = gca;
            tc.verifyEqual(ax.XLim, datenum([dt0 dt1]), 'AbsTol', 1e-9);
        end

        function plotServiceNormalizesStyleValues(tc)
            ylims.PT_1 = [-1 1];
            ylims.items = struct('name', 'P-2', 'ylim', [0 2]);
            tc.verifyEqual(bms.plot.PlotService.resolveNamedYLim(ylims, 'PT-1', []), [-1 1]);
            tc.verifyEqual(bms.plot.PlotService.resolveNamedYLim(ylims.items, 'P-2', []), [0 2]);
            tc.verifyTrue(bms.plot.PlotService.isValidYLim([0 Inf]));
            tc.verifyTrue(bms.plot.PlotService.isValidYLim([-400; 400]));
            tc.verifyEqual(bms.plot.PlotService.normalizeYLim([-400; 400]), [-400 400]);
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

        function statsWriterReplacesStaleSingleSheetRows(tc)
            tmp = tempname;
            cleanup = onCleanup(@() cleanup_temp_dir(tmp)); %#ok<NASGU>
            out = fullfile(tmp, 'stats.xlsx');
            T1 = table((1:3)', ["a"; "b"; "c"], 'VariableNames', {'ID', 'Name'});
            T2 = table(1, "a", 'VariableNames', {'ID', 'Name'});

            bms.io.StatsWriter.writeTable(T1, out);
            bms.io.StatsWriter.writeTable(T2, out);

            R = readtable(out, 'VariableNamingRule', 'preserve');
            tc.verifyEqual(height(R), 1);
            tc.verifyEqual(R.ID(1), 1);
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
            tc.verifyEqual(manifest.schema_version, bms.app.ManifestWriter.SchemaVersion);
            tc.verifyEqual(manifest.manifest_type, 'analysis_run');
            tc.verifyTrue(isfield(manifest, 'stats_schema_registry'));
            tc.verifyEqual(manifest.data_index_summary_path, 'index.xlsx');
            tc.verifyEqual(manifest.stats_inventory_summary_path, 'stats.xlsx');
            tc.verifyEqual(manifest.run_health_report_summary_path, 'health.xlsx');
            tc.verifyEqual(numel(manifest.missing_expected_stats), 1);
            clear cleanup;
        end

        function manifestWriterFallsBackToValidFailedManifest(tc)
            tmp = tempname;
            mkdir(tmp);
            cleanup = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>
            ctx = bms.core.AnalysisContext(tmp, '2026-01-01', '2026-01-01', ...
                struct(), struct(), 'RunId', 'manifest_fallback_unit');
            record = struct('key', 'temperature', 'label', 'temperature', ...
                'status', 'ok', 'artifacts', {{struct('path', 'large.bin')}});
            details = struct('module_logs', {{record}}, ...
                'log_file', fullfile(tmp, 'run.log'), ...
                'elapsed_sec', 12.5, ...
                'unencodable_test_value', @sin);

            manifestPath = bms.app.ManifestWriter.write(ctx, 'ok', details);

            tc.verifyTrue(endsWith(manifestPath, '_write_failure.json'));
            manifest = jsondecode(fileread(manifestPath));
            tc.verifyEqual(manifest.status, 'failed');
            tc.verifyEqual(manifest.requested_status, 'ok');
            tc.verifyEqual(manifest.error_type, 'manifest_write_error');
            tc.verifyEqual(manifest.module_status_counts.ok, 1);
            tc.verifyEqual(manifest.module_results.artifact_count, 0);
            tc.verifyEmpty(manifest.module_results.artifacts);
        end

        function manifestWriterFallsBackWhenFullBuildFails(tc)
            tmp = tempname;
            mkdir(tmp);
            cleanup = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>
            ctx = bms.core.AnalysisContext(tmp, '2026-01-01', '2026-01-01', ...
                struct(), struct(), 'RunId', 'manifest_build_fallback_unit');
            details = struct();
            % findMissing() cannot consume a struct.  This deterministic bad
            % field fails while build()/applyDetails() is still assembling the
            % full manifest, before Logger.writeJson() is entered.
            details.expected_stats_files = struct('bad', true);
            % The fallback must not re-encode unsafe optional detail values.
            details.warnings = {@sin, 'kept warning'};

            manifestPath = bms.app.ManifestWriter.write(ctx, 'ok', details);

            tc.verifyTrue(endsWith(manifestPath, '_write_failure.json'));
            manifest = jsondecode(fileread(manifestPath));
            tc.verifyEqual(manifest.status, 'failed');
            tc.verifyEqual(manifest.requested_status, 'ok');
            tc.verifyEqual(manifest.manifest_type, 'analysis_run_write_failure');
            tc.verifyEqual(manifest.run_id, 'manifest_build_fallback_unit');
            tc.verifyEqual(manifest.warnings, {'kept warning'});
            tc.verifyEmpty(dir(fullfile(ctx.LogDir, '*.json.tmp')));
        end
    end
end

function cleanup_temp_dir(p)
    if exist(p, 'dir')
        rmdir(p, 's');
    end
end

function cleanup_file(p)
    if exist(p, 'file')
        delete(p);
    end
end
