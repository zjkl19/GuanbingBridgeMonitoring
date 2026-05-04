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
            [tf, value] = bms.config.ConfigPatch.getPath(cfg, 'plot_common.gap_mode');
            tc.verifyTrue(tf);
            tc.verifyEqual(value, 'connect');
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
            days = bms.data.TimeRangeResolver.daysBetween('2026-01-01', '2026-01-03');
            tc.verifyEqual(numel(days), 3);
            months = bms.data.TimeRangeResolver.monthKeys('2026-01-15', '2026-03-01');
            tc.verifyEqual(months, {'202601','202602','202603'});
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

        function manifestWriterAddsSchemaAndMissingStats(tc)
            tmp = tempname;
            mkdir(tmp);
            cleanup = onCleanup(@() rmdir(tmp, 's'));
            ctx = bms.core.AnalysisContext(tmp, '2026-01-01', '2026-01-01', struct(), struct(), 'RunId', 'manifest_unit');
            details = struct('expected_stats_files', {{fullfile(tmp, 'stats', 'missing.xlsx')}}, 'module_logs', {{}}, 'stats_files', {{}});
            manifestPath = bms.app.ManifestWriter.write(ctx, 'ok', details);
            tc.verifyTrue(isfile(manifestPath));
            manifest = jsondecode(fileread(manifestPath));
            tc.verifyEqual(manifest.schema_version, 1);
            tc.verifyEqual(manifest.manifest_type, 'analysis_run');
            tc.verifyEqual(numel(manifest.missing_expected_stats), 1);
            clear cleanup;
        end
    end
end
