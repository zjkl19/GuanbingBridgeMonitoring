classdef test_manifest_reader < matlab.unittest.TestCase
    properties
        TempDir
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.TempDir = tempname;
            mkdir(fullfile(tc.TempDir, 'run_logs'));
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
        function readsLatestManifestAndMissingModules(tc)
            oldPath = fullfile(tc.TempDir, 'run_logs', 'analysis_manifest_20260101_010101.json');
            newPath = fullfile(tc.TempDir, 'run_logs', 'analysis_manifest_20260101_020202.json');
            bms.core.Logger.writeJson(oldPath, struct('status', 'ok'));
            pause(0.05);
            manifest = struct();
            manifest.status = 'failed';
            manifest.schema_version = 1;
            manifest.bridge_profile = struct('bridge_id', 'unit');
            manifest.module_results = {struct('key', 'strain', 'label', 'strain', 'status', 'fail', 'message', 'bad')};
            bms.core.Logger.writeJson(newPath, manifest);

            latest = bms.app.ManifestReader.latest(tc.TempDir);
            ctx = bms.app.ManifestReader.context(tc.TempDir);
            lines = bms.app.ManifestReader.summaryLines(ctx);

            tc.verifyEqual(latest, newPath);
            tc.verifyTrue(ctx.available);
            tc.verifyEqual(ctx.status, 'failed');
            tc.verifyEqual(numel(ctx.missing_modules), 1);
            tc.verifyTrue(any(contains(lines, 'missing_modules=1')));
        end

        function normalizesStructArraysAndColumnCells(tc)
            manifest = struct();
            manifest.module_preflight = {struct('key','temp','status','ok')};
            manifest.module_results = [ ...
                struct('key','temperature','label','温度分析','status','ok','message',''), ...
                struct('key','humidity','label','湿度分析','status','fail','message','bad') ...
            ]';

            records = bms.app.ManifestReader.recordsToCell(manifest.module_results);
            missing = bms.app.ManifestReader.missingModules(manifest);

            tc.verifySize(records, [1 2]);
            tc.verifyEqual(numel(missing), 1);
            tc.verifyEqual(missing{1}.key, 'humidity');
        end
    end
end
