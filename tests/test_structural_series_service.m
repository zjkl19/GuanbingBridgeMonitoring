classdef test_structural_series_service < matlab.unittest.TestCase
    properties
        Root
    end

    methods (TestMethodSetup)
        function setupCase(tc)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'pipeline'), fullfile(proj, 'analysis'));
            tc.Root = tempname;
            mkdir(fullfile(tc.Root, '2026-01-01', 'features'));
        end
    end

    methods (TestMethodTeardown)
        function cleanupCase(tc)
            if exist(tc.Root, 'dir')
                rmdir(tc.Root, 's');
            end
        end
    end

    methods (Test)
        function basicStatsIgnoreNonFiniteValues(tc)
            row = bms.analyzer.StructuralSeriesService.basicStatsRow( ...
                'P1', [1; NaN; 2.234; Inf], 2);

            tc.verifyEqual(row, {'P1', 1, 2.23, 1.62});
        end

        function filteredStatsUseSharedSevenColumnShape(tc)
            row = bms.analyzer.StructuralSeriesService.filteredStatsRow( ...
                'D1', [1; 3; NaN], [1.2; 2.2; NaN], 1);
            T = bms.analyzer.StructuralSeriesService.filteredStatsTable(row);

            tc.verifyEqual(T.PointID{1}, 'D1');
            tc.verifyEqual(T.OrigMin_mm(1), 1);
            tc.verifyEqual(T.OrigMax_mm(1), 3);
            tc.verifyEqual(T.OrigMean_mm(1), 2);
            tc.verifyEqual(T.FiltMin_mm(1), 1.2);
            tc.verifyEqual(T.FiltMax_mm(1), 2.2);
            tc.verifyEqual(T.FiltMean_mm(1), 1.7);
        end

        function crackStatsTableKeepsAnalyzerColumnNames(tc)
            T = bms.analyzer.StructuralSeriesService.crackStatsTable( ...
                {'C1', 1, 2, 1.5, 20, 22, 21});

            tc.verifyEqual(T.Properties.VariableNames, ...
                {'PointID', 'CrkMin', 'CrkMax', 'CrkMean', 'TmpMin', 'TmpMax', 'TmpMean'});
            tc.verifyEqual(T.CrkMean(1), 1.5);
            tc.verifyEqual(T.TmpMean(1), 21);
        end

        function collectPointsLoadsSeriesAndStats(tc)
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'features', 'S1.csv'), [1; 2; NaN]);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'features', 'S2.csv'), [4; 6; 8]);
            cfg = structural_cfg();

            [dataList, statsRows] = bms.analyzer.StructuralSeriesService.collectPoints( ...
                tc.Root, 'features', {'S1', 'S2'}, '2026-01-01', '2026-01-01', cfg, 'strain', 1, 'Strain point');

            tc.verifyEqual(numel(dataList), 2);
            tc.verifyEqual(dataList(1).pid, 'S1');
            tc.verifyEqual(statsRows(1, :), {'S1', 1, 2, 1.5});
            tc.verifyEqual(statsRows(2, :), {'S2', 4, 8, 6});
        end

        function validSeriesAndComponentStatsHandleGnssShape(tc)
            times = datetime(2026, 1, 1, 0, 0, 0) + minutes(0:3)';
            times(2) = NaT;
            values = [1; 2; NaN; 4];

            [validTimes, validValues] = bms.analyzer.StructuralSeriesService.validSeries(times, values);
            row = bms.analyzer.StructuralSeriesService.componentStatsRow( ...
                'G1', 'X', 'X displacement', validTimes, validValues, 1);
            T = bms.analyzer.StructuralSeriesService.componentStatsTable(row);

            tc.verifyEqual(validValues, [1; 4]);
            tc.verifyEqual(T.PointID{1}, 'G1');
            tc.verifyEqual(T.Component{1}, 'X');
            tc.verifyEqual(T.ValidCount(1), 2);
            tc.verifyEqual(T.Min_mm(1), 1);
            tc.verifyEqual(T.Max_mm(1), 4);
            tc.verifyEqual(T.Mean_mm(1), 2.5);
            tc.verifyEqual(T.PeakToPeak_mm(1), 3);
        end

        function movingMedianWindowUsesTenMinutes(tc)
            times = datetime(2026, 1, 1, 0, 0, 0) + minutes(0:20)';
            values = (1:21)';

            tc.verifyEqual(bms.analyzer.StructuralSeriesService.tenMinuteWindowLength(times), 11);
            filtered = bms.analyzer.StructuralSeriesService.movingMedian10Min(times, values);
            tc.verifySize(filtered, size(values));
            tc.verifyEqual(filtered(11), 11);
        end
    end
end

function cfg = structural_cfg()
    cfg = struct();
    cfg.defaults = struct('header_marker', 'Time');
    cfg.subfolders = struct('strain', 'features');
end

function write_series_csv(path, values)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid > 0, 'Failed to create test csv.');
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'Time,Value\n');
    base = datetime(2026, 1, 1, 0, 0, 0);
    for i = 1:numel(values)
        if isnan(values(i))
            fprintf(fid, '%s,NaN\n', datestr(base + minutes(i - 1), 'yyyy-mm-dd HH:MM:SS.FFF'));
        else
            fprintf(fid, '%s,%.6f\n', datestr(base + minutes(i - 1), 'yyyy-mm-dd HH:MM:SS.FFF'), values(i));
        end
    end
end
