classdef test_precheck_zip_count < matlab.unittest.TestCase
    properties
        TempRoot
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TempRoot = tempname;
            mkdir(tc.TempRoot);
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'scripts'), '-begin');
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if exist(tc.TempRoot, 'dir')
                rmdir(tc.TempRoot, 's');
            end
        end
    end

    methods (Test)
        function nestedDonghuaZipPerKindPasses(tc)
            day = '2026-05-26';
            tc.createZip(fullfile(tc.TempRoot, day, tc.waveName(), '8482acee-ad71-49b6-81bc-b357f011a146', 'wave.zip'));
            tc.createZip(fullfile(tc.TempRoot, day, tc.featureName(), 'd579dd0e-663d-4174-8aef-fd5fa4647de5', 'feature.zip'));

            tc.verifyWarningFree(@() precheck_zip_count(tc.TempRoot, day, day));
        end

        function directZipPerKindStillPasses(tc)
            day = '2026-05-27';
            tc.createZip(fullfile(tc.TempRoot, day, tc.waveName(), 'wave.zip'));
            tc.createZip(fullfile(tc.TempRoot, day, tc.featureName(), 'feature.zip'));

            tc.verifyWarningFree(@() precheck_zip_count(tc.TempRoot, day, day));
        end

        function missingZipStillFails(tc)
            day = '2026-05-28';
            tc.createZip(fullfile(tc.TempRoot, day, tc.waveName(), 'wave.zip'));

            didThrow = false;
            try
                precheck_zip_count(tc.TempRoot, day, day);
            catch
                didThrow = true;
            end
            tc.verifyTrue(didThrow);
        end

        function rootDailyZipIsActuallyChecked(tc)
            day = '2026-05-29';
            tc.createZip(fullfile(tc.TempRoot, ['data_jlj_' day '.zip']));
            cfg = struct('vendor', 'jiulongjiang');
            result = precheck_zip_count(tc.TempRoot, day, day, cfg);
            tc.verifyEqual(result.archive_count, 1);
            tc.verifyEqual(result.layout, 'daily_export');
        end

        function rootDailyZipMissingDateFails(tc)
            tc.createZip(fullfile(tc.TempRoot, 'data_jlj_2026-05-30.zip'));
            cfg = struct('vendor', 'jiulongjiang');
            tc.verifyError(@() precheck_zip_count( ...
                tc.TempRoot, '2026-05-30', '2026-05-31', cfg), ...
                'BMS:ArchiveExtract:DailyArchiveCount');
        end

        function donghuaMissingWholeDateFails(tc)
            day = '2026-06-01';
            tc.createZip(fullfile(tc.TempRoot, day, tc.waveName(), 'wave.zip'));
            tc.createZip(fullfile(tc.TempRoot, day, tc.featureName(), 'feature.zip'));
            tc.verifyError(@() precheck_zip_count( ...
                tc.TempRoot, day, '2026-06-02'), ...
                'BMS:ArchiveExtract:DonghuaArchiveCount');
        end
    end

    methods (Access = private)
        function name = waveName(~)
            name = char([0x6CE2 0x5F62]);
        end

        function name = featureName(~)
            name = char([0x7279 0x5F81 0x503C]);
        end

        function createZip(~, path)
            parent = fileparts(path);
            if exist(parent, 'dir') ~= 7
                mkdir(parent);
            end
            fid = fopen(path, 'w');
            assert(fid > 0);
            cleaner = onCleanup(@() fclose(fid));
            fwrite(fid, uint8([80 75 5 6 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0]));
            delete(cleaner);
        end
    end
end
