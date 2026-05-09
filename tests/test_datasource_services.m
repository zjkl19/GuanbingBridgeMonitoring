classdef test_datasource_services < matlab.unittest.TestCase
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
        function defaultSourceFindsDatedCsv(tc)
            dayDir = fullfile(tc.TempDir, '2026-03-01', 'wave');
            mkdir(dayDir);
            p = fullfile(dayDir, 'P1.csv');
            fclose(fopen(p, 'w'));

            src = bms.data.DefaultCsvDataSource(tc.TempDir, struct());
            files = src.findPointFiles('P1', 'wave', '2026-03-01', '2026-03-01', {'*P1*.csv'});

            tc.verifyEqual(numel(files), 1);
            tc.verifyEqual(files{1}, char(java.io.File(p).getCanonicalPath()));
        end

        function jiulongjiangSourceUsesCsvExportFolder(tc)
            csvDir = fullfile(tc.TempDir, 'data_jlj_2026-03-23', 'data', 'jlj', 'csv');
            mkdir(csvDir);
            p = fullfile(csvDir, 'GNSS-01.csv');
            fclose(fopen(p, 'w'));

            src = bms.data.DataSourceFactory.create(tc.TempDir, struct());
            tc.verifyClass(src, 'bms.data.JiulongjiangCsvDataSource');
            files = src.findPointFiles('GNSS-01', '', '2026-03-23', '2026-03-23', {'*GNSS-01*.csv'});

            tc.verifyEqual(numel(files), 1);
            tc.verifyEqual(files{1}, char(java.io.File(p).getCanonicalPath()));
        end

        function wimSourceFindsMonthlyPairs(tc)
            mkdir(fullfile(tc.TempDir, 'WIM'));
            fclose(fopen(fullfile(tc.TempDir, 'WIM', 'HS_Data_202601.fmt'), 'w'));
            fclose(fopen(fullfile(tc.TempDir, 'WIM', 'HS_Data_202601.bcp'), 'w'));

            src = bms.data.DataSourceFactory.wim(tc.TempDir, struct());
            files = src.monthFiles('2026-01-01', '2026-01-31');

            tc.verifyEqual(numel(files), 1);
            tc.verifyEqual(files(1).month, '202601');
            tc.verifyTrue(files(1).exists);
        end

        function closedRangeIncludesWholeEndDate(tc)
            times = datetime({'2026-03-01 00:00:00','2026-03-02 23:59:59','2026-03-03 00:00:00'}, ...
                'InputFormat', 'yyyy-MM-dd HH:mm:ss');
            mask = bms.data.TimeRangeResolver.contains(times, '2026-03-01', '2026-03-02');
            tc.verifyEqual(mask, [true true false]);
        end

        function cacheMetadataChecksSourceRecords(tc)
            src = fullfile(tc.TempDir, 'source.csv');
            cache = fullfile(tc.TempDir, 'cache.mat');
            fclose(fopen(src, 'w'));
            fclose(fopen(cache, 'w'));

            cfg = struct('a', 1);
            bms.data.CacheManager.writeMetadata(cache, {src}, cfg, 'v1');

            tc.verifyTrue(bms.data.CacheManager.metadataMatchesFull(cache, {src}, cfg, 'v1'));
            tc.verifyFalse(bms.data.CacheManager.metadataMatchesFull(cache, {src}, cfg, 'v2'));
        end

        function dataIndexBuildsPointFileMap(tc)
            dayDir = fullfile(tc.TempDir, '2026-03-01', 'temperature');
            mkdir(dayDir);
            src = fullfile(dayDir, 'PT-1.csv');
            fclose(fopen(src, 'w'));

            cfg = struct();
            cfg.defaults = struct();
            cfg.subfolders = struct('temperature', 'temperature');
            cfg.file_patterns = struct();
            cfg.points = struct('temperature', {{'PT-1', 'PT-2'}});
            cfg.plot_styles = struct();
            opts = struct('doTemp', true, 'buildDataIndex', true);

            index = bms.data.DataIndex.build(tc.TempDir, '2026-03-01', '2026-03-01', cfg, opts);
            tc.verifyEqual(index.summary.point_count, 2);
            tc.verifyEqual(index.summary.found_point_count, 1);
            tc.verifyEqual(index.summary.missing_point_count, 1);
            tc.verifyEqual(index.modules{1}.points{1}.status, 'found');

            out = bms.data.DataIndex.write(tc.TempDir, index, 'unit');
            tc.verifyTrue(isfile(out));
            payload = jsondecode(fileread(out));
            tc.verifyEqual(payload.summary.file_count, 1);

            loaded = bms.data.DataIndex.load(out);
            moduleRows = bms.data.DataIndex.moduleRows(loaded);
            pointRows = bms.data.DataIndex.pointRows(loaded);
            tc.verifyEqual(height(moduleRows), 1);
            tc.verifyEqual(height(pointRows), 2);
            tc.verifyEqual(pointRows.status{1}, 'found');

            summaryXlsx = bms.data.DataIndex.writeSummary(tc.TempDir, index, 'unit');
            tc.verifyTrue(isfile(summaryXlsx));
        end
    end
end
