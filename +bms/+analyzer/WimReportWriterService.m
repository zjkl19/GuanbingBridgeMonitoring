classdef WimReportWriterService
    %WIMREPORTWRITERSERVICE CSV and Excel output helpers for WIM reports.

    methods (Static)
        function csvPaths = writeCsvs(reports, outDir, yyyymm)
            csvPaths = struct();
            names = fieldnames(reports);
            for i = 1:numel(names)
                name = names{i};
                T = reports.(name);
                csvName = sprintf('%s_%s.csv', yyyymm, name);
                csvPath = fullfile(outDir, csvName);
                if istable(T)
                    writetable(T, csvPath, 'Encoding', 'UTF-8');
                else
                    writecell(T, csvPath, 'Encoding', 'UTF-8');
                end
                csvPaths.(name) = csvPath;
            end
        end

        function writeExcelFromCsvs(csvPaths, excelPath, bridge)
            if nargin < 3
                bridge = '';
            end
            names = fieldnames(csvPaths);
            if exist(excelPath, 'file')
                delete(excelPath);
            end
            for i = 1:numel(names)
                name = names{i};
                csvPath = csvPaths.(name);
                if ~exist(csvPath, 'file'), continue; end
                enc = bms.analyzer.WimSqlService.detectFileEncoding(csvPath);
                try
                    T = readtable(csvPath, 'TextType', 'string', 'Encoding', enc);
                    writetable(T, excelPath, 'Sheet', bms.analyzer.WimReportWriterService.safeSheetName(name));
                catch
                    C = readcell(csvPath, 'Encoding', enc);
                    writecell(C, excelPath, 'Sheet', bms.analyzer.WimReportWriterService.safeSheetName(name));
                end
            end

            if bms.analyzer.WimReportWriterService.shouldWriteTopNMetricSheets(bridge)
                bms.analyzer.WimReportWriterService.writeTopNMetricSheet(csvPaths, excelPath, 'TopN', 'TopN_m');
                bms.analyzer.WimReportWriterService.writeTopNMetricSheet(csvPaths, excelPath, 'TopN_MaxAxle', 'TopN_MaxAxle_m');
            end
        end

        function s = safeSheetName(name)
            s = regexprep(name, '[:\\/\?\*\[\]]', '_');
            if numel(s) > 31
                s = s(1:31);
            end
        end

        function tf = shouldWriteTopNMetricSheets(bridge)
            if isstring(bridge), bridge = char(bridge); end
            tf = ischar(bridge) && strcmpi(strtrim(bridge), 'hongtang');
        end

        function writeTopNMetricSheet(csvPaths, excelPath, srcName, dstName)
            if ~isfield(csvPaths, srcName), return; end
            csvPath = csvPaths.(srcName);
            if ~exist(csvPath, 'file'), return; end

            enc = bms.analyzer.WimSqlService.detectFileEncoding(csvPath);
            try
                T = readtable(csvPath, 'TextType', 'string', 'Encoding', enc);
            catch
                return;
            end

            Tm = bms.analyzer.WimReportTableService.convertAxleDistancesMmToM(T);
            writetable(Tm, excelPath, 'Sheet', bms.analyzer.WimReportWriterService.safeSheetName(dstName));
        end
    end
end
