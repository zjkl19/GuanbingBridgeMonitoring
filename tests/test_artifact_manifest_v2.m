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

        function manifestBuildsCurrentArtifactSummary(tc)
            ctx = bms.core.AnalysisContext(tempdir, '2026-01-01', '2026-01-02', struct(), struct());
            artifact = struct('kind', 'stats', 'path', 'D:/x/stats.xlsx', 'exists', true, 'bytes', 1, 'modified_at', '2026-01-01 00:00:00');
            details = struct();
            details.module_logs = {struct('key', 'deflection', 'label', 'deflection', 'status', 'ok', 'artifacts', {{artifact}})};
            manifest = bms.app.ManifestWriter.build(ctx, 'ok', details);
            tc.verifyEqual(manifest.schema_version, bms.app.ManifestWriter.SchemaVersion);
            tc.verifyEqual(manifest.artifact_count, 1);
            tc.verifyEqual(manifest.module_status_counts.ok, 1);
        end

        function collectorFindsCableForceSingleAndGroupFigures(tc)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() rmdir(root, 's'));
            singleDir = fullfile(root, '索力时程图');
            groupDir = fullfile(root, '索力时程图_组图');
            mkdir(singleDir);
            mkdir(groupDir);
            singlePath = fullfile(singleDir, 'CableForce_CS4_20260401_20260630.jpg');
            groupPath = fullfile(groupDir, 'CableForce_CS4-CX4_20260401_20260630.jpg');
            fid = fopen(singlePath, 'w'); fwrite(fid, 'single'); fclose(fid);
            fid = fopen(groupPath, 'w'); fwrite(fid, 'group'); fclose(fid);

            artifacts = bms.data.ArtifactCollector.collectModule( ...
                root, 'cable_accel_spectrum', '', datetime('now') - minutes(1), struct());
            paths = cellfun(@(s) string(s.path), artifacts, 'UniformOutput', true);
            tc.verifyTrue(any(paths == string(singlePath)));
            tc.verifyTrue(any(paths == string(groupPath)));
            clear cleanup;
        end

        function collectorIncludesWindRoseSummaryForStrictReports(tc)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() rmdir(root, 's'));
            windRoot = fullfile(root, 'wind_out');
            roseDir = fullfile(windRoot, 'rose');
            mkdir(roseDir);
            summaryPath = fullfile(roseDir, 'W1_windrose_2026-04-01_2026-06-30_summary.txt');
            fid = fopen(summaryPath, 'w');
            fwrite(fid, unicode2native('平均风向: 198.3°', 'UTF-8'), 'uint8');
            fclose(fid);

            cfg = struct();
            cfg.plot_styles.wind.output.root_dir = windRoot;
            artifacts = bms.data.ArtifactCollector.collectModule( ...
                root, 'wind', '', datetime('now') - minutes(1), cfg);
            paths = cellfun(@(s) string(s.path), artifacts, 'UniformOutput', true);
            idx = find(paths == string(summaryPath), 1);

            tc.verifyNotEmpty(idx);
            tc.verifyEqual(artifacts{idx}.kind, 'summary');
            tc.verifyEqual(artifacts{idx}.role, 'wind_rose');
            clear cleanup;
        end

        function collectorIncludesReportCriticalGuanbingDirectories(tc)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() rmdir(root, 's'));

            humidityDir = fullfile(root, '频次分布_湿度');
            tiltDir = fullfile(root, '时程曲线_倾角_组图');
            lowpassDir = fullfile(root, '时程曲线_动应变_低通滤波_组图');
            mkdir(humidityDir);
            mkdir(tiltDir);
            mkdir(lowpassDir);
            humidityPath = fullfile(humidityDir, 'GB-RHS-G05-001-03_freq_20260526_20260528.jpg');
            tiltPath = fullfile(tiltDir, 'Tilt_X_20260526_20260528.jpg');
            lowpassPath = fullfile(lowpassDir, 'dynstrain_lp_G05_20260526-20260528.jpg');
            writeBytes(humidityPath, uint8([1 2 3]));
            writeBytes(tiltPath, uint8([4 5 6]));
            writeBytes(lowpassPath, uint8([7 8 9]));

            humidity = bms.data.ArtifactCollector.collectModule( ...
                root, 'humidity', '', datetime('now') - minutes(1), struct());
            tilt = bms.data.ArtifactCollector.collectModule( ...
                root, 'tilt', '', datetime('now') - minutes(1), struct());
            lowpass = bms.data.ArtifactCollector.collectModule( ...
                root, 'dynamic_strain_lowpass', '', datetime('now') - minutes(1), struct());

            tc.verifyTrue(any(cellfun(@(s) strcmp(s.path, humidityPath), humidity)));
            tc.verifyTrue(any(cellfun(@(s) strcmp(s.path, tiltPath), tilt)));
            tc.verifyTrue(any(cellfun(@(s) strcmp(s.path, lowpassPath), lowpass)));
            clear cleanup;
        end

        function cableAccelerationEnvelopeFiguresAreManifested(tc)
            root = [tempname '_highfreq_regression'];
            mkdir(root);
            cleanup = onCleanup(@() rmdir(root, 's'));
            spec = bms.analyzer.DynamicAccelerationPipeline.spec('cable_accel');
            envelopeDir = fullfile(root, spec.envelopeOutputDir);
            mkdir(envelopeDir);
            jpgPath = fullfile(envelopeDir, 'CableAccelEnvelope30_CF-1_20260401_20260430.jpg');
            figPath = fullfile(envelopeDir, 'CableAccelEnvelope30_CF-1_20260401_20260430.fig');
            writeBytes(jpgPath, uint8([1 2 3 4]));
            writeBytes(figPath, uint8([5 6 7 8]));
            outputDirs = bms.data.ArtifactCollector.defaultOutputDirNames('cable_accel');
            rawDir = fullfile(root, outputDirs{1});
            mkdir(rawDir);
            rawPath = fullfile(rawDir, 'CableAccel_CF-1_20260401_20260430.jpg');
            writeBytes(rawPath, uint8([9 10 11 12]));

            artifacts = bms.data.ArtifactCollector.collectModule( ...
                root, 'cable_accel', '', datetime('now') - minutes(1), struct());
            paths = cellfun(@(s) string(s.path), artifacts, 'UniformOutput', true);
            jpgIdx = find(paths == string(jpgPath), 1);
            figIdx = find(paths == string(figPath), 1);
            rawIdx = find(paths == string(rawPath), 1);
            tc.verifyNotEmpty(jpgIdx);
            tc.verifyNotEmpty(figIdx);
            tc.verifyNotEmpty(rawIdx);
            tc.verifyEqual(artifacts{jpgIdx}.kind, 'figure');
            tc.verifyEqual(artifacts{figIdx}.kind, 'figure');
            tc.verifyEqual(artifacts{jpgIdx}.role, 'envelope30min');
            tc.verifyEqual(artifacts{figIdx}.role, 'envelope30min');
            tc.verifyEqual(artifacts{rawIdx}.role, 'time_history');
            tc.verifyNotEmpty(artifacts{jpgIdx}.sha256);
            tc.verifyNotEmpty(artifacts{figIdx}.sha256);

            started = datetime('now') - seconds(1);
            result = bms.analyzer.AnalyzerResult.ok( ...
                'cable_accel', '', artifacts, {}, started, datetime('now'));
            details = struct('module_logs', {{result.toStruct()}});
            context = bms.core.AnalysisContext(root, '2026-04-01', '2026-04-30', struct(), struct());
            manifest = bms.app.ManifestWriter.build(context, 'ok', details);
            tc.verifyEqual(result.ArtifactCount, 3);
            tc.verifyEqual(result.FigureCount, 3);
            tc.verifyEqual(manifest.artifact_count, 3);
            tc.verifyEqual(numel(manifest.module_artifacts), 1);
            tc.verifyEqual(numel(manifest.module_artifacts{1}.artifacts), 3);
            clear cleanup;
        end
    end
end

function writeBytes(path, bytes)
fid = fopen(path, 'w');
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, bytes, 'uint8');
clear cleanup;
end
