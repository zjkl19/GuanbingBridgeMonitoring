classdef test_artifact_manifest_v2 < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'pipeline'));
        end
    end

    methods (Test)
        function collectorFindsRecentModuleFiles(tc)
            root = tempname;
            mkdir(root);
            out = fullfile(root, '时程曲线_挠度_原始');
            mkdir(out);
            figPath = fullfile(out, 'Defl_A_Orig.jpg');
            fid = fopen(figPath, 'w'); fwrite(fid, 'x'); fclose(fid);
            statsPath = fullfile(root, 'stats', 'deflection_stats.xlsx');
            mkdir(fileparts(statsPath));
            writetable(table("A", 1, 'VariableNames', {'PointID','Value'}), statsPath);

            artifacts = bms.data.ArtifactCollector.collectModule(root, 'deflection', statsPath, datetime('now') - minutes(1), struct());
            paths = cellfun(@(s) string(s.path), artifacts, 'UniformOutput', true);
            tc.verifyTrue(any(paths == string(statsPath)));
            tc.verifyTrue(any(paths == string(figPath)));
            figIdx = find(paths == string(figPath), 1);
            tc.verifyEqual(artifacts{figIdx}.role, 'raw');
            statsIdx = find(paths == string(statsPath), 1);
            tc.verifyEqual(artifacts{statsIdx}.role, 'stats');
        end

        function manifestBuildsV2ArtifactSummary(tc)
            ctx = bms.core.AnalysisContext(tempdir, '2026-01-01', '2026-01-02', struct(), struct());
            artifact = struct('kind', 'stats', 'path', 'D:/x/stats.xlsx', 'exists', true, 'bytes', 1, 'modified_at', '2026-01-01 00:00:00');
            details = struct();
            details.module_logs = {struct('key', 'deflection', 'label', 'deflection', 'status', 'ok', 'artifacts', {{artifact}})};
            manifest = bms.app.ManifestWriter.build(ctx, 'ok', details);
            tc.verifyEqual(manifest.schema_version, 2);
            tc.verifyEqual(manifest.artifact_count, 1);
            tc.verifyEqual(manifest.module_status_counts.ok, 1);
        end
    end
end
