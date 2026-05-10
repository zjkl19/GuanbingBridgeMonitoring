classdef StructuralFilteredSeriesPipeline
    %STRUCTURALFILTEREDSERIESPIPELINE Shared raw/filtered structural workflow.

    methods (Static)
        function run(kind, rootDir, startDate, endDate, excelFile, subfolder, cfg)
            if nargin < 1 || isempty(kind), kind = 'deflection'; end
            spec = bms.analyzer.StructuralFilteredSeriesPipeline.spec(kind);

            if nargin < 2 || isempty(rootDir), rootDir = pwd; end
            if nargin < 7 || isempty(cfg), cfg = load_config(); end
            if nargin < 3 || isempty(startDate)
                if spec.promptForDates
                    startDate = input('开始日期(yyyy-MM-dd): ', 's');
                else
                    error('start_date is required');
                end
            end
            if nargin < 4 || isempty(endDate)
                if spec.promptForDates
                    endDate = input('结束日期 (yyyy-MM-dd): ', 's');
                else
                    error('end_date is required');
                end
            end
            if nargin < 5 || isempty(excelFile), excelFile = spec.defaultExcel; end
            if nargin < 6 || isempty(subfolder)
                subfolder = bms.analyzer.StructuralFilteredSeriesPipeline.resolveSubfolder(cfg, spec);
            end

            rootDir = char(rootDir);
            excelFile = resolve_data_output_path(rootDir, excelFile, 'stats');
            style = bms.analyzer.StructuralFilteredSeriesPipeline.resolveStyle(cfg, spec);

            switch spec.moduleKey
                case 'deflection'
                    rows = bms.analyzer.StructuralFilteredSeriesPipeline.runDeflection( ...
                        rootDir, startDate, endDate, subfolder, cfg, style, spec);
                case 'bearing_displacement'
                    rows = bms.analyzer.StructuralFilteredSeriesPipeline.runBearingDisplacement( ...
                        rootDir, startDate, endDate, subfolder, cfg, style, spec);
                otherwise
                    error('StructuralFilteredSeriesPipeline:UnsupportedKind', ...
                        'Unsupported filtered structural kind: %s', spec.moduleKey);
            end

            T = bms.analyzer.StructuralSeriesService.filteredStatsTable(rows);
            bms.io.StatsWriter.writeModuleTableChecked(T, excelFile, spec.moduleKey);
            fprintf('%s\n', sprintf(spec.doneMessage, excelFile));
        end

        function spec = spec(kind)
            kind = lower(char(string(kind)));
            switch kind
                case 'deflection'
                    spec.moduleKey = 'deflection';
                    spec.sensorType = 'deflection';
                    spec.pointKey = 'deflection';
                    spec.groupKey = 'deflection';
                    spec.styleKey = 'deflection';
                    spec.fallbackStyleKey = '';
                    spec.defaultExcel = 'deflection_stats.xlsx';
                    spec.subfolderKeys = {'deflection'};
                    spec.defaultSubfolder = '特征值_重采样';
                    spec.defaultOutputDir = '时程曲线_挠度';
                    spec.defaultYLabel = '挠度 (mm)';
                    spec.defaultTitlePrefix = '挠度时程';
                    spec.filePrefix = 'Defl';
                    spec.decimals = 1;
                    spec.promptForDates = true;
                    spec.doneMessage = '挠度统计已保存至 %s';
                    spec.emptyPointWarning = 'Point %s has no data, skip';
                    spec.groupMessage = '处理组 %d: %s\n';
                    spec.groupTitlePattern = '%s 组%d%s';
                    spec.pointTitlePattern = '%s %s%s';
                case 'bearing_displacement'
                    spec.moduleKey = 'bearing_displacement';
                    spec.sensorType = 'bearing_displacement';
                    spec.pointKey = 'bearing_displacement';
                    spec.groupKey = 'bearing_displacement';
                    spec.styleKey = 'bearing_displacement';
                    spec.fallbackStyleKey = 'deflection';
                    spec.defaultExcel = 'bearing_displacement_stats.xlsx';
                    spec.subfolderKeys = {'bearing_displacement', 'deflection'};
                    spec.defaultSubfolder = '';
                    spec.defaultOutputDir = '时程曲线_支座位移';
                    spec.defaultYLabel = 'Bearing displacement (mm)';
                    spec.defaultTitlePrefix = 'Bearing displacement';
                    spec.filePrefix = 'BearingDisp';
                    spec.decimals = 3;
                    spec.promptForDates = false;
                    spec.doneMessage = 'Bearing displacement stats saved to %s';
                    spec.emptyPointWarning = 'Bearing displacement point %s has no data, skip';
                    spec.groupMessage = '';
                    spec.groupTitlePattern = '%s %s %s';
                    spec.pointTitlePattern = '%s %s %s';
                otherwise
                    error('StructuralFilteredSeriesPipeline:UnsupportedKind', ...
                        'Unsupported filtered structural kind: %s', kind);
            end
        end

        function rows = runDeflection(rootDir, startDate, endDate, subfolder, cfg, style, spec)
            rows = cell(0, 7);
            groups = bms.analyzer.StructuralFilteredSeriesPipeline.deflectionGroups(cfg, spec);

            if bms.analyzer.StructuralPlotConfigService.isJiulongjiang(cfg)
                points = bms.analyzer.StructuralPlotConfigService.getPointsOrFlattenFallback(cfg, spec.pointKey, groups);
                collectStats = isempty(groups);
                for i = 1:numel(points)
                    pid = points{i};
                    fprintf('Per-point deflection: %s ...\n', pid);
                    rec = bms.analyzer.StructuralFilteredSeriesPipeline.loadFilteredPoint( ...
                        rootDir, subfolder, pid, startDate, endDate, cfg, spec);
                    if ~rec.hasData
                        warning(spec.emptyPointWarning, pid);
                        continue;
                    end
                    if collectStats
                        rows(end+1, :) = bms.analyzer.StructuralFilteredSeriesPipeline.statsRow(rec, spec); %#ok<AGROW>
                    end
                    bms.analyzer.StructuralFilteredSeriesPipeline.plotRecord(rec, rootDir, startDate, endDate, pid, style, 'Orig', spec, cfg);
                    bms.analyzer.StructuralFilteredSeriesPipeline.plotRecord(rec, rootDir, startDate, endDate, pid, style, 'Filt', spec, cfg);
                end
            end

            for g = 1:numel(groups)
                pidList = bms.data.PointResolver.normalize(groups{g});
                if isempty(pidList)
                    continue;
                end
                fprintf(spec.groupMessage, g, strjoin(pidList, ', '));
                [records, groupRows] = bms.analyzer.StructuralFilteredSeriesPipeline.collectGroup( ...
                    rootDir, subfolder, pidList, startDate, endDate, cfg, spec);
                rows = [rows; groupRows]; %#ok<AGROW>
                bms.analyzer.StructuralFilteredSeriesPipeline.plotRecords(records, rootDir, startDate, endDate, g, style, 'Orig', spec, cfg);
                bms.analyzer.StructuralFilteredSeriesPipeline.plotRecords(records, rootDir, startDate, endDate, g, style, 'Filt', spec, cfg);
            end
        end

        function rows = runBearingDisplacement(rootDir, startDate, endDate, subfolder, cfg, style, spec)
            groups = bms.analyzer.StructuralFilteredSeriesPipeline.groupsAsCell( ...
                bms.analyzer.StructuralPlotConfigService.getGroups(cfg, spec.groupKey, {}));
            points = bms.data.PointResolver.fromConfig(cfg, spec.pointKey, ...
                bms.data.PointResolver.flattenGroups(groups));
            points = unique(points, 'stable');

            rows = cell(0, 7);
            for i = 1:numel(points)
                pid = points{i};
                rec = bms.analyzer.StructuralFilteredSeriesPipeline.loadFilteredPoint( ...
                    rootDir, subfolder, pid, startDate, endDate, cfg, spec);
                if ~rec.hasData
                    warning(spec.emptyPointWarning, pid);
                    continue;
                end
                rows(end+1, :) = bms.analyzer.StructuralFilteredSeriesPipeline.statsRow(rec, spec); %#ok<AGROW>
                warnLines = bms.analyzer.StructuralTimeSeriesPlotService.resolveWarnLines(style, cfg, spec.moduleKey, pid);
                bms.analyzer.StructuralFilteredSeriesPipeline.plotRecord(rec, rootDir, startDate, endDate, pid, style, 'Orig', spec, cfg, warnLines);
                bms.analyzer.StructuralFilteredSeriesPipeline.plotRecord(rec, rootDir, startDate, endDate, pid, style, 'Filt', spec, cfg, warnLines);
            end

            for g = 1:numel(groups)
                pidList = bms.data.PointResolver.normalize(groups{g});
                if isempty(pidList)
                    continue;
                end
                records = bms.analyzer.StructuralFilteredSeriesPipeline.collectRecordsOnly( ...
                    rootDir, subfolder, pidList, startDate, endDate, cfg, spec);
                if isempty(records)
                    continue;
                end
                groupWarn = bms.analyzer.StructuralTimeSeriesPlotService.resolveWarnLines(style, cfg, spec.moduleKey, '');
                nameTag = sprintf('G%d', g);
                bms.analyzer.StructuralFilteredSeriesPipeline.plotRecords(records, rootDir, startDate, endDate, nameTag, style, 'Orig', spec, cfg, groupWarn);
                bms.analyzer.StructuralFilteredSeriesPipeline.plotRecords(records, rootDir, startDate, endDate, nameTag, style, 'Filt', spec, cfg, groupWarn);
            end
        end

        function rec = loadFilteredPoint(rootDir, subfolder, pid, startDate, endDate, cfg, spec)
            [times, values] = load_timeseries_range(rootDir, subfolder, pid, startDate, endDate, cfg, spec.sensorType);
            rec = struct('pid', pid, 'times', times, 'raw', values, 'filtered', [], 'hasData', ~isempty(values));
            if ~rec.hasData
                return;
            end
            filtered = bms.analyzer.StructuralSeriesService.movingMedian10Min(times, values);
            rec.filtered = apply_threshold_rules(filtered, times, ...
                resolve_post_filter_thresholds(cfg, spec.moduleKey, pid));
        end

        function [records, rows] = collectGroup(rootDir, subfolder, pointIds, startDate, endDate, cfg, spec)
            records = bms.analyzer.StructuralFilteredSeriesPipeline.collectRecordsOnly( ...
                rootDir, subfolder, pointIds, startDate, endDate, cfg, spec);
            rows = cell(0, 7);
            for i = 1:numel(records)
                rows(end+1, :) = bms.analyzer.StructuralFilteredSeriesPipeline.statsRow(records(i), spec); %#ok<AGROW>
            end
        end

        function records = collectRecordsOnly(rootDir, subfolder, pointIds, startDate, endDate, cfg, spec)
            records = repmat(bms.analyzer.StructuralFilteredSeriesPipeline.emptyRecord(), 0, 1);
            for i = 1:numel(pointIds)
                pid = pointIds{i};
                rec = bms.analyzer.StructuralFilteredSeriesPipeline.loadFilteredPoint( ...
                    rootDir, subfolder, pid, startDate, endDate, cfg, spec);
                if ~rec.hasData
                    if strcmp(spec.moduleKey, 'deflection')
                        warning('测点 %s 无数据，跳过', pid);
                    end
                    continue;
                end
                records(end+1, 1) = rec; %#ok<AGROW>
            end
        end

        function rec = emptyRecord()
            rec = struct('pid', '', 'times', [], 'raw', [], 'filtered', [], 'hasData', false);
        end

        function row = statsRow(rec, spec)
            row = bms.analyzer.StructuralSeriesService.filteredStatsRow( ...
                rec.pid, rec.raw, rec.filtered, spec.decimals);
        end

        function plotRecord(rec, rootDir, startDate, endDate, nameTag, style, suffix, spec, cfg, warnLines)
            if nargin < 10
                warnLines = bms.analyzer.StructuralFilteredSeriesPipeline.defaultWarnLines(style, cfg, spec, rec.pid);
            end
            bms.analyzer.StructuralFilteredSeriesPipeline.plotRecords( ...
                rec, rootDir, startDate, endDate, nameTag, style, suffix, spec, cfg, warnLines);
        end

        function plotRecords(records, rootDir, startDate, endDate, nameTag, style, suffix, spec, cfg, warnLines)
            if nargin < 10
                warnLines = bms.analyzer.StructuralFilteredSeriesPipeline.defaultWarnLines(style, cfg, spec, '');
            end
            if isempty(records)
                return;
            end

            valuesField = 'raw';
            suffixTag = bms.analyzer.StructuralFilteredSeriesPipeline.fileSuffixTag(suffix);
            if strcmpi(suffixTag, 'Filt')
                valuesField = 'filtered';
            end

            timesList = cell(numel(records), 1);
            valuesList = cell(numel(records), 1);
            labels = cell(numel(records), 1);
            for i = 1:numel(records)
                timesList{i} = records(i).times;
                valuesList{i} = records(i).(valuesField);
                labels{i} = records(i).pid;
            end

            [dt0, dt1] = bms.analyzer.StructuralTimeSeriesPlotService.dateRange(startDate, endDate);
            [titleText, fileNameTag, titleSuffix] = bms.analyzer.StructuralFilteredSeriesPipeline.titleParts( ...
                style, spec, nameTag, suffix);
            opts = struct();
            opts.style = style;
            opts.ylabel = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'ylabel', spec.defaultYLabel);
            opts.titleText = titleText;
            opts.outputDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'output_dir', spec.defaultOutputDir);
            opts.baseName = bms.analyzer.StructuralFilteredSeriesPipeline.baseName( ...
                spec, fileNameTag, suffixTag, dt0, dt1, titleSuffix);
            opts.warnLines = warnLines;
            pointId = '';
            if numel(records) == 1
                pointId = records(1).pid;
            end
            opts.ylimRange = bms.analyzer.StructuralTimeSeriesPlotService.resolveStyleYLim(style, pointId);
            opts = bms.analyzer.StructuralFilteredSeriesPipeline.applyColorOptions(opts, numel(records));
            bms.analyzer.StructuralTimeSeriesPlotService.plotCells( ...
                rootDir, timesList, valuesList, labels, startDate, endDate, opts, cfg);
        end

        function warnLines = defaultWarnLines(style, cfg, spec, pid)
            if strcmp(spec.moduleKey, 'deflection')
                warnLines = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'warn_lines', {});
            else
                warnLines = bms.analyzer.StructuralTimeSeriesPlotService.resolveWarnLines(style, cfg, spec.moduleKey, pid);
            end
        end

        function [titleText, fileNameTag, titleSuffix] = titleParts(style, spec, nameTag, suffix)
            prefix = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'title_prefix', spec.defaultTitlePrefix);
            suffixText = char(string(suffix));
            titleSuffix = suffixText;
            if strcmp(spec.moduleKey, 'deflection')
                if isempty(suffixText)
                    titleSuffix = '';
                else
                    titleSuffix = [' ' suffixText];
                end
                if isnumeric(nameTag)
                    fileNameTag = sprintf('G%d', nameTag);
                    titleText = sprintf(spec.groupTitlePattern, prefix, nameTag, titleSuffix);
                else
                    fileNameTag = char(string(nameTag));
                    titleText = sprintf(spec.pointTitlePattern, prefix, fileNameTag, titleSuffix);
                end
            else
                fileNameTag = char(string(nameTag));
                titleText = sprintf(spec.pointTitlePattern, prefix, fileNameTag, suffixText);
            end
        end

        function base = baseName(spec, nameTag, suffixTag, dt0, dt1, titleSuffix)
            if strcmp(spec.moduleKey, 'deflection')
                base = sprintf('%s_%s_%s_%s_%s_%s', spec.filePrefix, nameTag, suffixTag, ...
                    datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd'), datestr(now, 'yyyymmdd_HHMMSS'));
            else
                base = sprintf('%s_%s_%s_%s_%s_%s', spec.filePrefix, nameTag, ...
                    datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd'), char(string(titleSuffix)), datestr(now, 'yyyymmdd_HHMMSS'));
            end
        end

        function tag = fileSuffixTag(suffix)
            tag = char(string(suffix));
            if strcmpi(strtrim(tag), 'Filt') || strcmpi(strtrim(tag), 'Filtered')
                tag = 'Filt';
            elseif strcmpi(strtrim(tag), 'Orig') || strcmpi(strtrim(tag), 'Raw')
                tag = 'Orig';
            elseif isempty(strtrim(tag))
                tag = 'Series';
            else
                tag = regexprep(tag, '[^\w-]', '');
                if isempty(tag)
                    tag = 'Series';
                end
            end
        end

        function opts = applyColorOptions(opts, nSeries)
            if nSeries == 2
                opts.colorField = 'colors_2';
                opts.defaultColors = [0 0 1; 0 0.7 0];
            elseif nSeries == 3
                opts.colorField = 'colors_3';
                opts.defaultColors = [0.5 0 0.7; 0 0 1; 0 0.7 0];
            end
        end

        function subfolder = resolveSubfolder(cfg, spec)
            subfolder = '';
            for i = 1:numel(spec.subfolderKeys)
                subfolder = bms.config.ConfigReader.getSubfolder(cfg, spec.subfolderKeys{i}, '');
                if ~isempty(subfolder)
                    return;
                end
            end
            subfolder = spec.defaultSubfolder;
        end

        function style = resolveStyle(cfg, spec)
            style = bms.analyzer.StructuralPlotConfigService.getStyle(cfg, spec.styleKey);
            if isempty(fieldnames(style)) && ~isempty(spec.fallbackStyleKey)
                style = bms.analyzer.StructuralPlotConfigService.getStyle(cfg, spec.fallbackStyleKey);
            end
        end

        function groups = deflectionGroups(cfg, spec)
            groups = {};
            raw = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, spec.groupKey, {});
            if bms.analyzer.StructuralPlotConfigService.hasGroups(raw)
                groups = bms.analyzer.StructuralFilteredSeriesPipeline.groupsAsCell(raw);
            end
        end

        function groups = groupsAsCell(raw)
            if isempty(raw)
                groups = {};
            elseif iscell(raw)
                groups = raw;
            elseif isstruct(raw)
                names = fieldnames(raw);
                groups = cell(numel(names), 1);
                for i = 1:numel(names)
                    groups{i} = bms.data.PointResolver.normalize(raw.(names{i}));
                end
            else
                groups = {};
            end
        end
    end
end
