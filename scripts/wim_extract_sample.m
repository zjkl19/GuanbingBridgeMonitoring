function wim_extract_sample(src_dir, yyyymm, out_dir, n, encoding)
% wim_extract_sample  Extract first N rows from WIM bcp/fmt and save as sample.
%
% Usage:
%   wim_extract_sample();  % uses defaults
%   wim_extract_sample(src_dir, yyyymm, out_dir, n, encoding)
%
% Output:
%   - <out_dir>/HS_Data_<yyyymm>_sample_<n>.bcp
%   - <out_dir>/HS_Data_<yyyymm>_sample_<n>.fmt
%   - <out_dir>/HS_Data_<yyyymm>_sample_<n>.csv

    if nargin < 1 || isempty(src_dir)
        src_dir = fullfile(pwd, 'data', '_samples', 'wim', 'zhichen', '202512');
    end
    if nargin < 2 || isempty(yyyymm)
        yyyymm = '202512';
    end
    if nargin < 3 || isempty(out_dir)
        out_dir = src_dir;
    end
    if nargin < 4 || isempty(n)
        n = 300;
    end
    if nargin < 5 || isempty(encoding)
        encoding = 'gbk';
    end

    fmt_path = fullfile(src_dir, ['HS_Data_' yyyymm '.fmt']);
    bcp_path = fullfile(src_dir, ['HS_Data_' yyyymm '.bcp']);
    if ~exist(fmt_path, 'file')
        error('Fmt file not found: %s', fmt_path);
    end
    if ~exist(bcp_path, 'file')
        error('BCP file not found: %s', bcp_path);
    end
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end

    fmt = parse_bcp_fmt(fmt_path);
    out_bcp = fullfile(out_dir, sprintf('HS_Data_%s_sample_%d.bcp', yyyymm, n));
    out_fmt = fullfile(out_dir, sprintf('HS_Data_%s_sample_%d.fmt', yyyymm, n));
    out_csv = fullfile(out_dir, sprintf('HS_Data_%s_sample_%d.csv', yyyymm, n));

    copyfile(fmt_path, out_fmt);

    fid_in = fopen(bcp_path, 'r', 'ieee-le');
    if fid_in < 0, error('Cannot open bcp: %s', bcp_path); end
    cleanup_in = onCleanup(@() fclose(fid_in)); %#ok<NASGU>

    fid_out = fopen(out_bcp, 'w', 'ieee-le');
    if fid_out < 0, error('Cannot write bcp: %s', out_bcp); end
    cleanup_out = onCleanup(@() fclose(fid_out)); %#ok<NASGU>

    rows = cell(n+1, numel(fmt));
    headers = {fmt.name};
    rows(1,:) = headers;

    count = 0;
    while count < n
        [row_raw, row_bytes, ok] = read_bcp_row_raw(fid_in, fmt);
        if ~ok, break; end
        fwrite(fid_out, row_raw, 'uint8');

        count = count + 1;
        vals = decode_row(fmt, row_bytes, encoding);
        rows(count+1,:) = vals;
    end

    if count < n
        rows = rows(1:count+1, :);
    end

    writecell(rows, out_csv, 'Encoding','UTF-8');
    fprintf('Sample rows: %d\n', count);
    fprintf('Sample bcp: %s\n', out_bcp);
    fprintf('Sample fmt: %s\n', out_fmt);
    fprintf('Sample csv: %s\n', out_csv);
end

% =========================
% BCP parsing helpers
% =========================
function fmt = parse_bcp_fmt(fmt_path)
    lines = readlines(fmt_path, 'WhitespaceRule','preserve');
    if numel(lines) < 3
        error('Invalid fmt file: %s', fmt_path);
    end
    ncols = str2double(strtrim(lines(2)));
    fmt = repmat(struct('name','','type','','prefix',0,'len',0), ncols, 1);
    for i = 1:ncols
        line = strtrim(lines(i+2));
        if line == "", continue; end
        tokens = regexp(line, '\s+', 'split');
        if numel(tokens) < 7
            error('Fmt line parse error: %s', line);
        end
        fmt(i).type = tokens{2};
        fmt(i).prefix = str2double(tokens{3});
        fmt(i).len = str2double(tokens{4});
        fmt(i).name = tokens{7};
    end
end

