classdef LargeCsvService
    %LARGECSVSERVICE Helpers for legacy large CSV utilities.

    methods (Static)
        function values = extractTimeRange(filePath, startTime, endTime)
            values = [];
            t0 = bms.data.LargeCsvService.parseTime(startTime);
            t1 = bms.data.LargeCsvService.parseTime(endTime);

            fid = fopen(filePath, 'r');
            if fid == -1
                error('LargeCsvService:OpenFailed', 'Cannot open file: %s', filePath);
            end
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

            bms.data.LargeCsvService.skipFirstNonEmptyLine(fid);
            while ~feof(fid)
                line = fgetl(fid);
                if ~ischar(line) || isempty(strtrim(line))
                    continue;
                end
                [ok, timestamp, value] = bms.data.LargeCsvService.parseDataLine(line);
                if ok && timestamp >= t0 && timestamp <= t1
                    values(end+1, 1) = value; %#ok<AGROW>
                end
            end
        end

        function data = readWithHeader(filePath, marker)
            if nargin < 2 || isempty(marker)
                marker = '[绝对时间]';
            end
            if ~isfile(filePath)
                error('LargeCsvService:MissingFile', 'File does not exist: %s', filePath);
            end

            lineNum = bms.data.LargeCsvService.findHeaderLine(filePath, marker);
            opts = detectImportOptions(filePath, 'NumHeaderLines', lineNum - 1);
            data = readtable(filePath, opts);
        end

        function lineNum = findHeaderLine(filePath, marker)
            fid = fopen(filePath, 'r');
            if fid == -1
                error('LargeCsvService:OpenFailed', 'Cannot open file: %s', filePath);
            end
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

            lineNum = 0;
            while ~feof(fid)
                line = fgetl(fid);
                lineNum = lineNum + 1;
                if ischar(line) && contains(line, marker)
                    return;
                end
            end
            error('LargeCsvService:HeaderNotFound', ...
                'Header marker "%s" not found in file: %s', marker, filePath);
        end

        function [startDate, endDate] = dateRangeLargeFile(filePath)
            if ~isfile(filePath)
                error('LargeCsvService:MissingFile', 'File does not exist: %s', filePath);
            end

            startDate = bms.data.LargeCsvService.firstTimestampText(filePath);
            endDate = bms.data.LargeCsvService.lastTimestampText(filePath);
        end

        function text = firstTimestampText(filePath)
            fid = fopen(filePath, 'r');
            if fid == -1
                error('LargeCsvService:OpenFailed', 'Cannot open file: %s', filePath);
            end
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

            text = '';
            while ~feof(fid)
                line = fgetl(fid);
                if ~ischar(line) || isempty(strtrim(line))
                    continue;
                end
                [ok, timestampText] = bms.data.LargeCsvService.parseTimestampText(line);
                if ok
                    text = timestampText;
                    return;
                end
            end
            error('LargeCsvService:NoStartDate', 'No valid start timestamp found in file: %s', filePath);
        end

        function text = lastTimestampText(filePath)
            lines = bms.data.LargeCsvService.tailLines(filePath, 8192);
            text = '';
            for i = numel(lines):-1:1
                [ok, timestampText] = bms.data.LargeCsvService.parseTimestampText(lines{i});
                if ok
                    text = timestampText;
                    return;
                end
            end
            error('LargeCsvService:NoEndDate', 'No valid end timestamp found in file: %s', filePath);
        end

        function lines = tailLines(filePath, blockSize)
            if nargin < 2 || isempty(blockSize)
                blockSize = 8192;
            end
            info = dir(filePath);
            readSize = min(blockSize, max(info.bytes, 0));

            fid = fopen(filePath, 'r');
            if fid == -1
                error('LargeCsvService:OpenFailed', 'Cannot open file: %s', filePath);
            end
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

            if readSize <= 0
                lines = {};
                return;
            end
            fseek(fid, -readSize, 'eof');
            dataBlock = fread(fid, readSize, '*char')';
            lines = regexp(dataBlock, '\r\n|\n|\r', 'split');
            lines = lines(~cellfun(@(s) isempty(strtrim(s)), lines));
        end

        function skipFirstNonEmptyLine(fid)
            while ~feof(fid)
                line = fgetl(fid);
                if ischar(line) && ~isempty(strtrim(line))
                    return;
                end
            end
        end

        function [ok, timestamp, value] = parseDataLine(line)
            ok = false;
            timestamp = NaT;
            value = NaN;
            row = strsplit(line, ',');
            if numel(row) < 2
                return;
            end
            try
                timestamp = bms.data.LargeCsvService.parseTime(row{1});
                value = str2double(row{2});
                ok = isfinite(value);
            catch
                ok = false;
            end
        end

        function [ok, timestampText] = parseTimestampText(line)
            ok = false;
            timestampText = '';
            if ~ischar(line) || isempty(strtrim(line))
                return;
            end
            row = strsplit(line, ',');
            if isempty(row)
                return;
            end
            timestampText = strtrim(row{1});
            try
                bms.data.LargeCsvService.parseTime(timestampText);
                ok = true;
            catch
                ok = false;
            end
        end

        function t = parseTime(value)
            if isdatetime(value)
                t = value;
            else
                t = datetime(strtrim(char(string(value))), 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
            end
        end
    end
end
