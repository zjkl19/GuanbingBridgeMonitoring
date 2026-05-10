classdef test_vibration_mode_service < matlab.unittest.TestCase
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
        function largeFileWrapperReturnsNormalizedModeShape(tc)
            fs = 50;
            frequency = 2.0;
            amps = [1, 2, 4];
            files = cell(1, numel(amps));
            for i = 1:numel(amps)
                files{i} = fullfile(tc.Root, sprintf('P%d.csv', i));
                write_sine_csv(files{i}, fs, frequency, amps(i));
            end

            modeShape = analyze_vibration_mode_large_files(files, ...
                '2026-01-01 00:00:01.000', '2026-01-01 00:00:18.000', frequency, fs);

            tc.verifyEqual(modeShape(:), [0.25; 0.5; 1.0], 'AbsTol', 0.08);
        end

        function invalidFilterBandIsRejected(tc)
            tc.verifyError(@() bms.analyzer.VibrationModeService.bandpassCoefficients(0.05, 20, struct()), ...
                'VibrationModeService:InvalidFilterBand');
        end
    end
end

function write_sine_csv(path, fs, frequency, amplitude)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid > 0, 'Failed to create test CSV.');
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'Time,Value\n');
    base = datetime(2026, 1, 1);
    n = 20 * fs;
    t = (0:n-1)' / fs;
    values = amplitude * sin(2 * pi * frequency * t);
    for i = 1:n
        fprintf(fid, '%s,%.10f\n', datestr(base + seconds(t(i)), 'yyyy-mm-dd HH:MM:SS.FFF'), values(i));
    end
end
