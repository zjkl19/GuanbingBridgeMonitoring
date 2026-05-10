classdef WimAccumulatorService
    %WIMACCUMULATORSERVICE Shared accumulator helpers for WIM reports.

    methods (Static)
        function topn = initTopN(n)
            topn.n = n;
            topn.values = -inf(n, 1);
            topn.times = inf(n, 1);
            topn.std_rows = cell(n, 1);
            topn.raw_rows = cell(n, 1);
        end

        function idx = findBin(value, edges)
            if ~isfinite(value)
                idx = 0;
                return;
            end

            n = numel(edges) - 1;
            for i = 1:n
                lo = edges(i);
                hi = edges(i + 1);
                if i == n
                    if value >= lo
                        idx = i;
                        return;
                    end
                else
                    if value >= lo && value < hi
                        idx = i;
                        return;
                    end
                end
            end
            idx = 0;
        end

        function ok = qualifiesForTopN(topn, key, timeDatenum)
            ok = false;
            if ~isfinite(key)
                return;
            end

            minValue = topn.values(end);
            if key > minValue
                ok = true;
            elseif key == minValue && timeDatenum < topn.times(end)
                ok = true;
            end
        end

        function topn = updateTopN(topn, key, timeDatenum, stdRow, rawRow)
            if ~isfinite(key)
                return;
            end

            idx = bms.analyzer.WimAccumulatorService.findInsertIndex(topn, key, timeDatenum);
            if isempty(idx)
                return;
            end
            if idx < topn.n
                topn.values(idx+1:end) = topn.values(idx:end-1);
                topn.times(idx+1:end) = topn.times(idx:end-1);
                topn.std_rows(idx+1:end) = topn.std_rows(idx:end-1);
                topn.raw_rows(idx+1:end) = topn.raw_rows(idx:end-1);
            end
            topn.values(idx) = key;
            topn.times(idx) = timeDatenum;
            topn.std_rows{idx} = stdRow;
            topn.raw_rows{idx} = rawRow;
        end

        function idx = findInsertIndex(topn, key, timeDatenum)
            idx = [];
            for i = 1:topn.n
                if key > topn.values(i)
                    idx = i;
                    return;
                elseif key == topn.values(i) && timeDatenum < topn.times(i)
                    idx = i;
                    return;
                end
            end
        end

        function row = standardRow(lane, timeDatenum, axleNum, gross, speed, plate, axleWeights, axleDistances)
            timeString = datestr(timeDatenum, 'yyyy-mm-dd HH:MM:SS');
            row = [{lane, timeString, axleNum, gross, speed, plate}, num2cell(axleWeights), num2cell(axleDistances)];
        end
    end
end
