function fixture = create_synthetic_zhichen_fixture(rootDir)
%CREATE_SYNTHETIC_ZHICHEN_FIXTURE Build a tiny, non-production WIM BCP fixture.
%   The public test suite must not depend on the ignored data/_samples tree.
%   This helper writes one clearly synthetic 42-column native BCP row and its
%   matching format file into ROOTDIR.  No production vehicle data is copied.

    if nargin < 1 || isempty(rootDir)
        rootDir = tempname;
    end
    if ~exist(rootDir, 'dir')
        mkdir(rootDir);
    end

    baseName = 'HS_Data_202512_synthetic';
    fixture = struct( ...
        'dir', rootDir, ...
        'fmtName', [baseName '.fmt'], ...
        'bcpName', [baseName '.bcp'], ...
        'fmtPath', fullfile(rootDir, [baseName '.fmt']), ...
        'bcpPath', fullfile(rootDir, [baseName '.bcp']));

    spec = syntheticSpec();
    writeFmt(fixture.fmtPath, spec);
    writeBcp(fixture.bcpPath, spec, syntheticRow());
end

function spec = syntheticSpec()
    names = { ...
        'HSData_Id', 'Lane_Id', 'HSData_DT', 'Oper_Direc', ...
        'Axle_Num', 'AxleGrp_Num', 'Gross_Load', 'Veh_Type', ...
        'LWheel_1_W', 'LWheel_2_W', 'LWheel_3_W', 'LWheel_4_W', ...
        'LWheel_5_W', 'LWheel_6_W', 'LWheel_7_W', 'LWheel_8_W', ...
        'RWheel_1_W', 'RWheel_2_W', 'RWheel_3_W', 'RWheel_4_W', ...
        'RWheel_5_W', 'RWheel_6_W', 'RWheel_7_W', 'RWheel_8_W', ...
        'AxleDis1', 'AxleDis2', 'AxleDis3', 'AxleDis4', 'AxleDis5', ...
        'AxleDis6', 'AxleDis7', 'Violation_Id', 'OverLoad_Sign', ...
        'Speed', 'Acceleration', 'Veh_Length', 'QAT', ...
        'License_Plate', 'License_Plate_Color', 'F7Code', ...
        'ExternInfo', 'Temp'};
    types = [{ ...
        'SQLINT', 'SQLTINYINT', 'SQLDATETIME', 'SQLCHAR', ...
        'SQLTINYINT', 'SQLTINYINT', 'SQLINT', 'SQLSMALLINT'}, ...
        repmat({'SQLINT'}, 1, 24), { ...
        'SQLTINYINT', 'SQLINT', 'SQLNUMERIC', 'SQLINT', 'SQLNUMERIC', ...
        'SQLNCHAR', 'SQLNCHAR', 'SQLNCHAR', 'SQLFLT4', 'SQLINT'}];
    prefixes = [0, 1, 1, 2, 1, 1, 1, 1, ones(1, 24), ...
        1, 1, 1, 1, 1, 2, 2, 2, 1, 1];
    lengths = [4, 1, 8, 10, 1, 1, 4, 2, ...
        repmat(4, 1, 24), 1, 4, 19, 4, 19, 24, 24, 112, 4, 4];

    spec = repmat(struct( ...
        'name', '', 'type', '', 'prefix', 0, 'len', 0, 'collation', '""'), ...
        numel(names), 1);
    for i = 1:numel(names)
        spec(i).name = names{i};
        spec(i).type = types{i};
        spec(i).prefix = prefixes(i);
        spec(i).len = lengths(i);
        if any(strcmp(types{i}, {'SQLCHAR', 'SQLNCHAR'}))
            spec(i).collation = 'Chinese_PRC_CI_AS';
        end
    end
end

