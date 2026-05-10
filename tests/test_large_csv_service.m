classdef test_large_csv_service < matlab.unittest.TestCase
    properties
        Root
    end

    methods (TestMethodSetup)
        function setupCase(tc)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(projectRoot, fullfile(projectRoot, 'scripts'), fullfile(projectRoot, 'analysis'));
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
        function extractTimeRangeKeepsSelectedRows(tc)
            path = fullfile(tc.Root, 'series.csv');
            write_time_value_csv(path, [1; 2; 3; 4]);

            values = extract_time_range_data(path, ...
                '2026-01-01 00:00:01.000', '2026-01-01 00:00:02.000');

            tc.verifyEqual(values, [2; 3]);
        end

        function dateRangeWorksForSmallFiles(tc)
            path = fullfile(tc.Root, 'small.csv');
            write_time_value_csv(path, [10; 20]);

            [startDate, endDate] = get_start_and_end_date_large_file(path);

            tc.verifyEqual(startDate, '2026-01-01 00:00:00.000');
            tc.verifyEqual(endDate, '2026-01-01 00:00:01.000');
        end

        function readWithHeaderStartsAtMarkerLine(tc)
            path = fullfile(tc.Root, 'header.csv');
            fid = fopen(path, 'w', 'n', 'UTF-8');
            assert(fid > 0, 'Failed to create test CSV.');
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, 'junk\n');
            fprintf(fid, 'Time,Value\n');
            fprintf(fid, '2026-01-01 00:00:00.000,1\n');
            fprintf(fid, '2026-01-01 00:00:01.000,2\n');

            data = bms.data.LargeCsvService.readWithHeader(path, 'Time');

            tc.verifyEqual(height(data), 2);
            tc.verifyEqual(data.Value, [1; 2]);
        end

        function readWrapperFindsDefaultAbsoluteTimeMarker(tc)
            path = fullfile(tc.Root, 'absolute_time_header.csv');
            fid = fopen(path, 'w', 'n', 'UTF-8');
            assert(fid > 0, 'Failed to create test CSV.');
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, 'junk\n');
            fprintf(fid, '[绝对时间],Value\n');
            fprintf(fid, '2026-01-01 00:00:00.000,3\n');
            fprintf(fid, '2026-01-01 00:00:01.000,4\n');

            data = read_csv_with_header(path);

            tc.verifyEqual(height(data), 2);
            tc.verifyEqual(data.Value, [3; 4]);
        end
    end
end

function write_time_value_csv(path, values)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid > 0, 'Failed to create test CSV.');
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'Time,Value\n');
    base = datetime(2026, 1, 1);
    for i = 1:numel(values)
        fprintf(fid, '%s,%.6f\n', datestr(base + seconds(i - 1), 'yyyy-mm-dd HH:MM:SS.FFF'), values(i));
    end
end
