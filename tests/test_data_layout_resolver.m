classdef test_data_layout_resolver < matlab.unittest.TestCase
    properties
        TempDir
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj);
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if exist(tc.TempDir, 'dir'), rmdir(tc.TempDir, 's'); end
        end
    end

    methods (Test)
        function identifiesJiulongjiangDailyExport(tc)
            mkdir(fullfile(tc.TempDir, 'data_jlj_2026-03-23', 'data', 'jlj', 'csv'));
            layout = bms.data.DataLayoutResolver.inferLayout(tc.TempDir, struct());
            tc.verifyEqual(layout, 'jlj_daily_export');
            dirs = bms.data.DataLayoutResolver.jljCsvDirs(tc.TempDir, '2026-03-23', '2026-03-24');
            tc.verifyEqual(numel(dirs), 1);
            tc.verifyTrue(endsWith(dirs{1}, fullfile('data', 'jlj', 'csv')));
        end

        function vendorSelectsJiulongjiangLayoutBeforeExtraction(tc)
            layout = bms.data.DataLayoutResolver.inferLayout( ...
                tc.TempDir, struct('vendor', 'jiulongjiang'));
            tc.verifyEqual(layout, 'jlj_daily_export');
        end

        function resolvesHongtangWimMonths(tc)
            mkdir(fullfile(tc.TempDir, 'WIM'));
            fclose(fopen(fullfile(tc.TempDir, 'WIM', 'HS_Data_202601.fmt'), 'w'));
            fclose(fopen(fullfile(tc.TempDir, 'WIM', 'HS_Data_202601.bcp'), 'w'));
            files = bms.data.DataLayoutResolver.wimMonthFiles(tc.TempDir, '2026-01-01', '2026-02-01');
            tc.verifyEqual(numel(files), 2);
            tc.verifyTrue(files(1).exists);
            tc.verifyFalse(files(2).exists);
        end

        function pointTokenDoesNotMatchPrefixCollision(tc)
            files = {'CS1_202601.jpg', 'CS12_202601.jpg', 'abc_CS1_def.jpg'};
            matches = bms.data.PointResolver.filterFilesForPoint(files, 'CS1');
            tc.verifyEqual(matches, {'CS1_202601.jpg', 'abc_CS1_def.jpg'});
            tc.verifyFalse(bms.data.PointResolver.filenameHasPointToken('CS12_202601.jpg', 'CS1'));
        end

        function timeRangeParsesSeveralFormats(tc)
            tc.verifyEqual(bms.data.TimeRangeResolver.toDateString('2026/03/05'), '2026-03-05');
            tc.verifyEqual(bms.data.TimeRangeResolver.monthKeys('2026.01.15', '2026-03-16'), {'202601','202602','202603'});
        end
    end
end
