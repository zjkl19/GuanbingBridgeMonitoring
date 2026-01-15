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
end
