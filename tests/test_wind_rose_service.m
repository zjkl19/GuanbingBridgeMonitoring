classdef test_wind_rose_service < matlab.unittest.TestCase
    properties
        Root
    end

    methods (TestMethodSetup)
        function setupCase(tc)
            tc.Root = tempname;
            mkdir(tc.Root);
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
        function alignForRoseInterpolatesDirectionToSpeedTimes(tc)
            tSpeed = datetime(2026, 1, 1, 0, 0, 0) + minutes(0:2)';
            vSpeed = [1; 2; NaN];
            tDir = datetime(2026, 1, 1, 0, 0, 0) + minutes([0; 2]);
            vDir = [350; 10];

            [speedAligned, dirAligned] = bms.analyzer.WindRoseService.alignForRose(tSpeed, vSpeed, tDir, vDir);

            tc.verifyEqual(speedAligned, [1; 2]);
            tc.verifyEqual(dirAligned, [350; 10]);
        end

        function buildMatrixNormalizesCountsAndLabelsSpeedBins(tc)
            params = struct('sector_deg', 90, 'speed_bins', [0 2 4]);
            directions = [10; 80; 100; 190; 350];
            speeds = [1; 3; 3; 5; 1];

            [mat, sectorEdges, speedEdges, totalCount] = bms.analyzer.WindRoseService.buildMatrix(directions, speeds, params);
            labels = bms.analyzer.WindRoseService.speedBinLabels(speedEdges);

            tc.verifyEqual(totalCount, 5);
            tc.verifyEqual(sectorEdges, [0 90 180 270 360]);
            tc.verifyEqual(speedEdges, [0 2 4 inf]);
            tc.verifyEqual(sum(mat, 'all'), 1, 'AbsTol', 1e-12);
            tc.verifyEqual(labels, {'0-2 m/s', '2-4 m/s', '>=4 m/s'});
        end

        function summarizeAndWriteSummaryReport(tc)
            params = struct('sector_deg', 90, 'speed_bins', [0 2 4]);
            directions = [10; 80; 100; 190; 350];
            speeds = [1; 3; 3; 5; 1];
            [mat, sectorEdges, speedEdges, totalCount] = bms.analyzer.WindRoseService.buildMatrix(directions, speeds, params);

            summary = bms.analyzer.WindRoseService.summarize('W1', directions, speeds, sectorEdges, speedEdges, mat, totalCount);
            bms.analyzer.WindRoseService.writeSummary(tc.Root, 'windrose_W1', 'W1', directions, speeds, sectorEdges, speedEdges, mat, totalCount);

            tc.verifyEqual(summary.total_count, 5);
            tc.verifyEqual(summary.dominant_direction, '0.0°-90.0°');
            tc.verifyEqual(summary.main_speed_bin, '0-2 m/s');
            tc.verifyTrue(isfile(fullfile(tc.Root, 'windrose_W1_summary.txt')));
        end
    end
end
