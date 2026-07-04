classdef ConfigMigrator
    %CONFIGMIGRATOR In-memory config normalization for legacy JSON files.

    properties (Constant)
        TargetVersion = 1
    end

    methods (Static)
        function cfg = migrate(cfg)
            if nargin < 1 || isempty(cfg)
                cfg = struct();
            end
            if ~isstruct(cfg)
                error('BMS:ConfigMigrator:InvalidConfig', 'Config must be a struct.');
            end
            cfg = cfg(1);
            cfg = bms.config.ConfigMigrator.ensureSchemaVersion(cfg);
            cfg = bms.config.ConfigMigrator.ensureStructs(cfg, { ...
                'defaults','subfolders','file_patterns','points','plot_styles', ...
                'per_point','post_filter_thresholds','plot_common','reporting','gui','wim'});
            cfg = bms.config.ConfigMigrator.ensurePlotCommonDefaults(cfg);
            cfg = bms.config.ConfigMigrator.ensureGuiDefaults(cfg);
        end

        function cfg = ensureSchemaVersion(cfg)
            if ~isfield(cfg, 'config_schema_version') || isempty(cfg.config_schema_version)
                cfg.config_schema_version = bms.config.ConfigMigrator.TargetVersion;
            end
        end

        function cfg = ensureStructs(cfg, names)
            for i = 1:numel(names)
                name = char(names{i});
                if ~isfield(cfg, name) || isempty(cfg.(name)) || ~isstruct(cfg.(name))
                    cfg.(name) = struct();
                end
            end
        end

        function cfg = ensurePlotCommonDefaults(cfg)
            defaults = struct( ...
                'append_timestamp', false, ...
                'gap_mode', 'connect', ...
                'gap_break_factor', 5, ...
                'save_fig', true, ...
                'lightweight_fig', true, ...
                'fig_max_points', 50000);
            cfg.plot_common = bms.config.ConfigMigrator.fillMissing(cfg.plot_common, defaults);
        end

        function cfg = ensureGuiDefaults(cfg)
            defaults = struct('show_warnings', false);
            cfg.gui = bms.config.ConfigMigrator.fillMissing(cfg.gui, defaults);
        end

        function out = fillMissing(out, defaults)
            if ~isstruct(out)
                out = struct();
            end
            names = fieldnames(defaults);
            for i = 1:numel(names)
                name = names{i};
                if ~isfield(out, name) || isempty(out.(name))
                    out.(name) = defaults.(name);
                end
            end
        end
    end
end
