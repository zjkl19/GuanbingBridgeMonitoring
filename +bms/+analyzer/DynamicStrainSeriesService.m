classdef DynamicStrainSeriesService
    %DYNAMICSTRAINSERIESSERVICE Data collection for dynamic strain boxplots.

    methods (Static)
        function [dataMat, labels, tsList] = collectGroupData(rootDir, subfolder, startStr, endStr, pointIds, ds, cfg, spec)
            n = numel(pointIds);
            colData = cell(n, 1);
            labels = pointIds(:).';
            tsList = struct('pid', cell(n, 1), 'times', [], 'vals', []);
            for i = 1:n
                bms.app.StopController.throwIfRequested('Stop requested before next dynamic strain point');
                pid = pointIds{i};
                fprintf('  -> 读取 %s ...\n', pid);
                [values, times] = bms.analyzer.DynamicStrainBoxplotService.processPoint( ...
                    rootDir, subfolder, startStr, endStr, pid, ds, cfg, spec.mode);
                colData{i} = values(:);
                tsList(i).pid = pid;
                tsList(i).times = times(:);
                tsList(i).vals = values(:);
                fprintf('    样本数(非NaN): %d\n', nnz(~isnan(values)));
            end

            maxLen = max(cellfun(@numel, colData));
            dataMat = NaN(maxLen, n);
            for i = 1:n
                values = colData{i};
                dataMat(1:numel(values), i) = values;
            end
        end
    end
end