function row = syntheticRow()
    row = cell(1, 42);
    row{1} = scalarBytes(int32(101));
    row{2} = scalarBytes(uint8(2));
    row{3} = sqlDateTimeBytes(2025, 12, 15, 12, 34, 56);
    row{4} = uint8('UP');
    row{5} = scalarBytes(uint8(2));
    row{6} = scalarBytes(uint8(2));
    row{7} = scalarBytes(int32(12000));
    row{8} = scalarBytes(int16(2));

    leftWheels = [3000, 3000, zeros(1, 6)];
    rightWheels = [3000, 3000, zeros(1, 6)];
    for i = 1:8
        row{8 + i} = scalarBytes(int32(leftWheels(i)));
        row{16 + i} = scalarBytes(int32(rightWheels(i)));
    end
    axleDistances = [4000, zeros(1, 6)];
    for i = 1:7
        row{24 + i} = scalarBytes(int32(axleDistances(i)));
    end

    row{32} = scalarBytes(int32(0));
    row{33} = scalarBytes(uint8(0));
    row{34} = scalarBytes(int32(60));
    row{35} = sqlNumericBytes(0, 19);
    row{36} = scalarBytes(int32(7500));
    row{37} = sqlNumericBytes(0, 19);
    row{38} = unicode2native('TEST0001', 'UTF-16LE');
    row{39} = unicode2native('BLUE', 'UTF-16LE');
    row{40} = unicode2native('SYNTHETIC', 'UTF-16LE');
    row{41} = scalarBytes(single(0));
    row{42} = scalarBytes(int32(20));
end

function writeFmt(path, spec)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    if fid < 0
        error('WIM:TestFixture:FmtOpen', 'Cannot create synthetic fmt: %s', path);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '9.0\r\n%d\r\n', numel(spec));
    for i = 1:numel(spec)
        fprintf(fid, '%d\t%s\t%d\t%d\t""\t%d\t%s\t%s\r\n', ...
            i, spec(i).type, spec(i).prefix, spec(i).len, i, ...
            spec(i).name, spec(i).collation);
    end
end

function writeBcp(path, spec, row)
    fid = fopen(path, 'w', 'ieee-le');
    if fid < 0
        error('WIM:TestFixture:BcpOpen', 'Cannot create synthetic bcp: %s', path);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    for i = 1:numel(spec)
        payload = uint8(row{i});
        if spec(i).prefix == 0
            if numel(payload) ~= spec(i).len
                error('WIM:TestFixture:FixedWidth', ...
                    'Synthetic field %s has %d bytes; expected %d.', ...
                    spec(i).name, numel(payload), spec(i).len);
            end
        else
            writePrefix(fid, spec(i).prefix, numel(payload));
        end
        fwrite(fid, payload, 'uint8');
    end
end

function writePrefix(fid, prefixLength, value)
    switch prefixLength
        case 1
            fwrite(fid, uint8(value), 'uint8');
        case 2
            fwrite(fid, uint16(value), 'uint16');
        case 4
            fwrite(fid, uint32(value), 'uint32');
        case 8
            fwrite(fid, uint64(value), 'uint64');
        otherwise
            error('WIM:TestFixture:Prefix', ...
                'Unsupported synthetic prefix length: %d', prefixLength);
    end
end

function bytes = scalarBytes(value)
    bytes = typecast(value, 'uint8');
end

function bytes = sqlDateTimeBytes(year, month, day, hour, minute, second)
    epoch = datenum(1900, 1, 1);
    value = datenum(year, month, day, hour, minute, second) - epoch;
    wholeDays = floor(value);
    ticks = round((value - wholeDays) * 86400 * 300);
    bytes = [scalarBytes(int32(wholeDays)), scalarBytes(int32(ticks))];
end

function bytes = sqlNumericBytes(value, width)
    magnitude = abs(round(double(value)));
    bytes = zeros(1, width, 'uint8');
    bytes(1) = uint8(value >= 0);
    for i = 2:width
        bytes(i) = uint8(mod(magnitude, 256));
        magnitude = floor(magnitude / 256);
    end
end
