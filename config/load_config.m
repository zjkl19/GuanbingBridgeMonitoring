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
    cfg.source = path;
    cfg.warnings = validate_config(cfg);
end

function warns = validate_config(cfg)
%VALIDATE_CONFIG Basic schema checks; returns cell array of warning strings.
    warns = {};
    required_top = {"defaults","subfolders","file_patterns","groups","plot_styles"};
    for k = 1:numel(required_top)
        if ~isfield(cfg, required_top{k})
            warns{end+1} = sprintf('Missing config.%s', required_top{k}); %#ok<AGROW>
        end
    end

    % header marker
    if ~isfield(cfg,'defaults') || ~isfield(cfg.defaults,'header_marker')
        warns{end+1} = 'defaults.header_marker not set; fallback to [绝对时间]';
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
end
