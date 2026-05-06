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

        function manifestWriterAddsSchemaAndMissingStats(tc)
            tmp = tempname;
            mkdir(tmp);
            cleanup = onCleanup(@() rmdir(tmp, 's'));
            ctx = bms.core.AnalysisContext(tmp, '2026-01-01', '2026-01-01', struct(), struct(), 'RunId', 'manifest_unit');
            details = struct('expected_stats_files', {{fullfile(tmp, 'stats', 'missing.xlsx')}}, 'module_logs', {{}}, 'stats_files', {{}});
            manifestPath = bms.app.ManifestWriter.write(ctx, 'ok', details);
            tc.verifyTrue(isfile(manifestPath));
            manifest = jsondecode(fileread(manifestPath));
            tc.verifyEqual(manifest.schema_version, 2);
            tc.verifyEqual(manifest.manifest_type, 'analysis_run');
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
