classdef test_dynamic_strain_boxplot_service < matlab.unittest.TestCase
    properties
        Root
        OldFigureVisible
    end

    methods (TestMethodSetup)
        function setupCase(tc)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(projectRoot, ...
                fullfile(projectRoot, 'config'), ...
                fullfile(projectRoot, 'pipeline'), ...
                fullfile(projectRoot, 'analysis'));
            tc.Root = tempname;
            mkdir(tc.Root);
            tc.OldFigureVisible = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
        end
    end

    methods (TestMethodTeardown)
        function cleanupCase(tc)
            close all force;
            set(0, 'DefaultFigureVisible', tc.OldFigureVisible);
            if exist(tc.Root, 'dir')
                rmdir(tc.Root, 's');
            end
        end
    end

    methods (Test)
        function sampleBoxplotMatrixDropsNonFiniteAndCapsRows(tc)
            data = [1 10; NaN 11; 2 Inf; 3 12; 4 13];

            plotMat = bms.analyzer.DynamicStrainBoxplotService.sampleBoxplotMatrix(data, 1000);

            tc.verifyEqual(size(plotMat, 2), 2);
            tc.verifyEqual(plotMat(:, 1), [1; 2; 3; 4]);
            tc.verifyEqual(plotMat(1:4, 2), [10; 11; 12; 13]);
        end

        function sampleBoxplotMatrixPreservesExtremaWhenCapping(tc)
            data = [(1:2000)' (1:2000)'];
            data(2, 1) = -9999;
            data(4, 1) = 9999;
            data(3, 2) = -8888;
            data(5, 2) = 8888;

            plotMat = bms.analyzer.DynamicStrainBoxplotService.sampleBoxplotMatrix(data, 1000);

            tc.verifyLessThanOrEqual(size(plotMat, 1), 1000);
            tc.verifyEqual(min(plotMat(:, 1)), -9999);
            tc.verifyEqual(max(plotMat(:, 1)), 9999);
            tc.verifyEqual(min(plotMat(:, 2)), -8888);
            tc.verifyEqual(max(plotMat(:, 2)), 8888);
        end

        function statsTableMatchesDynamicStrainOutputShape(tc)
            data = [1 10; 2 NaN; 3 14; NaN 18];

            T = bms.analyzer.DynamicStrainBoxplotService.statsTable(data, {'S1', 'S2'});

            tc.verifyEqual(T.Properties.VariableNames, ...
                {'PointID', 'Min', 'Q1', 'Median', 'Q3', 'Max', 'Mean', 'Std', 'Count'});
            tc.verifyEqual(T.PointID{1}, 'S1');
            tc.verifyEqual(T.Min(1), 1);
            tc.verifyEqual(T.Max(1), 3);
            tc.verifyEqual(T.Median(1), 2);
            tc.verifyEqual(T.Count(1), 3);
            tc.verifyEqual(T.PointID{2}, 'S2');
            tc.verifyEqual(T.Min(2), 10);
            tc.verifyEqual(T.Max(2), 18);
            tc.verifyEqual(T.Count(2), 3);
        end

        function estimateSampleRateUsesDatetimeSpacing(tc)
            times = datetime(2026, 1, 1, 0, 0, 0) + seconds(0:0.5:2);

            fs = bms.analyzer.DynamicStrainBoxplotService.estimateSampleRate(times, [], 'test_dynamic_strain:fs');

            tc.verifyEqual(fs, 2, 'AbsTol', 1e-12);
        end

        function resolveLowpassCutoffUsesAutoPeriod(tc)
            cfg = struct('FilterMode', 'auto', 'AutoCutoffPeriodMinutes', 10, 'MinSamplesPerCutoff', 20);

            [fc, periodMinutes] = bms.analyzer.DynamicStrainBoxplotService.resolveLowpassCutoff(cfg, 1);

            tc.verifyEqual(periodMinutes, 10);
            tc.verifyEqual(fc, 1 / 600, 'AbsTol', 1e-12);
        end

        function lowpassBySegmentsKeepsGapAsMissing(tc)
            times = datetime(2026, 1, 1, 0, 0, 0) + seconds(0:19);
            values = sin((0:19)' / 3);
            values(8:10) = NaN;
            cfg = struct('MaxGapSec', 2);

            filtered = bms.analyzer.DynamicStrainBoxplotService.lowpassBySegments(times, values, 1, 0.2, 2, cfg);

            tc.verifyTrue(all(isnan(filtered(8:10))));
            tc.verifyTrue(all(isfinite(filtered([1:7 11:20]))));
        end

        function trimEdgesDropsExpectedSamples(tc)
            times = datetime(2026, 1, 1, 0, 0, 0) + seconds(0:9);
            values = (1:10)';

            [trimmedValues, trimmedTimes] = bms.analyzer.DynamicStrainBoxplotService.trimEdges(values, times, 1, 2);

            tc.verifyEqual(trimmedValues, (3:8)');
            tc.verifyEqual(trimmedTimes(1), times(3));
            tc.verifyEqual(trimmedTimes(end), times(8));
        end

        function pipelineLowpassFallsBackToDynamicStrainGroups(tc)
            cfg.groups.dynamic_strain = struct('G1', {{'S1', 'S2'}});
            cfg.plot_styles.dynamic_strain = struct('ylims', struct('G1', [-1 1]));
            spec = bms.analyzer.DynamicStrainBoxplotPipeline.modeSpec('lowpass');

            [groups, names, style] = bms.analyzer.DynamicStrainBoxplotPipeline.groupsAndStyle(cfg, spec);
            [serviceGroups, serviceNames, serviceStyle] = bms.analyzer.DynamicStrainConfigService.groupsAndStyle(cfg, spec);

            tc.verifyEqual(names, {'G1'});
            tc.verifyEqual(groups{1}, {'S1'; 'S2'});
            tc.verifyEqual(style.ylims.G1, [-1 1]);
            tc.verifyEqual(serviceNames, names);
            tc.verifyEqual(serviceGroups{1}, groups{1});
            tc.verifyEqual(serviceStyle.ylims.G1, style.ylims.G1);
        end

        function pipelineHighpassSpecKeepsModuleKey(tc)
            spec = bms.analyzer.DynamicStrainBoxplotPipeline.modeSpec('highpass');
            serviceSpec = bms.analyzer.DynamicStrainConfigService.modeSpec('highpass');

            tc.verifyEqual(spec.mode, 'highpass');
            tc.verifyEqual(spec.moduleKey, 'dynamic_strain_highpass');
            tc.verifyEqual(spec.timeseriesBase, 'dynstrain_hp');
            tc.verifyEqual(serviceSpec.moduleKey, spec.moduleKey);
        end

        function pipelineDelegatesPathAndYLimHelpers(tc)
            style.ylims.G1 = [-2 2];
            ds = struct('YLimManual', true, 'YLimRange', [-1 1]);

            tc.verifyEqual( ...
                bms.analyzer.DynamicStrainConfigService.groupYLim(style, 'G1', ds), ...
                bms.analyzer.DynamicStrainBoxplotPipeline.groupYLim(style, 'G1', ds));
            tc.verifyEqual( ...
                bms.analyzer.DynamicStrainConfigService.resolveDir('C:\root', 'plots', 'default'), ...
                bms.analyzer.DynamicStrainBoxplotPipeline.resolveDir('C:\root', 'plots', 'default'));
            tc.verifyEqual( ...
                bms.analyzer.DynamicStrainBoxplotPipeline.resolveStatsFile('C:\root', '', 'dynamic_strain_highpass_stats.xlsx'), ...
                fullfile('C:\root', 'stats', 'dynamic_strain_highpass_stats.xlsx'));
            tc.verifyEqual( ...
                bms.analyzer.DynamicStrainBoxplotPipeline.resolveStatsFile('C:\root', 'custom.xlsx', 'default.xlsx'), ...
                fullfile('C:\root', 'stats', 'custom.xlsx'));
            style.output_dir_ts = 'point_ts';
            style.group_output_dir_ts = 'group_ts';
            spec = bms.analyzer.DynamicStrainBoxplotPipeline.modeSpec('highpass');
            singleDir = bms.analyzer.DynamicStrainBoxplotPipeline.resolveTimeseriesSingleDir('C:\root', '', style, spec);
            tc.verifyEqual(singleDir, fullfile('C:\root', 'point_ts'));
            tc.verifyEqual( ...
                bms.analyzer.DynamicStrainBoxplotPipeline.resolveTimeseriesGroupDir('C:\root', singleDir, style), ...
                fullfile('C:\root', 'group_ts'));
            style = rmfield(style, 'group_output_dir_ts');
            tc.verifyEqual( ...
                bms.analyzer.DynamicStrainBoxplotPipeline.resolveTimeseriesGroupDir('C:\root', singleDir, style), ...
                [singleDir, char([95 32452 22270])]);
        end

        function pointTimeseriesWritesSinglePlot(tc)
            ts = struct( ...
                'times', datetime(2026, 1, 1, 0, 0, 0) + minutes(0:3), ...
                'vals', [0; 1; -1; 0.5]);
            spec = bms.analyzer.DynamicStrainBoxplotPipeline.modeSpec('highpass');
            ds = spec.defaults;

            bms.analyzer.DynamicStrainPlotService.plotPointTimeseries( ...
                ts, 'S1', tc.Root, datetime(2026, 1, 1), datetime(2026, 1, 1), ...
                ds, spec, [], '20260101-20260101', 'test', struct());

            tc.verifyGreaterThanOrEqual(numel(dir(fullfile(tc.Root, 'dynstrain_hp_S1_20260101-20260101_test.fig'))), 1);
        end

        function boxplotStatsAreWrittenToCanonicalStatsFile(tc)
            imageDir = fullfile(tc.Root, 'boxplots');
            statsFile = fullfile(tc.Root, 'stats', 'dynamic_strain_highpass_stats.xlsx');
            spec = bms.analyzer.DynamicStrainBoxplotPipeline.modeSpec('highpass');
            ds = spec.defaults;

            bms.analyzer.DynamicStrainPlotService.makeBoxplotAndStats( ...
                [1 10; 2 11; 3 12], {'S1', 'S2'}, 'G1', imageDir, statsFile, ...
                ds, spec, '20260101-20260101', 'test', datetime(2026, 1, 1), datetime(2026, 1, 1), struct());

            tc.verifyTrue(isfile(statsFile));
            tc.verifyEmpty(dir(fullfile(imageDir, 'boxplot_stats_*.xlsx')));
            tc.verifyGreaterThanOrEqual(numel(dir(fullfile(imageDir, 'boxplot_G1_20260101-20260101_test.fig'))), 1);

            T = readtable(statsFile, 'Sheet', 'G1', 'VariableNamingRule', 'preserve');
            tc.verifyEqual(T.PointID, {'S1'; 'S2'});
            tc.verifyTrue(isfile(fullfile(tc.Root, 'stats', 'dynamic_strain_highpass_G1_20260101-20260101.txt')));
        end
    end
end
