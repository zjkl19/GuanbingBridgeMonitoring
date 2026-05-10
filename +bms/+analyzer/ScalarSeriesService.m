classdef ScalarSeriesService
    %SCALARSERIESSERVICE Shared helpers for scalar time-series analyzers.

    methods (Static)
        function args = resolveInputs(rootDir, pointIds, startDate, endDate, excelFile, subfolder, cfg, moduleKey, defaultExcelFile, defaultSubfolder)
            if nargin < 1 || isempty(rootDir), rootDir = pwd; end
            if nargin < 2 || isempty(pointIds), error('Please provide point_ids cell array.'); end
            if nargin < 3 || isempty(startDate), startDate = input('Start date (yyyy-MM-dd): ', 's'); end
            if nargin < 4 || isempty(endDate), endDate = input('End date (yyyy-MM-dd): ', 's'); end
            if nargin < 5 || isempty(excelFile), excelFile = defaultExcelFile; end
            if nargin < 7 || isempty(cfg), cfg = load_config(); end
            if nargin < 10 || isempty(defaultSubfolder), defaultSubfolder = '特征值'; end

            if nargin < 6 || isempty(subfolder)
                subfolder = bms.analyzer.ScalarSeriesService.subfolderFromConfig(cfg, moduleKey, defaultSubfolder);
            end

            args = struct();
            args.root_dir = rootDir;
            args.point_ids = cellstr(string(pointIds));
            args.start_date = bms.analyzer.ScalarSeriesService.normalizeDate(startDate);
            args.end_date = bms.analyzer.ScalarSeriesService.normalizeDate(endDate);
            args.excel_file = bms.data.DataLayoutResolver.resolveOutputPath(rootDir, excelFile, 'stats');
            args.subfolder = subfolder;
            args.cfg = cfg;
            args.style = bms.config.ConfigReader.getPlotStyle(cfg, moduleKey);
        end

        function subfolder = subfolderFromConfig(cfg, moduleKey, fallback)
            subfolder = fallback;
            if isstruct(cfg) && isfield(cfg, 'subfolders') && isstruct(cfg.subfolders) ...
                    && isfield(cfg.subfolders, moduleKey) && ~isempty(cfg.subfolders.(moduleKey))
                subfolder = cfg.subfolders.(moduleKey);
            end
        end

        function out = normalizeDate(value)
            if isa(value, 'datetime')
                out = datestr(value, 'yyyy-mm-dd');
                return;
            end
            if isstring(value)
                value = char(value);
            end
            out = value;
        end

        function range = dateRange(startDate, endDate)
            range = struct();
            range.start_date = bms.analyzer.ScalarSeriesService.normalizeDate(startDate);
            range.end_date = bms.analyzer.ScalarSeriesService.normalizeDate(endDate);
            range.dn0 = datenum(range.start_date, 'yyyy-mm-dd');
            range.dn1 = datenum(range.end_date, 'yyyy-mm-dd');
            if range.dn1 <= range.dn0
                range.dn1 = range.dn0 + 1;
            end
            range.dt0 = datetime(range.start_date, 'InputFormat', 'yyyy-MM-dd');
            range.dt1 = datetime(range.end_date, 'InputFormat', 'yyyy-MM-dd');
            if range.dt1 <= range.dt0
                range.dt1 = range.dt0 + days(1);
            end
        end

        function ticks = dateTicks(range, count)
            if nargin < 2 || isempty(count), count = 5; end
            ticks = datetime(linspace(range.dn0, range.dn1, count), 'ConvertFrom', 'datenum');
        end

        function values = finiteValues(values)
            values = values(isfinite(values));
        end

        function row = basicStatsRow(pointId, values, decimals)
            if nargin < 3 || isempty(decimals), decimals = 1; end
            values = bms.analyzer.ScalarSeriesService.finiteValues(values);
            if isempty(values)
                row = {pointId, NaN, NaN, NaN};
                return;
            end
            row = {pointId, min(values), max(values), round(mean(values), decimals)};
        end

        function T = basicStatsTable(rows)
            T = cell2table(rows, 'VariableNames', {'PointID', 'Min', 'Max', 'Mean'});
        end

        function value = styleField(style, field, defaultValue)
            value = bms.config.ConfigReader.getField(style, field, defaultValue);
        end

        function c = color(style, idx)
            c = [];
            if isfield(style, 'colors') && isnumeric(style.colors) && size(style.colors, 1) >= idx
                c = style.colors(idx, :);
            end
            if isempty(c)
                cmap = lines(3);
                c = cmap(idx, :);
            end
        end

        function applyYLim(style, pointId, defaultAuto)
            if nargin < 3, defaultAuto = false; end
            yl = bms.plot.PlotService.resolveNamedYLim( ...
                bms.analyzer.ScalarSeriesService.styleField(style, 'ylims', []), ...
                pointId, ...
                bms.analyzer.ScalarSeriesService.styleField(style, 'ylim', []));
            if bms.plot.PlotService.isValidYLim(yl)
                ylim(yl);
            elseif bms.config.ConfigReader.boolValue( ...
                    bms.analyzer.ScalarSeriesService.styleField(style, 'ylim_auto', defaultAuto), defaultAuto)
                ylim auto;
            elseif ~isempty(bms.analyzer.ScalarSeriesService.styleField(style, 'ylim', []))
                ylim(bms.analyzer.ScalarSeriesService.styleField(style, 'ylim', []));
            else
                ylim auto;
            end
        end

        function applyYLimAutoFirst(style, pointId, defaultAuto)
            if nargin < 3, defaultAuto = true; end
            if bms.config.ConfigReader.boolValue( ...
                    bms.analyzer.ScalarSeriesService.styleField(style, 'ylim_auto', defaultAuto), defaultAuto)
                ylim auto;
                return;
            end
            bms.analyzer.ScalarSeriesService.applyYLim(style, pointId, defaultAuto);
        end
    end
end
