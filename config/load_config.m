function cfg = load_config(path)
%LOAD_CONFIG Load JSON configuration for data loading/cleaning.
%   cfg = load_config();                % loads config/default_config.json
%   cfg = load_config('custom.json');   % loads specified JSON
%
%   The config structure mirrors default_config.json fields and adds:
%     - cfg.source: absolute path of the loaded file
%
%   If the file is missing, an error is thrown.

    if nargin < 1 || isempty(path)
        path = fullfile(fileparts(mfilename('fullpath')), 'default_config.json');
    end
    if ~isfile(path)
        error('Config file not found: %s', path);
    end
    txt = fileread(path);
    cfg = jsondecode(txt);

    % 记录原始字段名映射（point_id 可能含连字符），便于保存时还原
    % 仅映射 per_point / file_patterns.per_point 中实际存在的测点字段
    safe_ids = collect_safe_point_ids(cfg);
    name_map = struct();
    if ~isempty(safe_ids)
        safe_set = struct();
        for i = 1:numel(safe_ids)
            safe_set.(safe_ids{i}) = true;
        end
        tokens = regexp(txt, '"([^"]+)"\s*:', 'tokens');
        for i = 1:numel(tokens)
            orig = tokens{i}{1};
            safe = strrep(orig,'-','_');  % jsondecode 会把连字符改成下划线
            if isfield(safe_set, safe)
                name_map.(safe) = orig;
            end
        end
    end
    if ~isempty(fieldnames(name_map))
        cfg.name_map_global = name_map;
    end

    cfg.source = path;
    cfg.warnings = validate_config(cfg);
end

function ids = collect_safe_point_ids(cfg)
% Collect point_id fieldnames from per_point and file_patterns.per_point
    ids = {};
    if isfield(cfg,'per_point') && isstruct(cfg.per_point)
        sens = fieldnames(cfg.per_point);
        for i = 1:numel(sens)
            pts = cfg.per_point.(sens{i});
            if isstruct(pts)
                ids = [ids; fieldnames(pts)]; %#ok<AGROW>
            end
        end
    end
    if isfield(cfg,'file_patterns') && isstruct(cfg.file_patterns)
        sens = fieldnames(cfg.file_patterns);
        for i = 1:numel(sens)
            fp = cfg.file_patterns.(sens{i});
            if isstruct(fp) && isfield(fp,'per_point') && isstruct(fp.per_point)
                ids = [ids; fieldnames(fp.per_point)]; %#ok<AGROW>
            end
        end
    end
    if ~isempty(ids)
        ids = unique(ids, 'stable');
    end
end

function warns = validate_config(cfg)
%VALIDATE_CONFIG Basic schema checks; returns cell array of warning strings.
    warns = {};
    required_top = {"defaults","subfolders","file_patterns","groups","plot_styles","vendor"};
    for k = 1:numel(required_top)
        if ~isfield(cfg, required_top{k})
            warns{end+1} = sprintf('Missing config.%s', required_top{k}); %#ok<AGROW>
        end
    end

    % header marker
    if ~isfield(cfg,'defaults') || ~isfield(cfg.defaults,'header_marker')
        warns{end+1} = 'defaults.header_marker not set; fallback to [绝对时间]';
    elseif ~ischar(cfg.defaults.header_marker) && ~isstring(cfg.defaults.header_marker)
        warns{end+1} = 'defaults.header_marker should be string';
    end

    % subfolders
    sub_keys = {'deflection','acceleration','acceleration_raw','cable_accel','cable_accel_raw', ...
                'strain','tilt','crack','humidity','temperature','wind_raw'};
    if isfield(cfg,'subfolders')
        for k = 1:numel(sub_keys)
            if ~isfield(cfg.subfolders, sub_keys{k})
                warns{end+1} = sprintf('subfolders.%s missing; using fallback in code', sub_keys{k});
            end
        end
    end

    % groups basic checks
    if ~isfield(cfg,'groups')
        warns{end+1} = 'groups not set; using hardcoded defaults';
    end

    % plot_styles basic checks
    if ~isfield(cfg,'plot_styles')
        warns{end+1} = 'plot_styles not set; using hardcoded defaults';
    end

    % file_patterns basic checks per sensor
    sensors = {'deflection','acceleration','acceleration_raw','cable_accel','cable_accel_raw', ...
               'strain','tilt','crack','crack_temp','humidity','temperature', ...
               'wind_speed','wind_direction','wind'};
    if isfield(cfg,'file_patterns')
        for k = 1:numel(sensors)
            s = sensors{k};
            if ~isfield(cfg.file_patterns, s), continue; end
            fp = cfg.file_patterns.(s);
            if ~isfield(fp,'default') || isempty(fp.default)
                warns{end+1} = sprintf('file_patterns.%s.default missing or empty', s); %#ok<AGROW>
            end
        end
    end

    % defaults per sensor thresholds schema
    if isfield(cfg,'defaults')
        fns = fieldnames(cfg.defaults);
        for i = 1:numel(fns)
            def = cfg.defaults.(fns{i});
            if isfield(def,'thresholds')
                th = def.thresholds;
                if ~(isstruct(th) || isempty(th))
                    warns{end+1} = sprintf('defaults.%s.thresholds should be struct array', fns{i}); %#ok<AGROW>
                end
            end
        end
    end
end
