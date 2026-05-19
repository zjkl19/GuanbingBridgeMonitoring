classdef TimeSeriesRangeLoader
    %TIMESERIESRANGELOADER Orchestrates vendor-aware range loading and cleaning.

    methods (Static)
        function [times, vals, meta] = load(rootDir, subfolder, pointId, startDate, endDate, cfg, sensorType)
            if nargin < 7 || isempty(sensorType)
                sensorType = 'generic';
            end
            if nargin < 6 || isempty(cfg)
                cfg = load_config();
            end

            meta = struct();
            meta.files = {};

            dateList = bms.data.TimeSeriesRangeLoader.buildDateList(startDate, endDate);
            [rangeStart, rangeEnd] = bms.data.TimeRangeResolver.closedRange(startDate, endDate);
            range = struct('start', rangeStart, 'end', rangeEnd);

            loader = bms.data.TimeSeriesRangeLoader.vendorLoader(cfg);
            rules = bms.data.CleaningPipeline.resolveRules(cfg, sensorType, pointId);
            meta.applied_rules = rules;

            [allT, allV, meta, usedRangeLoader] = bms.data.TimeSeriesRangeLoader.tryReadRange( ...
                loader, rootDir, subfolder, pointId, sensorType, range, meta);
            if ~usedRangeLoader
                [allT, allV, meta] = bms.data.TimeSeriesRangeLoader.readByDay( ...
                    loader, rootDir, subfolder, pointId, sensorType, range, dateList, meta);
            end

            if isempty(allT)
                times = [];
                vals = [];
                return;
            end

            [times, vals] = bms.data.TimeSeriesRangeLoader.sortSeries(allT, allV);
            [vals, meta] = bms.data.TimeSeriesRangeLoader.applyCleaning(vals, times, rules, sensorType, pointId, meta);
        end

        function [allT, allV, meta, used] = tryReadRange(loader, rootDir, subfolder, pointId, sensorType, range, meta)
            allT = [];
            allV = [];
            used = false;
            if ~isfield(loader, 'read_range') || ~isa(loader.read_range, 'function_handle')
                return;
            end

            [t, v, used, files] = loader.read_range(rootDir, subfolder, pointId, sensorType, range);
            if ~used
                return;
            end
            if ~isempty(files)
                meta.files = files;
            end
            if ~isempty(v)
                allT = [allT; t]; %#ok<AGROW>
                allV = [allV; v]; %#ok<AGROW>
            end
        end

        function [allT, allV, meta] = readByDay(loader, rootDir, subfolder, pointId, sensorType, range, dateList, meta)
            allT = [];
            allV = [];
            for i = 1:numel(dateList)
                day = dateList{i};
                dayMeta = struct('day', day, 'range', range);
                [dirp, dayMeta] = bms.data.TimeSeriesRangeLoader.resolveDayDir( ...
                    loader, rootDir, day, subfolder, sensorType, dayMeta);
                if isempty(dirp), continue; end

                fp = loader.find_file(dirp, pointId, sensorType, day, dayMeta);
                if isempty(fp), continue; end

                [t, v] = loader.read_file(fp, sensorType, pointId, day, dayMeta);
                if isempty(v), continue; end
                meta.files{end+1} = fp; %#ok<AGROW>
                allT = [allT; t]; %#ok<AGROW>
                allV = [allV; v]; %#ok<AGROW>
            end
        end

        function [dirp, dayMeta] = resolveDayDir(loader, rootDir, day, subfolder, sensorType, dayMeta)
            if isfield(loader, 'get_day_dir')
                [dirp, dayMeta] = loader.get_day_dir(rootDir, day, subfolder, sensorType, dayMeta);
                return;
            end
            dirp = fullfile(rootDir, day, subfolder);
            if ~exist(dirp, 'dir')
                dirp = '';
            end
        end

        function [times, vals] = sortSeries(allT, allV)
            [times, order] = sort(allT);
            vals = allV(order);
        end

        function [vals, meta] = applyCleaning(vals, times, rules, sensorType, pointId, meta)
            [vals, cleanLog] = bms.data.CleaningPipeline.apply(vals, times, rules, struct( ...
                'record_offset', true, ...
                'sensor_type', sensorType, ...
                'point_id', pointId, ...
                'files', {meta.files}));
            meta.cleaning_log = cleanLog;
            meta.applied_offset_correction = cleanLog.offset_correction;
        end

        function loader = vendorLoader(cfg)
            vendor = 'default';
            if isstruct(cfg) && isfield(cfg, 'vendor') && ~isempty(cfg.vendor)
                vendor = lower(string(cfg.vendor));
            end
            switch vendor
                case {'donghua'}
                    loader = bms.data.TimeSeriesRangeLoader.donghuaLoader(cfg);
                case {'hongtang'}
                    loader = bms.data.TimeSeriesRangeLoader.hongtangLoader(cfg);
                case {'jiulongjiang', 'jiulong', 'shuixianhua', 'sxh'}
                    loader = bms.data.TimeSeriesRangeLoader.jiulongjiangLoader(cfg);
                otherwise
                    loader = bms.data.TimeSeriesRangeLoader.donghuaLoader(cfg);
            end
        end

        function loader = donghuaLoader(cfg)
            loader.get_day_dir = @(rootDir, day, subfolder, sensorType, meta) ...
                bms.data.TimeSeriesRangeLoader.dataSourceDayDir(rootDir, day, subfolder, cfg, meta);
            loader.find_file = @(dirp, pointId, sensorType, varargin) ...
                bms.data.TimeSeriesLoader.findCsvForPoint(dirp, pointId, cfg, sensorType);
            loader.read_file = @(fp, sensorType, varargin) ...
                bms.data.TimeSeriesLoader.readCachedCsvSeries(fp, bms.data.TimeSeriesRangeLoader.defaultHeaderMarker(cfg)); %#ok<NASGU>
        end

        function loader = hongtangLoader(cfg)
            loader = bms.data.TimeSeriesRangeLoader.donghuaLoader(cfg);
            loader.read_range = @(rootDir, subfolder, pointId, sensorType, range) ...
                bms.data.HongtangLowFreqDataSource.readRange(rootDir, pointId, sensorType, range, cfg);
        end

        function loader = jiulongjiangLoader(cfg)
            loader.get_day_dir = @(rootDir, day, subfolder, sensorType, meta) ...
                bms.data.JiulongjiangCsvDataSource.getDayDir(rootDir, day, cfg, meta);
            loader.find_file = @(dirp, pointId, sensorType, varargin) ...
                bms.data.JiulongjiangCsvDataSource.findFile(dirp, pointId, sensorType, cfg);
            loader.read_file = @(fp, sensorType, pointId, varargin) ...
                bms.data.JiulongjiangCsvDataSource.readFile(fp, sensorType, pointId, cfg, varargin{:});
        end

        function marker = defaultHeaderMarker(cfg)
            marker = '[绝对时间]';
            if isstruct(cfg) && isfield(cfg, 'defaults') && isstruct(cfg.defaults) ...
                    && isfield(cfg.defaults, 'header_marker') && ~isempty(cfg.defaults.header_marker)
                marker = cfg.defaults.header_marker;
            end
        end

        function [dirp, meta] = dataSourceDayDir(rootDir, day, subfolder, cfg, meta)
            dirp = '';
            if nargin < 5 || isempty(meta)
                meta = struct();
            end
            if isempty(rootDir) || ~exist(rootDir, 'dir')
                return;
            end
            try
                src = bms.data.DataSourceFactory.create(rootDir, cfg);
                dirs = src.candidateDirs(subfolder, day, day);
                meta.data_source = class(src);
                meta.candidate_dirs = dirs;
                if ~isempty(dirs)
                    dirp = dirs{1};
                end
            catch
                dirp = fullfile(rootDir, day, subfolder);
                if ~exist(dirp, 'dir')
                    dirp = '';
                end
            end
        end

        function list = buildDateList(startDate, endDate)
            daysList = bms.data.TimeRangeResolver.daysBetween(startDate, endDate);
            list = cell(numel(daysList), 1);
            for i = 1:numel(daysList)
                list{i} = datestr(daysList(i), 'yyyy-mm-dd');
            end
        end
    end
end
