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

    % 记录原始字段名映射（尤其 per_point 中含连字符的 point_id），便于保存时还原
    name_map = struct();
    tokens = regexp(txt, '"(GB[^"]+)"\s*:', 'tokens');
    for i = 1:numel(tokens)
        orig = tokens{i}{1};
        safe = strrep(orig,'-','_');  % jsondecode 会把连字符改成下划线
        name_map.(safe) = orig;
    end
    if ~isempty(fieldnames(name_map))
        cfg.name_map_global = name_map;
    end

    cfg.source = path;
    cfg.warnings = validate_config(cfg);
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
    sub_keys = {'deflection','acceleration','acceleration_raw','strain','tilt','crack','humidity','temperature'};
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
    sensors = {'deflection','acceleration','acceleration_raw','strain','tilt','crack','crack_temp','humidity','temperature'};
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
