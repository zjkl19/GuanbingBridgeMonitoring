classdef test_donghua_export_normalizer < matlab.unittest.TestCase
    properties
        TempRoot
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TempRoot = tempname;
            mkdir(tc.TempRoot);
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'config'), fullfile(proj, 'pipeline'), ...
                fullfile(proj, 'analysis'), fullfile(proj, 'scripts'), '-begin');
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
        function nestedDonghuaCsvIsCopiedToDirectFolder(tc)
            folder = fullfile(tc.TempRoot, '2026-05-26', '波形');
            nested = fullfile(folder, '8482acee-ad71-49b6-81bc-b357f011a146');
            mkdir(nested);
            name = 'G05基准点1X_原始数据_20260526.csv';
            canonicalName = 'G05基准点1X.csv';
            tc.writeFile(fullfile(nested, name));

            dry = bms.data.DonghuaExportNormalizer.normalizeFolder(folder, 'DryRun', true);
            tc.verifyEqual(dry.source_count, 1);
            tc.verifyEqual(dry.would_copy, 1);

            summary = bms.data.DonghuaExportNormalizer.normalizeFolder(folder);

            tc.verifyEqual(summary.copied, 1);
            tc.verifyTrue(isfile(fullfile(folder, canonicalName)));
            tc.verifyFalse(isfile(fullfile(folder, name)));
            tc.verifyTrue(isfile(fullfile(nested, name)));
        end

        function canonicalExistingFilePreventsRepeatedCopy(tc)
            folder = fullfile(tc.TempRoot, '2026-05-27', '特征值');
            nested = fullfile(folder, '62fcbff5-4992-4044-ac62-9f0684c55fb1');
            mkdir(nested);
            rawName = 'G05基准点1X_原始数据_20260527.csv';
            tc.writeFile(fullfile(nested, rawName));
            tc.writeFile(fullfile(folder, 'G05基准点1X.csv'));

            summary = bms.data.DonghuaExportNormalizer.normalizeFolder(folder);

            tc.verifyEqual(summary.copied, 0);
            tc.verifyEqual(summary.skipped_existing, 1);
            tc.verifyFalse(isfile(fullfile(folder, rawName)));
        end

        function directRawDonghuaNameIsCanonicalized(tc)
            folder = fullfile(tc.TempRoot, '2026-05-27', '波形');
            mkdir(folder);
            rawName = 'GB-DIS-P04-001-01-X_原始数据_1001972_20260527.csv';
            canonicalName = 'GB-DIS-P04-001-01-X.csv';
            tc.writeFile(fullfile(folder, rawName));

            dry = bms.data.DonghuaExportNormalizer.normalizeFolder(folder, 'DryRun', true);
            tc.verifyEqual(dry.would_rename, 1);

            summary = bms.data.DonghuaExportNormalizer.normalizeFolder(folder);

            tc.verifyEqual(summary.renamed, 1);
            tc.verifyTrue(isfile(fullfile(folder, canonicalName)));
            tc.verifyFalse(isfile(fullfile(folder, rawName)));
        end

        function mojibakeRawDonghuaNameIsCanonicalized(tc)
            rawName = 'GB-DIS-P04-001-01-X_鍘熷鏁版嵁_1001972_20260527.csv';
            tc.verifyEqual( ...
                bms.data.DonghuaExportNormalizer.canonicalFileName(rawName), ...
                'GB-DIS-P04-001-01-X.csv');
        end

        function batchRenameCsvStagesNestedDonghuaFiles(tc)
            folder = fullfile(tc.TempRoot, '2026-05-28', '波形');
            nested = fullfile(folder, '49183336-3f80-44df-aef4-df5a10aac43f');
            mkdir(nested);
            tc.writeFile(fullfile(nested, 'G05基准点1X_原始数据_20260528.csv'));

            batch_rename_csv(tc.TempRoot, '2026-05-28', '2026-05-28', true);

            tc.verifyTrue(isfile(fullfile(folder, 'G05基准点1X.csv')));
            tc.verifyTrue(isfile(fullfile(nested, 'G05基准点1X_原始数据_20260528.csv')));
        end
    end

    methods (Access = private)
        function writeFile(~, path)
            fid = fopen(path, 'w');
            assert(fid > 0);
            cleaner = onCleanup(@() fclose(fid));
            fprintf(fid, 'time,value\n2026-05-26 00:00:00.000,1\n');
            delete(cleaner);
        end
    end
end
