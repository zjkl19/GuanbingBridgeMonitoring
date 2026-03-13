function varargout = offset_correction_registry(action, varargin)
% offset_correction_registry  Track applied offset corrections during a run.

    persistent entries
    if isempty(entries)
        entries = empty_entries();
    end

    action = lower(string(action));
    switch action
        case "reset"
            entries = empty_entries();
        case "record"
            if ~isempty(varargin)
                entries = merge_entry(entries, varargin{1});
            end
        case "get"
            varargout{1} = entries;
        case "write"
            outDir = varargin{1};
            startTs = varargin{2};
            [filepath, count] = write_entries(entries, outDir, startTs);
            varargout{1} = filepath;
            if nargout > 1
                varargout{2} = count;
            end
        otherwise
            error('Unsupported action: %s', action);
    end
end

function entries = empty_entries()
    entries = struct( ...
        'sensor_type', {}, ...
        'point_id', {}, ...
        'offset_correction', {}, ...
        'start_time', {}, ...
        'end_time', {}, ...
        'sample_count', {}, ...
        'load_calls', {}, ...
        'files', {});
end

function entries = merge_entry(entries, entry)
    if ~isstruct(entry) || ~isfield(entry, 'sensor_type') || ~isfield(entry, 'point_id') ...
            || ~isfield(entry, 'offset_correction')
        return;
    end
    if isempty(entry.offset_correction) || ~isnumeric(entry.offset_correction) ...
            || ~isscalar(entry.offset_correction) || ~isfinite(entry.offset_correction) ...
            || entry.offset_correction == 0
        return;
    end

    idx = [];
    for i = 1:numel(entries)
        if strcmp(entries(i).sensor_type, entry.sensor_type) ...
                && strcmp(entries(i).point_id, entry.point_id) ...
                && isequal(entries(i).offset_correction, double(entry.offset_correction))
            idx = i;
            break;
        end
    end

    if isempty(idx)
        newEntry = struct( ...
            'sensor_type', char(string(entry.sensor_type)), ...
            'point_id', char(string(entry.point_id)), ...
            'offset_correction', double(entry.offset_correction), ...
            'start_time', get_dt(entry, 'start_time'), ...
            'end_time', get_dt(entry, 'end_time'), ...
            'sample_count', get_num(entry, 'sample_count', 0), ...
            'load_calls', 1, ...
            'files', normalize_files(get_field(entry, 'files', {})));
        entries(end+1, 1) = newEntry; %#ok<AGROW>
        return;
    end

    entries(idx).start_time = min_dt(entries(idx).start_time, get_dt(entry, 'start_time'));
    entries(idx).end_time = max_dt(entries(idx).end_time, get_dt(entry, 'end_time'));
    entries(idx).sample_count = entries(idx).sample_count + get_num(entry, 'sample_count', 0);
    entries(idx).load_calls = entries(idx).load_calls + 1;
    newFiles = normalize_files(get_field(entry, 'files', {}));
    combinedFiles = normalize_files([entries(idx).files(:); newFiles(:)]);
    dedupFiles = {};
    for i = 1:numel(combinedFiles)
        item = combinedFiles{i};
        if isempty(item)
            continue;
        end
        if isempty(dedupFiles) || ~any(strcmp(dedupFiles, item))
            dedupFiles{end+1, 1} = item; %#ok<AGROW>
        end
    end
    entries(idx).files = dedupFiles;
end

function value = get_field(s, field, default)
    value = default;
    if isstruct(s) && isfield(s, field)
        value = s.(field);
    end
end

function value = get_num(s, field, default)
    value = default;
    raw = get_field(s, field, default);
    if isnumeric(raw) && isscalar(raw) && isfinite(raw)
        value = double(raw);
    end
end

function dt = get_dt(s, field)
    dt = NaT;
    raw = get_field(s, field, NaT);
    if isa(raw, 'datetime') && isscalar(raw)
        dt = raw;
    end
end

function files = normalize_files(files)
    if ischar(files) || isstring(files)
        files = cellstr(string(files(:)));
    elseif iscell(files)
        out = {};
        for i = 1:numel(files)
            item = files{i};
            if iscell(item)
                nested = normalize_files(item);
                out = [out; nested(:)]; %#ok<AGROW>
            elseif isstring(item)
                if isscalar(item)
                    out{end+1, 1} = char(string(item)); %#ok<AGROW>
                end
            elseif ischar(item)
                out{end+1, 1} = char(string(item)); %#ok<AGROW>
            end
        end
        files = out;
    else
        files = {};
    end
    files = files(~cellfun(@isempty, files));
end

function out = min_dt(a, b)
    vals = [a; b];
    vals = vals(~isnat(vals));
    if isempty(vals)
        out = NaT;
    else
        out = min(vals);
    end
end

function out = max_dt(a, b)
    vals = [a; b];
    vals = vals(~isnat(vals));
    if isempty(vals)
        out = NaT;
    else
        out = max(vals);
    end
end

function [filepath, count] = write_entries(entries, outDir, startTs)
    if nargin < 2 || isempty(outDir)
        outDir = fullfile(pwd, 'outputs', 'run_logs');
    end
    if nargin < 3 || isempty(startTs) || ~isa(startTs, 'datetime')
        startTs = datetime('now');
    end
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    count = numel(entries);
    T = table('Size', [count, 8], ...
        'VariableTypes', {'string','string','double','string','string','double','double','string'}, ...
        'VariableNames', {'SensorType','PointID','OffsetCorrection','StartTime','EndTime','SampleCount','LoadCalls','Files'});

    for i = 1:count
        T.SensorType(i) = string(entries(i).sensor_type);
        T.PointID(i) = string(entries(i).point_id);
        T.OffsetCorrection(i) = entries(i).offset_correction;
        T.StartTime(i) = string(format_dt(entries(i).start_time));
        T.EndTime(i) = string(format_dt(entries(i).end_time));
        T.SampleCount(i) = entries(i).sample_count;
        T.LoadCalls(i) = entries(i).load_calls;
        T.Files(i) = string(join_files(entries(i).files));
    end

    filepath = fullfile(outDir, sprintf('offset_correction_applied_%s.xlsx', datestr(startTs, 'yyyymmdd_HHMMSS')));
    writetable(T, filepath);
end

function txt = format_dt(dt)
    txt = '';
    if isa(dt, 'datetime') && isscalar(dt) && ~isnat(dt)
        txt = char(string(dt, 'yyyy-MM-dd HH:mm:ss'));
    end
end

function txt = join_files(files)
    txt = '';
    files = normalize_files(files);
    if isempty(files)
        return;
    end
    for i = 1:numel(files)
        item = files{i};
        if isstring(item)
            item = char(string(item));
        elseif ~ischar(item)
            continue;
        end
        item = item(:)';
        if isempty(item)
            continue;
        end
        if isempty(txt)
            txt = item;
        else
            txt = [txt '; ' item]; %#ok<AGROW>
        end
    end
end
