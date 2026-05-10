classdef WimJiulongjiangExcelSource
    %WIMJIULONGJIANGEXCELSOURCE Adapter for Jiulongjiang WIM Excel exports.

    methods (Static)
        function [parsed, tbl] = readRecords(filePath)
            tbl = readtable(filePath, 'VariableNamingRule', 'preserve');
            parsed = bms.analyzer.WimJiulongjiangExcelSource.parseTable(tbl);
        end

        function parsed = parseTable(tbl)
            cols = bms.analyzer.WimJiulongjiangExcelSource.resolveColumns(tbl);
            n = height(tbl);

            parsed = struct();
            parsed.headers = tbl.Properties.VariableNames;
            parsed.columns = cols;
            parsed.time_datenum = bms.analyzer.WimJiulongjiangExcelSource.timeColumn(tbl, cols.time);
            parsed.lane = bms.analyzer.WimJiulongjiangExcelSource.resolveLane(tbl, cols);
            parsed.gross = bms.analyzer.WimJiulongjiangExcelSource.numericColumn(tbl, cols.gross, n);
            parsed.speed = bms.analyzer.WimJiulongjiangExcelSource.numericColumn(tbl, cols.speed, n);
            parsed.axle_num = bms.analyzer.WimJiulongjiangExcelSource.numericColumn(tbl, cols.axle_num, n);
            parsed.axle_weights = bms.analyzer.WimJiulongjiangExcelSource.axleMatrix(tbl, cols.axle_weights);
            parsed.axle_distances = bms.analyzer.WimJiulongjiangExcelSource.axleMatrix(tbl, cols.axle_dists);
            parsed.plate = bms.analyzer.WimJiulongjiangExcelSource.plateColumn(tbl, cols);
        end

        function [normCsv, rawCsv, meta] = buildStage(files, stageDir)
            normCsv = fullfile(stageDir, 'jiulongjiang_norm.tsv');
            rawCsv = fullfile(stageDir, 'jiulongjiang_raw.tsv');
            if exist(normCsv, 'file'), delete(normCsv); end
            if exist(rawCsv, 'file'), delete(rawCsv); end

            meta = bms.analyzer.WimJiulongjiangExcelSource.emptyStageMeta();
            rowOffset = 0;
            for fi = 1:numel(files)
                [parsed, tbl] = bms.analyzer.WimJiulongjiangExcelSource.readRecords(files{fi});
                if isempty(tbl), continue; end

                meta = bms.analyzer.WimJiulongjiangExcelSource.updateStageMeta(meta, tbl, parsed);
                Tnorm = bms.analyzer.WimJiulongjiangExcelSource.normalizedTable(parsed, rowOffset);
                rowOffset = rowOffset + height(tbl);

                bms.analyzer.WimJiulongjiangExcelSource.writeTsv(rawCsv, tbl, fi == 1);
                bms.analyzer.WimJiulongjiangExcelSource.writeTsv(normCsv, Tnorm, fi == 1);
            end
        end

        function meta = emptyStageMeta()
            meta = struct();
            meta.headers = {};
            meta.axle_cols = {};
            meta.time_col = '';
        end

        function meta = updateStageMeta(meta, tbl, parsed)
            if isempty(meta.headers)
                meta.headers = tbl.Properties.VariableNames;
            end

            cols = parsed.columns;
            if isempty(meta.time_col) && ~isempty(cols.time)
                meta.time_col = tbl.Properties.VariableNames{cols.time};
            end
            if isempty(meta.axle_cols)
                idxs = cols.axle_weights;
                idxs = idxs(idxs > 0);
                if ~isempty(idxs)
                    meta.axle_cols = tbl.Properties.VariableNames(idxs);
                end
            end
        end

        function Tnorm = normalizedTable(parsed, rowOffset)
            if nargin < 2
                rowOffset = 0;
            end

            n = numel(parsed.time_datenum);
            ids = (1:n).' + rowOffset;
            dt = datetime(parsed.time_datenum, 'ConvertFrom', 'datenum');
            dt.Format = 'yyyy-MM-dd HH:mm:ss.SSS';

            L = parsed.axle_weights;
            R = zeros(size(L));
            D = parsed.axle_distances;

            Tnorm = table(ids, parsed.lane, dt, parsed.axle_num, parsed.gross, parsed.speed, parsed.plate, ...
                L(:,1), L(:,2), L(:,3), L(:,4), L(:,5), L(:,6), L(:,7), L(:,8), ...
                R(:,1), R(:,2), R(:,3), R(:,4), R(:,5), R(:,6), R(:,7), R(:,8), ...
                D(:,1), D(:,2), D(:,3), D(:,4), D(:,5), D(:,6), D(:,7), ...
                'VariableNames', {'HSData_Id','Lane_Id','HSData_DT','Axle_Num','Gross_Load','Speed','License_Plate', ...
                'LWheel_1_W','LWheel_2_W','LWheel_3_W','LWheel_4_W','LWheel_5_W','LWheel_6_W','LWheel_7_W','LWheel_8_W', ...
                'RWheel_1_W','RWheel_2_W','RWheel_3_W','RWheel_4_W','RWheel_5_W','RWheel_6_W','RWheel_7_W','RWheel_8_W', ...
                'AxleDis1','AxleDis2','AxleDis3','AxleDis4','AxleDis5','AxleDis6','AxleDis7'});
        end

        function cols = resolveColumns(tbl)
            names = tbl.Properties.VariableNames;
            cols = struct();
            cols.time = bms.analyzer.WimJiulongjiangExcelSource.findColumn(names, {'采集时间','时间','日期'});
            cols.lane_id = bms.analyzer.WimJiulongjiangExcelSource.findColumn(names, {'车道号','车道编号'});
            cols.lane_text = bms.analyzer.WimJiulongjiangExcelSource.findColumn(names, {'车道'});
            cols.speed = bms.analyzer.WimJiulongjiangExcelSource.findColumn(names, {'车速','车速(Km/h)','车速(km/h)'});
            cols.gross = bms.analyzer.WimJiulongjiangExcelSource.findColumn(names, {'总重','总重(kg)'});
            cols.axle_num = bms.analyzer.WimJiulongjiangExcelSource.findColumn(names, {'轴数','轴数(个)'});
            cols.plate = bms.analyzer.WimJiulongjiangExcelSource.findColumn(names, {'车牌号'});
            cols.axle_weights = bms.analyzer.WimJiulongjiangExcelSource.findSeriesColumns(names, '轴重', 8);
            cols.axle_dists = bms.analyzer.WimJiulongjiangExcelSource.findSeriesColumns(names, '轴距', 7);
        end

        function idx = findColumn(names, candidates)
            idx = [];
            for i = 1:numel(candidates)
                c = candidates{i};
                hit = find(strcmp(names, c), 1);
                if ~isempty(hit)
                    idx = hit;
                    return;
                end
            end
            for i = 1:numel(candidates)
                c = candidates{i};
                hit = find(contains(names, c), 1);
                if ~isempty(hit)
                    idx = hit;
                    return;
                end
            end
        end

        function idxs = findSeriesColumns(names, prefix, nmax)
            idxs = zeros(1, nmax);
            for k = 1:nmax
                pat = sprintf('%s%d', prefix, k);
                hit = find(contains(names, pat), 1);
                if ~isempty(hit)
                    idxs(k) = hit;
                end
            end
        end

        function tDatenum = timeColumn(tbl, idx)
            if isempty(idx)
                tDatenum = NaN(height(tbl), 1);
                return;
            end
            tDatenum = bms.analyzer.WimJiulongjiangExcelSource.toDatenum(tbl{:, idx});
        end

        function tDatenum = toDatenum(col)
            if isdatetime(col)
                tDatenum = datenum(col);
            else
                try
                    tDatenum = datenum(col);
                catch
                    tDatenum = datenum(datetime(col, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS'));
                end
            end
        end

        function values = numericColumn(tbl, idx, n)
            if isempty(idx)
                values = NaN(n, 1);
                return;
            end
            values = bms.analyzer.WimJiulongjiangExcelSource.toDouble(tbl{:, idx});
        end

        function lane = resolveLane(tbl, cols)
            n = height(tbl);
            lane = NaN(n, 1);
            if ~isempty(cols.lane_text)
                lane = bms.analyzer.WimJiulongjiangExcelSource.parseLaneText(tbl{:, cols.lane_text});
                if any(isfinite(lane))
                    return;
                end
            end
            if ~isempty(cols.lane_id)
                lane = bms.analyzer.WimJiulongjiangExcelSource.toDouble(tbl{:, cols.lane_id});
            end
        end

        function lane = parseLaneText(col)
            n = numel(col);
            lane = NaN(n, 1);
            for i = 1:n
                s = string(col(i));
                d = regexp(s, '\d+', 'match');
                if ~isempty(d)
                    lane(i) = str2double(d{1});
                end
            end
        end

        function plate = plateColumn(tbl, cols)
            n = height(tbl);
            plate = repmat({''}, n, 1);
            if isempty(cols.plate)
                return;
            end

            raw = tbl{:, cols.plate};
            for i = 1:n
                plate{i} = char(string(raw(i)));
            end
        end

        function values = toDouble(x)
            values = NaN(size(x));
            if iscell(x)
                for i = 1:numel(x)
                    values(i) = str2double(string(x{i}));
                end
            elseif isstring(x) || ischar(x)
                values = str2double(string(x));
            else
                values = double(x);
            end
        end

        function values = axleMatrix(tbl, idxs)
            n = height(tbl);
            values = zeros(n, numel(idxs));
            for k = 1:numel(idxs)
                if idxs(k) > 0
                    values(:, k) = bms.analyzer.WimJiulongjiangExcelSource.toDouble(tbl{:, idxs(k)});
                end
            end
        end

        function writeTsv(path, T, writeHeader)
            if nargin < 3
                writeHeader = true;
            end
            if writeHeader
                writetable(T, path, 'FileType', 'text', 'Delimiter', '\t', 'Encoding', 'UTF-8');
            else
                writetable(T, path, 'FileType', 'text', 'Delimiter', '\t', 'Encoding', 'UTF-8', ...
                    'WriteMode', 'append', 'WriteVariableNames', false);
            end
        end
    end
end
