classdef test_config_layer_loader < matlab.unittest.TestCase
    methods (Test)
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
