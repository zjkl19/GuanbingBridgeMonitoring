classdef SchemaValidator
    %SCHEMAVALIDATOR Lightweight config schema checks for preflight use.

    methods (Static)
        function warns = validate(cfg)
            warns = {};
            if ~isstruct(cfg)
                warns{end+1} = 'cfg must be a struct';
                return;
            end
            required = {'defaults','subfolders','file_patterns','points','plot_styles'};
            for i = 1:numel(required)
                if ~isfield(cfg, required{i})
                    warns{end+1} = ['missing top-level field: ' required{i}]; %#ok<AGROW>
                end
            end
            if isfield(cfg, 'points') && isstruct(cfg.points)
                names = fieldnames(cfg.points);
                for i = 1:numel(names)
                    key = names{i};
                    if isfield(cfg, 'subfolders') && isstruct(cfg.subfolders) && ~isfield(cfg.subfolders, key) ...
                            && ~ismember(key, {'temp_humidity','accel_spectrum','cable_accel_spectrum','cable_force','wind','eq'})
                        warns{end+1} = ['points.' key ' has no matching subfolders.' key]; %#ok<AGROW>
                    end
                end
            end
            warns = [warns, bms.config.SchemaValidator.checkPerPoint(cfg)];
        end

        function warns = checkPerPoint(cfg)
            warns = {};
            if ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point)
                return;
            end
            modules = fieldnames(cfg.per_point);
            for i = 1:numel(modules)
                pts = cfg.per_point.(modules{i});
                if ~isstruct(pts), continue; end
                pnames = fieldnames(pts);
                for j = 1:numel(pnames)
                    rule = pts.(pnames{j});
                    if isfield(rule, 'thresholds') && ~isempty(rule.thresholds)
                        ths = rule.thresholds;
                        for k = 1:numel(ths)
                            if ~isfield(ths(k), 'min') || ~isfield(ths(k), 'max')
                                warns{end+1} = ['threshold missing min/max: per_point.' modules{i} '.' pnames{j}]; %#ok<AGROW>
                            elseif isnumeric(ths(k).min) && isnumeric(ths(k).max) && ths(k).min > ths(k).max
                                warns{end+1} = ['threshold min > max: per_point.' modules{i} '.' pnames{j}]; %#ok<AGROW>
                            end
                        end
                    end
                end
            end
        end
    end
end
