classdef test_cache_and_artifacts < matlab.unittest.TestCase
    properties
        TempDir
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'config'), fullfile(proj, 'pipeline'), fullfile(proj, 'analysis'));
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if exist(tc.TempDir, 'dir'), rmdir(tc.TempDir, 's'); end
        end
    end

    methods (Test)
        function cacheMetadataControlsFreshness(tc)
            src = fullfile(tc.TempDir, 'source.csv');
            cacheDir = bms.data.CacheManager.cacheDir(tc.TempDir);
            mkdir(cacheDir);
            cacheFile = fullfile(cacheDir, 'data.mat');
            fclose(fopen(src, 'w'));
            save(cacheFile, 'src');

            cfg = struct('a', 1);
            bms.data.CacheManager.writeMetadata(cacheFile, {src}, cfg, 'v1');

            tc.verifyTrue(bms.data.CacheManager.isFresh(cacheFile, {src}, cfg, 'v1'));
            tc.verifyFalse(bms.data.CacheManager.isFresh(cacheFile, {src}, struct('a', 2), 'v1'));
            tc.verifyFalse(bms.data.CacheManager.isFresh(cacheFile, {src}, cfg, 'v2'));
        end

        function cacheInvalidateDeletesOnlyCachePattern(tc)
            cacheDir = bms.data.CacheManager.cacheDir(tc.TempDir);
            mkdir(cacheDir);
            a = fullfile(cacheDir, 'a.mat');
            b = fullfile(cacheDir, 'b.txt');
            fclose(fopen(a, 'w'));
            fclose(fopen(b, 'w'));

            removed = bms.data.CacheManager.invalidate(tc.TempDir, '*.mat');

            tc.verifyEqual(numel(removed), 1);
            tc.verifyFalse(isfile(a));
            tc.verifyTrue(isfile(b));
        end

        function artifactCleanerDryRunAndDeleteAreSafe(tc)
            imgDir = fullfile(tc.TempDir, 'figs');
            mkdir(imgDir);
            img = fullfile(imgDir, 'a.jpg');
            txt = fullfile(imgDir, 'keep.txt');
            fclose(fopen(img, 'w'));
            fclose(fopen(txt, 'w'));

            files = bms.data.ArtifactCleaner.list(tc.TempDir, 'images', true);
            tc.verifyEqual(files, {img});
            dry = bms.data.ArtifactCleaner.deleteFiles(tc.TempDir, files, true);
            tc.verifyTrue(isfile(img));
            tc.verifyEqual(numel(dry.deleted), 1);

            done = bms.data.ArtifactCleaner.deleteFiles(tc.TempDir, files, false);
            tc.verifyFalse(isfile(img));
            tc.verifyTrue(isfile(txt));
            tc.verifyEqual(numel(done.deleted), 1);
        end
    end
end
