classdef WimZhichenBcpSource
    %WIMZHICHENBCPSOURCE Parser and decoder for Zhichen WIM native BCP files.

    methods (Static)
        function spec = loadSpec(fmtPath)
            spec = struct();
            spec.fmt = bms.analyzer.WimZhichenBcpSource.parseFmt(fmtPath);
            spec.index = bms.analyzer.WimZhichenBcpSource.indexMap(spec.fmt);
            bms.analyzer.WimZhichenBcpSource.validateRequired(spec.index);
        end

        function fmt = parseFmt(fmtPath)
            lines = readlines(fmtPath, 'WhitespaceRule', 'preserve');
            if numel(lines) < 3
                error('Invalid fmt file: %s', fmtPath);
            end

            ncols = str2double(strtrim(lines(2)));
            fmt = repmat(struct('name', '', 'type', '', 'prefix', 0, 'len', 0), ncols, 1);
            for i = 1:ncols
                line = strtrim(lines(i + 2));
                if line == ""
                    continue;
                end

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

        function idx = indexMap(fmt)
            idx = struct();
            for i = 1:numel(fmt)
                idx.(fmt(i).name) = i;
            end
        end

        function required = requiredColumns()
            required = {'HSData_DT', 'Lane_Id', 'Axle_Num', 'Gross_Load', 'Speed', 'License_Plate'};
            for k = 1:8
                required{end + 1} = sprintf('LWheel_%d_W', k); %#ok<AGROW>
                required{end + 1} = sprintf('RWheel_%d_W', k); %#ok<AGROW>
            end
            for k = 1:7
                required{end + 1} = sprintf('AxleDis%d', k); %#ok<AGROW>
            end
        end

        function validateRequired(idx, required)
            if nargin < 2
                required = bms.analyzer.WimZhichenBcpSource.requiredColumns();
            end
            for i = 1:numel(required)
                if ~isfield(idx, required{i})
                    error('Missing column in fmt: %s', required{i});
                end
            end
        end

        function [rowBytes, ok] = readRowBytes(fid, fmt)
            n = numel(fmt);
            rowBytes = cell(1, n);
            ok = true;
            for i = 1:n
                [bytes, ok] = bms.analyzer.WimZhichenBcpSource.readFieldBytes(fid, fmt(i));
                if ~ok
                    rowBytes = {};
                    return;
                end
                rowBytes{i} = bytes;
            end
        end

        function [bytes, ok] = readFieldBytes(fid, spec)
            ok = true;
            if spec.prefix > 0
                len = bms.analyzer.WimZhichenBcpSource.readPrefixLength(fid, spec.prefix);
                if isempty(len)
                    ok = false;
                    bytes = [];
                    return;
                end
                if len == 0
                    bytes = [];
                    return;
                end
                bytes = fread(fid, len, 'uint8=>uint8');
                if numel(bytes) < len
                    ok = false;
                end
            else
                bytes = fread(fid, spec.len, 'uint8=>uint8');
                if numel(bytes) < spec.len
                    ok = false;
                end
            end
        end

        function len = readPrefixLength(fid, prefixLength)
            switch prefixLength
                case 1
                    len = fread(fid, 1, 'uint8=>double');
                case 2
                    len = fread(fid, 1, 'uint16=>double');
                case 4
                    len = fread(fid, 1, 'uint32=>double');
                case 8
                    len = fread(fid, 1, 'uint64=>double');
                otherwise
                    len = fread(fid, 1, 'uint32=>double');
            end
        end

        function record = decodeRecord(~, idx, rowBytes, ~)
            record = struct();
            record.time_datenum = bms.analyzer.WimZhichenBcpSource.decodeDateTime(rowBytes{idx.HSData_DT});
            record.lane = bms.analyzer.WimZhichenBcpSource.decodeInt(rowBytes{idx.Lane_Id});
            record.axle_num = bms.analyzer.WimZhichenBcpSource.decodeInt(rowBytes{idx.Axle_Num});
            record.gross = bms.analyzer.WimZhichenBcpSource.decodeInt(rowBytes{idx.Gross_Load});
            record.speed = bms.analyzer.WimZhichenBcpSource.decodeInt(rowBytes{idx.Speed});
            record.plate = bms.analyzer.WimZhichenBcpSource.decodeString(rowBytes{idx.License_Plate}, 'utf-16le');

            record.axle_weights = zeros(1, 8);
            for k = 1:8
                lw = bms.analyzer.WimZhichenBcpSource.decodeInt(rowBytes{idx.(sprintf('LWheel_%d_W', k))});
                rw = bms.analyzer.WimZhichenBcpSource.decodeInt(rowBytes{idx.(sprintf('RWheel_%d_W', k))});
                record.axle_weights(k) = nansum([lw rw]);
            end

            record.axle_distances = zeros(1, 7);
            for k = 1:7
                record.axle_distances(k) = bms.analyzer.WimZhichenBcpSource.decodeInt(rowBytes{idx.(sprintf('AxleDis%d', k))});
            end
        end

        function values = decodeAllRow(fmt, rowBytes, encoding)
            values = cell(1, numel(fmt));
            for i = 1:numel(fmt)
                values{i} = bms.analyzer.WimZhichenBcpSource.decodeByType(fmt(i).type, rowBytes{i}, encoding);
            end
        end

        function dt = decodeDateTime(bytes)
            if isempty(bytes) || numel(bytes) < 8
                dt = NaN;
                return;
            end
            days = typecast(uint8(bytes(1:4)), 'int32');
            ticks = typecast(uint8(bytes(5:8)), 'int32');
            dt = datenum('1900-01-01') + double(days) + double(ticks) / 300 / 86400;
        end

        function value = decodeInt(bytes)
            if isempty(bytes)
                value = NaN;
                return;
            end

            n = numel(bytes);
            if n == 1
                value = double(typecast(uint8(bytes), 'uint8'));
            elseif n == 2
                value = double(typecast(uint8(bytes), 'int16'));
            elseif n == 4
                value = double(typecast(uint8(bytes), 'int32'));
            else
                value = double(bytes(1));
            end
        end

        function text = decodeString(bytes, encoding)
            if isempty(bytes)
                text = '';
                return;
            end

            try
                if strcmpi(encoding, 'utf-16le')
                    text = native2unicode(uint8(bytes), 'UTF-16LE');
                else
                    text = native2unicode(uint8(bytes), encoding);
                end
            catch
                text = native2unicode(uint8(bytes), 'UTF-8');
            end
            text = strtrim(text);
        end

        function value = decodeByType(typeName, bytes, encoding)
            if isempty(bytes)
                value = '';
                return;
            end

            switch upper(typeName)
                case 'SQLINT'
                    value = double(typecast(uint8(bytes), 'int32'));
                case 'SQLTINYINT'
                    value = double(typecast(uint8(bytes), 'uint8'));
                case 'SQLSMALLINT'
                    value = double(typecast(uint8(bytes), 'int16'));
                case 'SQLBIGINT'
                    value = double(typecast(uint8(bytes), 'int64'));
                case 'SQLDATETIME'
                    dt = bms.analyzer.WimZhichenBcpSource.decodeDateTime(bytes);
                    if isfinite(dt)
                        value = datestr(dt, 'yyyy-mm-dd HH:MM:SS');
                    else
                        value = '';
                    end
                case 'SQLCHAR'
                    value = bms.analyzer.WimZhichenBcpSource.decodeString(bytes, encoding);
                case 'SQLNCHAR'
                    value = bms.analyzer.WimZhichenBcpSource.decodeString(bytes, 'utf-16le');
                case 'SQLNUMERIC'
                    value = bms.analyzer.WimZhichenBcpSource.decodeNumeric(bytes);
                case 'SQLFLT4'
                    value = double(typecast(uint8(bytes), 'single'));
                case 'SQLFLT8'
                    value = double(typecast(uint8(bytes), 'double'));
                otherwise
                    value = bms.analyzer.WimZhichenBcpSource.decodeString(bytes, encoding);
            end
        end

        function value = decodeNumeric(bytes)
            if isempty(bytes)
                value = NaN;
                return;
            end

            signByte = bytes(1);
            mag = 0;
            if numel(bytes) > 1
                for i = 2:numel(bytes)
                    mag = mag + double(bytes(i)) * 256^(i - 2);
                end
            end
            if signByte == 0
                value = -mag;
            else
                value = mag;
            end
        end

        function sqlTypeName = sqlType(spec)
            switch upper(spec.type)
                case 'SQLINT'
                    sqlTypeName = 'INT';
                case 'SQLTINYINT'
                    sqlTypeName = 'TINYINT';
                case 'SQLSMALLINT'
                    sqlTypeName = 'SMALLINT';
                case 'SQLBIGINT'
                    sqlTypeName = 'BIGINT';
                case 'SQLDATETIME'
                    sqlTypeName = 'DATETIME';
                case 'SQLCHAR'
                    sqlTypeName = sprintf('VARCHAR(%d)', spec.len);
                case 'SQLNCHAR'
                    sqlTypeName = sprintf('NVARCHAR(%d)', spec.len);
                case 'SQLNUMERIC'
                    sqlTypeName = sprintf('NUMERIC(%d,0)', max(1, min(38, spec.len)));
                case 'SQLFLT4'
                    sqlTypeName = 'REAL';
                case 'SQLFLT8'
                    sqlTypeName = 'FLOAT';
                otherwise
                    sqlTypeName = 'NVARCHAR(255)';
            end
        end
    end
end
