classdef DynamicStrainBoxplotService
    %DYNAMICSTRAINBOXPLOTSERVICE Shared boxplot/stat helpers for dynamic strain.

    methods (Static)
        function plotMat = sampleBoxplotMatrix(dataMat, maxPointsPerSeries)
            if nargin < 2 || isempty(maxPointsPerSeries) || ~isscalar(maxPointsPerSeries) || ...
                    ~isfinite(maxPointsPerSeries) || maxPointsPerSeries < 1000
                maxPointsPerSeries = 50000;
            end
            maxPointsPerSeries = round(maxPointsPerSeries);

            nCols = size(dataMat, 2);
            keepCols = cell(nCols, 1);
            maxLen = 0;
            for c = 1:nCols
                v = dataMat(:, c);
                v = v(isfinite(v));
                if numel(v) > maxPointsPerSeries
                    idx = unique(round(linspace(1, numel(v), maxPointsPerSeries)), 'stable');
                    v = v(idx);
                end
                keepCols{c} = v;
                maxLen = max(maxLen, numel(v));
            end

            plotMat = NaN(maxLen, nCols);
            for c = 1:nCols
                v = keepCols{c};
                plotMat(1:numel(v), c) = v;
            end
        end

        function T = statsTable(dataMat, labels)
            n = numel(labels);
            mins = NaN(n, 1);
            q1s = NaN(n, 1);
            meds = NaN(n, 1);
            q3s = NaN(n, 1);
            maxs = NaN(n, 1);
            means = NaN(n, 1);
            stds = NaN(n, 1);
            cnts = NaN(n, 1);

            for k = 1:n
                v = dataMat(:, k);
                v = v(isfinite(v));
                if isempty(v)
                    continue;
                end
                mins(k) = min(v);
                q1s(k) = quantile(v, 0.25);
                meds(k) = quantile(v, 0.50);
                q3s(k) = quantile(v, 0.75);
                maxs(k) = max(v);
                means(k) = mean(v);
                stds(k) = std(v);
                cnts(k) = numel(v);
            end

            T = table(labels(:), mins, q1s, meds, q3s, maxs, means, stds, cnts, ...
                'VariableNames', {'PointID', 'Min', 'Q1', 'Median', 'Q3', 'Max', 'Mean', 'Std', 'Count'});
        end
    end
end
