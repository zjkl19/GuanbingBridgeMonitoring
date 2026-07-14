classdef test_config_layer_loader < matlab.unittest.TestCase
    methods (Test)
        function sharedFixtureFingerprintMatchesPythonContract(tc)
            fixture = fullfile(project_root(), 'tests', 'config', 'fingerprint', 'project.json');
            tc.verifyEqual( ...
                upper(bms.config.ConfigLayerLoader.dependencySha256(fixture)), ...
                '01A68C332F2E2ACD36D3DCBE6C179C1D616BBCC841B89E28499D405EA99B17A6');
        end

        function unicodeFixtureFingerprintMatchesPythonContract(tc)
            fixture = fullfile(project_root(), 'tests', 'config', 'fingerprint', 'unicode_project.json');
            tc.verifyEqual( ...
                upper(bms.config.ConfigLayerLoader.dependencySha256(fixture)), ...
                'CFE34E9BFA1BBD3359A621450AB61EB557E5081FECFFC44A58CBFFAE96CA90C5');
        end

        function layeredConfigMergesBaseIncludesAndOverlay(tc)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_dir(root)); %#ok<NASGU>

            write_text(fullfile(root, 'base.json'), [ ...
                '{"vendor":"unit","defaults":{"header_marker":"time","gap":1},' ...
                '"subfolders":{"deflection":"base_folder"},' ...
                '"file_patterns":{},"groups":{},"points":{},"plot_styles":{"deflection":{"ylabel":"old"}}}']);
            write_text(fullfile(root, 'per_point.json'), ...
                '{"deflection":{"P_1":{"alarm_bounds":{"level2":[-2,2]}}}}');
            write_text(fullfile(root, 'project.json'), [ ...
                '{"extends":"base.json","includes":{"per_point":"per_point.json"},' ...
                '"plot_styles":{"deflection":{"title_prefix":"new"}}}']);

            [cfg, combinedText, meta] = bms.config.ConfigLayerLoader.load(fullfile(root, 'project.json'));

            tc.verifyEqual(cfg.defaults.header_marker, 'time');
            tc.verifyEqual(cfg.plot_styles.deflection.ylabel, 'old');
            tc.verifyEqual(cfg.plot_styles.deflection.title_prefix, 'new');
            tc.verifyTrue(isfield(cfg.per_point.deflection, 'P_1'));
            tc.verifyGreaterThanOrEqual(numel(meta.files), 3);
            tc.verifyTrue(contains(combinedText, 'alarm_bounds'));
        end

        function loadConfigUsesLayeredResult(tc)
            cfg = load_config(fullfile(project_root(), 'tests', 'config', 'layered_bridge_project.json'));

            tc.verifyEqual(cfg.plot_styles.deflection.ylabel, '位移 (mm)');
            tc.verifyEqual(cfg.plot_styles.deflection.title_prefix, '挠度时程');
            tc.verifyTrue(isfield(cfg.per_point.deflection, 'D_1'));
            tc.verifyTrue(isfield(cfg, 'warnings'));
        end

        function shuixianhuaLayeredConfigMatchesProductionConfig(tc)
            root = project_root();
            original = load_config(fullfile(root, 'config', 'shuixianhua_config.json'));
            layered = load_config(fullfile(root, 'config', 'shuixianhua_layered_config.json'));

            volatile = {'source', 'warnings', 'name_map_global'};
            for i = 1:numel(volatile)
                if isfield(original, volatile{i}), original = rmfield(original, volatile{i}); end
                if isfield(layered, volatile{i}), layered = rmfield(layered, volatile{i}); end
            end

            tc.verifyEqual(layered, original);
        end

        function shuixianhuaAccelerationRmsWarnLinesMatchArchAndGirder(tc)
            cfg = load_config(fullfile(project_root(), 'config', 'shuixianhua_config.json'));
            lines = cfg.plot_styles.acceleration.rms_warn_lines;

            tc.verifyEqual([lines.ZG.y], [31.5 50], 'AbsTol', 1e-12);
            tc.verifyEqual([lines.ZL.y], [31.5 50], 'AbsTol', 1e-12);
        end

        function dependencyHashTracksIncludedFileChanges(tc)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_dir(root)); %#ok<NASGU>
            entryPath = fullfile(root, 'project.json');
            includePath = fullfile(root, 'per_point.json');
            write_text(entryPath, '{"includes":{"per_point":"per_point.json"}}');
            write_text(includePath, '{"P1":{"limit":1}}');

            entryHash = bms.io.JsonFile.sha256(entryPath);
            first = bms.config.ConfigLayerLoader.dependencySha256(entryPath);
            write_text(includePath, '{"P1":{"limit":2}}');
            second = bms.config.ConfigLayerLoader.dependencySha256(entryPath);

            tc.verifyEqual(bms.io.JsonFile.sha256(entryPath), entryHash);
            tc.verifyNotEqual(second, first);
        end

        function dependencyHashKeepsFileIdentityWhenLayerContentsSwap(tc)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_dir(root)); %#ok<NASGU>
            entryPath = fullfile(root, 'project.json');
            firstPath = fullfile(root, 'a.json');
            secondPath = fullfile(root, 'b.json');
            write_text(entryPath, '{"layers":["a.json","b.json"]}');
            write_text(firstPath, '{"value":1}');
            write_text(secondPath, '{"value":2}');
            [beforeCfg, ~] = bms.config.ConfigLayerLoader.load(entryPath);
            beforeHash = bms.config.ConfigLayerLoader.dependencySha256(entryPath);

            write_text(firstPath, '{"value":2}');
            write_text(secondPath, '{"value":1}');
            [afterCfg, ~] = bms.config.ConfigLayerLoader.load(entryPath);

            tc.verifyEqual(beforeCfg.value, 2);
            tc.verifyEqual(afterCfg.value, 1);
            tc.verifyNotEqual(bms.config.ConfigLayerLoader.dependencySha256(entryPath), beforeHash);
        end
    end
end

function write_text(path, text)
    fid = fopen(path, 'wt', 'n', 'UTF-8');
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', text);
end

function cleanup_dir(path)
    if isfolder(path)
        rmdir(path, 's');
    end
end

function root = project_root()
    root = fileparts(fileparts(mfilename('fullpath')));
end