function [row_raw, row_bytes, ok] = read_bcp_row_raw(fid, fmt)
    n = numel(fmt);
    row_raw = uint8([]);
    row_bytes = cell(1, n);
    ok = true;
    for i = 1:n
        [raw_bytes, data_bytes, ok] = read_field_raw(fid, fmt(i));
        if ~ok
            row_raw = uint8([]);
            row_bytes = {};
            return;
        end
        row_raw = [row_raw; raw_bytes]; %#ok<AGROW>
        row_bytes{i} = data_bytes;
    end
end

function [raw_bytes, data_bytes, ok] = read_field_raw(fid, spec)
    ok = true;
    raw_bytes = uint8([]);
    data_bytes = uint8([]);
    if spec.prefix > 0
        prefix_bytes = fread(fid, spec.prefix, 'uint8=>uint8');
        if numel(prefix_bytes) < spec.prefix
            ok = false; return;
        end
        len = decode_prefix(prefix_bytes);
        if len == 0
            raw_bytes = prefix_bytes;
            data_bytes = uint8([]);
            return;
        end
        data_bytes = fread(fid, len, 'uint8=>uint8');
        if numel(data_bytes) < len
            ok = false; return;
        end
        raw_bytes = [prefix_bytes; data_bytes];
    else
        data_bytes = fread(fid, spec.len, 'uint8=>uint8');
        if numel(data_bytes) < spec.len
            ok = false; return;
        end
        raw_bytes = data_bytes;
    end
end

function len = decode_prefix(prefix_bytes)
    n = numel(prefix_bytes);
    switch n
        case 1
            len = double(typecast(uint8(prefix_bytes), 'uint8'));
        case 2
            len = double(typecast(uint8(prefix_bytes), 'uint16'));
        case 4
            len = double(typecast(uint8(prefix_bytes), 'uint32'));
        case 8
            len = double(typecast(uint8(prefix_bytes), 'uint64'));
        otherwise
            len = double(typecast(uint8(prefix_bytes), 'uint32'));
    end
end

function vals = decode_row(fmt, row_bytes, encoding)
    vals = cell(1, numel(fmt));
    for i = 1:numel(fmt)
        vals{i} = decode_by_type(fmt(i).type, row_bytes{i}, encoding);
    end
end

function v = decode_by_type(type_name, bytes, encoding)
    if isempty(bytes)
        v = '';
        return;
    end
    switch upper(type_name)
        case 'SQLINT'
            v = double(typecast(uint8(bytes), 'int32'));
        case 'SQLTINYINT'
            v = double(typecast(uint8(bytes), 'uint8'));
        case 'SQLSMALLINT'
            v = double(typecast(uint8(bytes), 'int16'));
        case 'SQLBIGINT'
            v = double(typecast(uint8(bytes), 'int64'));
        case 'SQLDATETIME'
            dt = decode_datetime(bytes);
            if isfinite(dt)
                v = datestr(dt, 'yyyy-mm-dd HH:MM:SS');
            else
                v = '';
            end
        case 'SQLCHAR'
            v = decode_string(bytes, encoding);
        case 'SQLNCHAR'
            v = decode_string(bytes, 'utf-16le');
        case 'SQLNUMERIC'
            v = decode_numeric(bytes);
        case 'SQLFLT4'
            v = double(typecast(uint8(bytes), 'single'));
        case 'SQLFLT8'
            v = double(typecast(uint8(bytes), 'double'));
        otherwise
            v = decode_string(bytes, encoding);
    end
end

function dt = decode_datetime(bytes)
    if isempty(bytes) || numel(bytes) < 8
        dt = NaN; return;
    end
    days = typecast(uint8(bytes(1:4)), 'int32');
    ticks = typecast(uint8(bytes(5:8)), 'int32');
    dt = datenum('1900-01-01') + double(days) + double(ticks) / 300 / 86400;
end

function v = decode_numeric(bytes)
    if isempty(bytes)
        v = NaN; return;
    end
    sign_byte = bytes(1);
    mag = 0;
    if numel(bytes) > 1
        for i = 2:numel(bytes)
            mag = mag + double(bytes(i)) * 256^(i-2);
        end
    end
    if sign_byte == 0
        v = -mag;
    else
        v = mag;
    end
end

function s = decode_string(bytes, encoding)
    if isempty(bytes)
        s = '';
        return;
    end
    try
        if strcmpi(encoding, 'utf-16le')
            s = native2unicode(uint8(bytes), 'UTF-16LE');
        else
            s = native2unicode(uint8(bytes), encoding);
        end
    catch
        s = native2unicode(uint8(bytes), 'UTF-8');
    end
    s = strtrim(s);
end
