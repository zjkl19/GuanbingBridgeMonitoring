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
                case 'tilt'
                    bms.analyzer.StructuralFilteredSeriesPipeline.runTiltAndWrite( ...
                        rootDir, startDate, endDate, excelFile, subfolder, cfg, style, spec);
                    return;
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
                case 'tilt'
                    spec.moduleKey = 'tilt';
                    spec.sensorType = 'tilt';
                    spec.pointKey = 'tilt';
                    spec.groupKey = 'tilt';
                    spec.styleKey = 'tilt';
                    spec.fallbackStyleKey = '';
                    spec.defaultExcel = 'tilt_stats.xlsx';
                    spec.subfolderKeys = {'tilt'};
                    spec.defaultSubfolder = '波形_重采样';
                    spec.defaultOutputDir = '时程曲线_倾角';
                    spec.defaultYLabel = '倾角 (°)';
                    spec.defaultTitlePrefix = '倾角时程';
                    spec.filePrefix = 'Tilt';
                    spec.decimals = 3;
                    spec.promptForDates = false;
                    spec.doneMessage = 'Tilt stats saved to %s';
                    spec.emptyPointWarning = 'Tilt point %s has no data, skip';
                    spec.groupMessage = '';
                    spec.groupTitlePattern = '';
                    spec.pointTitlePattern = '';
                otherwise
                    error('StructuralFilteredSeriesPipeline:UnsupportedKind', ...
                        'Unsupported filtered structural kind: %s', kind);
            end
        end

        function rows = runDeflection(rootDir, startDate, endDate, subfolder, cfg, style, spec)
            rows = cell(0, 7);
            [groups, groupNames] = bms.analyzer.StructuralFilteredSeriesService.deflectionGroupsWithNames(cfg, spec);
            plottedPointIds = {};

            points = bms.analyzer.StructuralPlotConfigService.getPointsOrFlattenFallback(cfg, spec.pointKey, groups);
            if isempty(groups)
                for i = 1:numel(points)
                    bms.app.StopController.throwIfRequested('Stop requested before next deflection point');
                    pid = points{i};
                    fprintf('Per-point deflection: %s ...\n', pid);
                    rec = bms.analyzer.StructuralFilteredSeriesService.loadFilteredPoint( ...
                        rootDir, subfolder, pid, startDate, endDate, cfg, spec);
                    if ~rec.hasData
                        warning(spec.emptyPointWarning, pid);
                        continue;
                    end
                    rows(end+1, :) = bms.analyzer.StructuralFilteredSeriesService.statsRow(rec, spec); %#ok<AGROW>
                    plottedPointIds = bms.analyzer.StructuralFilteredSeriesPipeline.plotDeflectionRecordOnce( ...
                        rec, plottedPointIds, rootDir, startDate, endDate, style, spec, cfg);
                end
                return;
            end

            for g = 1:numel(groups)
                bms.app.StopController.throwIfRequested('Stop requested before next deflection group');
                groupName = groupNames{g};
                pidList = bms.data.PointResolver.normalize(groups{g});
                if isempty(pidList)
                    continue;
                end
                fprintf(spec.groupMessage, g, strjoin(pidList, ', '));
                [records, groupRows] = bms.analyzer.StructuralFilteredSeriesService.collectGroup( ...
                    rootDir, subfolder, pidList, startDate, endDate, cfg, spec);
                rows = [rows; groupRows]; %#ok<AGROW>
                for i = 1:numel(records)
                    bms.app.StopController.throwIfRequested('Stop requested before next deflection point plot');
                    plottedPointIds = bms.analyzer.StructuralFilteredSeriesPipeline.plotDeflectionRecordOnce( ...
                        records(i), plottedPointIds, rootDir, startDate, endDate, style, spec, cfg);
                end
                warnLines = bms.analyzer.StructuralFilteredSeriesPipeline.deflectionGroupWarnLines(records, style, cfg, spec);
                groupStyle = style;
                groupStyle.output_dir = bms.analyzer.StructuralFilteredSeriesPipeline.deflectionGroupOutputDir(style, spec, 'raw');
                bms.analyzer.StructuralFilteredPlotService.plotRecords(records, rootDir, startDate, endDate, groupName, groupStyle, 'Orig', spec, cfg, warnLines);
                groupStyle.output_dir = bms.analyzer.StructuralFilteredSeriesPipeline.deflectionGroupOutputDir(style, spec, 'filtered');
                bms.analyzer.StructuralFilteredPlotService.plotRecords(records, rootDir, startDate, endDate, groupName, groupStyle, 'Filt', spec, cfg, warnLines);
            end

            for i = 1:numel(points)
                bms.app.StopController.throwIfRequested('Stop requested before next deflection point');
                pid = points{i};
                if bms.analyzer.StructuralFilteredSeriesPipeline.containsPoint(plottedPointIds, pid)
                    continue;
                end
                fprintf('Per-point deflection: %s ...\n', pid);
                rec = bms.analyzer.StructuralFilteredSeriesService.loadFilteredPoint( ...
                    rootDir, subfolder, pid, startDate, endDate, cfg, spec);
                if ~rec.hasData
                    warning(spec.emptyPointWarning, pid);
                    continue;
                end
                rows(end+1, :) = bms.analyzer.StructuralFilteredSeriesService.statsRow(rec, spec); %#ok<AGROW>
                plottedPointIds = bms.analyzer.StructuralFilteredSeriesPipeline.plotDeflectionRecordOnce( ...
                    rec, plottedPointIds, rootDir, startDate, endDate, style, spec, cfg);
            end
        end

        function rows = runBearingDisplacement(rootDir, startDate, endDate, subfolder, cfg, style, spec)
            groups = bms.analyzer.StructuralFilteredSeriesService.groupsAsCell( ...
                bms.analyzer.StructuralPlotConfigService.getGroups(cfg, spec.groupKey, {}));
            points = bms.data.PointResolver.fromConfig(cfg, spec.pointKey, ...
                bms.data.PointResolver.flattenGroups(groups));
            points = unique(points, 'stable');

            rows = cell(0, 7);
            for i = 1:numel(points)
                bms.app.StopController.throwIfRequested('Stop requested before next bearing displacement point');
                pid = points{i};
                rec = bms.analyzer.StructuralFilteredSeriesService.loadFilteredPoint( ...
                    rootDir, subfolder, pid, startDate, endDate, cfg, spec);
                if ~rec.hasData
                    warning(spec.emptyPointWarning, pid);
                    continue;
                end
                rows(end+1, :) = bms.analyzer.StructuralFilteredSeriesService.statsRow(rec, spec); %#ok<AGROW>
                warnLines = bms.analyzer.StructuralTimeSeriesPlotService.resolveWarnLines(style, cfg, spec.moduleKey, pid);
                bms.analyzer.StructuralFilteredPlotService.plotRecord(rec, rootDir, startDate, endDate, pid, style, 'Orig', spec, cfg, warnLines);
                bms.analyzer.StructuralFilteredPlotService.plotRecord(rec, rootDir, startDate, endDate, pid, style, 'Filt', spec, cfg, {});
            end

            for g = 1:numel(groups)
                bms.app.StopController.throwIfRequested('Stop requested before next bearing displacement group');
                pidList = bms.data.PointResolver.normalize(groups{g});
                if isempty(pidList)
                    continue;
                end
                records = bms.analyzer.StructuralFilteredSeriesService.collectRecordsOnly( ...
                    rootDir, subfolder, pidList, startDate, endDate, cfg, spec);
                if isempty(records)
                    continue;
                end
                groupWarn = bms.analyzer.StructuralFilteredSeriesPipeline.bearingGroupWarnLines(records, style, cfg, spec);
                nameTag = sprintf('G%d', g);
                groupStyle = style;
                groupStyle.output_dir = bms.analyzer.StructuralFilteredSeriesPipeline.bearingGroupOutputDir(style, spec);
                bms.analyzer.StructuralFilteredPlotService.plotRecords(records, rootDir, startDate, endDate, nameTag, groupStyle, 'Orig', spec, cfg, groupWarn);
                bms.analyzer.StructuralFilteredPlotService.plotRecords(records, rootDir, startDate, endDate, nameTag, groupStyle, 'Filt', spec, cfg, {});
            end
        end

        function plottedPointIds = plotDeflectionRecordOnce(rec, plottedPointIds, rootDir, startDate, endDate, style, spec, cfg)
            if isempty(rec) || ~isfield(rec, 'pid') || isempty(rec.pid) || ...
                    bms.analyzer.StructuralFilteredSeriesPipeline.containsPoint(plottedPointIds, rec.pid)
                return;
            end

            pointStyle = style;
            pointStyle.output_dir = bms.analyzer.StructuralFilteredSeriesPipeline.deflectionSingleOutputDir(style, spec, 'raw');
            warnLines = bms.analyzer.StructuralFilteredPlotService.defaultWarnLines(style, cfg, spec, rec.pid);
            bms.analyzer.StructuralFilteredPlotService.plotRecord( ...
                rec, rootDir, startDate, endDate, rec.pid, pointStyle, 'Orig', spec, cfg, warnLines);
            pointStyle.output_dir = bms.analyzer.StructuralFilteredSeriesPipeline.deflectionSingleOutputDir(style, spec, 'filtered');
            bms.analyzer.StructuralFilteredPlotService.plotRecord( ...
                rec, rootDir, startDate, endDate, rec.pid, pointStyle, 'Filt', spec, cfg, warnLines);
            plottedPointIds{end+1, 1} = char(string(rec.pid));
        end

        function outDir = deflectionSingleOutputDir(style, spec, variant)
            if nargin < 3 || isempty(variant), variant = 'raw'; end
            outDir = '';
            switch lower(char(string(variant)))
                case {'raw','orig','original'}
                    outDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'raw_output_dir', '');
                    if isempty(outDir)
                        outDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'single_raw_output_dir', '');
                    end
                    suffix = '_原始';
                case {'filtered','filt'}
                    outDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'filtered_output_dir', '');
                    if isempty(outDir)
                        outDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'single_filtered_output_dir', '');
                    end
                    suffix = '_滤波';
                otherwise
                    error('StructuralFilteredSeriesPipeline:InvalidDeflectionVariant', ...
                        'Unknown deflection output variant: %s', char(string(variant)));
            end
            baseDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'single_output_dir', '');
            if isempty(baseDir)
                baseDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'output_dir', spec.defaultOutputDir);
            end
            if isempty(outDir)
                outDir = [char(string(baseDir)) suffix];
            end
        end

        function outDir = deflectionGroupOutputDir(style, spec, variant)
            if nargin < 3 || isempty(variant), variant = 'raw'; end
            outDir = '';
            switch lower(char(string(variant)))
                case {'raw','orig','original'}
                    outDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'raw_group_output_dir', '');
                    if isempty(outDir)
                        outDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'group_raw_output_dir', '');
                    end
                    suffix = '_原始';
                case {'filtered','filt'}
                    outDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'filtered_group_output_dir', '');
                    if isempty(outDir)
                        outDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'group_filtered_output_dir', '');
                    end
                    suffix = '_滤波';
                otherwise
                    error('StructuralFilteredSeriesPipeline:InvalidDeflectionVariant', ...
                        'Unknown deflection output variant: %s', char(string(variant)));
            end
            baseDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'group_output_dir', '');
            if isempty(baseDir)
                singleBase = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'single_output_dir', '');
                if isempty(singleBase)
                    singleBase = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'output_dir', spec.defaultOutputDir);
                end
                baseDir = [char(string(singleBase)) '_组图'];
            end
            if isempty(outDir)
                outDir = [char(string(baseDir)) suffix];
            end
        end

        function outDir = bearingGroupOutputDir(style, spec)
            outDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'group_output_dir', '');
            if isempty(outDir)
                singleDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'output_dir', spec.defaultOutputDir);
                outDir = [char(string(singleDir)) '_组图'];
            end
        end

        function outDir = tiltSingleOutputDir(style, spec)
            outDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'single_output_dir', '');
            if isempty(outDir)
                outDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'output_dir', spec.defaultOutputDir);
            end
        end

        function outDir = tiltGroupOutputDir(style, spec)
            outDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'group_output_dir', '');
            if isempty(outDir)
                singleDir = bms.analyzer.StructuralFilteredSeriesPipeline.tiltSingleOutputDir(style, spec);
                outDir = [char(string(singleDir)) '_组图'];
            end
        end

        function warnLines = deflectionGroupWarnLines(records, style, cfg, spec)
            fallback = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'warn_lines', {});
            pointResolver = @(pid) bms.analyzer.StructuralFilteredPlotService.defaultWarnLines( ...
                style, cfg, spec, pid);
            warnLines = bms.analyzer.StructuralFilteredSeriesPipeline.commonRecordWarnLines( ...
                records, pointResolver, fallback);
        end

        function warnLines = bearingGroupWarnLines(records, style, cfg, spec)
            fallback = bms.analyzer.StructuralTimeSeriesPlotService.resolveWarnLines( ...
                style, cfg, spec.moduleKey, '');
            pointResolver = @(pid) bms.analyzer.StructuralTimeSeriesPlotService.resolveWarnLines( ...
                style, cfg, spec.moduleKey, pid);
            warnLines = bms.analyzer.StructuralFilteredSeriesPipeline.commonRecordWarnLines( ...
                records, pointResolver, fallback);
        end

        function warnLines = commonRecordWarnLines(records, pointResolver, fallbackWarnLines)
            warnLines = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(fallbackWarnLines);
            if ~isempty(warnLines)
                return;
            end

            common = {};
            for i = 1:numel(records)
                if ~isfield(records(i), 'pid') || isempty(records(i).pid)
                    continue;
                end
                current = pointResolver(records(i).pid);
                current = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(current);
                if isempty(current)
                    warnLines = {};
                    return;
                end
                if isempty(common)
                    common = current;
                elseif ~bms.analyzer.StructuralFilteredSeriesPipeline.warnLinesHaveSameY(common, current)
                    warnLines = {};
                    return;
                end
            end
            warnLines = common;
        end

        function tf = warnLinesHaveSameY(a, b)
            av = bms.analyzer.StructuralFilteredSeriesPipeline.warnLineYValues(a);
            bv = bms.analyzer.StructuralFilteredSeriesPipeline.warnLineYValues(b);
            av = sort(av(isfinite(av)));
            bv = sort(bv(isfinite(bv)));
            tf = numel(av) == numel(bv) && all(abs(av(:) - bv(:)) < 1e-9);
        end

        function values = warnLineYValues(warnLines)
            warnLines = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(warnLines);
            values = NaN(numel(warnLines), 1);
            for i = 1:numel(warnLines)
                wl = warnLines{i};
                if isstruct(wl) && isfield(wl, 'y') && isnumeric(wl.y) && isscalar(wl.y)
                    values(i) = wl.y;
                end
            end
        end

        function tf = containsPoint(pointIds, pid)
            tf = any(strcmp(pointIds, char(string(pid))));
        end

        function runTiltAndWrite(rootDir, startDate, endDate, excelFile, subfolder, cfg, style, spec)
            [perPointRows, groupRows, groupNames] = bms.analyzer.StructuralFilteredSeriesPipeline.runTilt( ...
                rootDir, startDate, endDate, subfolder, cfg, style, spec);

            if ~isempty(perPointRows)
                T = bms.analyzer.StructuralSeriesService.basicStatsTable(perPointRows);
                bms.io.StatsWriter.writeModuleTableChecked(T, excelFile, spec.moduleKey, 'Sheet', 'Tilt');
            end
            for i = 1:numel(groupRows)
                T = bms.analyzer.StructuralSeriesService.basicStatsTable(groupRows{i});
                bms.io.StatsWriter.writeModuleTableChecked(T, excelFile, spec.moduleKey, ...
                    'Sheet', bms.analyzer.StructuralPlotConfigService.sheetName(groupNames{i}, 'Tilt_'));
            end

            fprintf('%s\n', sprintf(spec.doneMessage, excelFile));
        end

        function [perPointRows, groupRows, groupNames] = runTilt(rootDir, startDate, endDate, subfolder, cfg, style, spec)
            pointsCfg = bms.analyzer.StructuralPlotConfigService.getPoints(cfg, spec.pointKey, {});
            groupsCfg = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, spec.groupKey, []);
            explicitPoints = ~isempty(pointsCfg);
            explicitGroups = bms.analyzer.StructuralPlotConfigService.hasGroups(groupsCfg);

            if ~explicitPoints && ~explicitGroups
                groupsCfg = bms.analyzer.StructuralFilteredSeriesService.legacyTiltGroups();
                explicitGroups = true;
                pointsCfg = bms.analyzer.StructuralPlotConfigService.flattenGroups(groupsCfg);
            end

            perPointRows = cell(0, 4);
            if explicitPoints || bms.analyzer.StructuralPlotConfigService.isJiulongjiang(cfg)
                for i = 1:numel(pointsCfg)
                    pid = pointsCfg{i};
                    fprintf('Per-point tilt: %s ...\n', pid);
                    data = bms.analyzer.StructuralSeriesService.loadPoint( ...
                        rootDir, subfolder, pid, startDate, endDate, cfg, spec.sensorType);
                    if isempty(data.vals)
                        warning(spec.emptyPointWarning, pid);
                        continue;
                    end

                    perPointRows(end+1, :) = bms.analyzer.StructuralSeriesService.basicStatsRow( ...
                        pid, data.vals, spec.decimals); %#ok<AGROW>

                    warnLines = bms.analyzer.StructuralTimeSeriesPlotService.resolveWarnLines( ...
                        style, cfg, spec.moduleKey, pid);
                    pointStyle = style;
                    pointStyle.output_dir = bms.analyzer.StructuralFilteredSeriesPipeline.tiltSingleOutputDir(style, spec);
                    bms.analyzer.StructuralFilteredPlotService.plotTiltCurve( ...
                        rootDir, data, startDate, endDate, pid, pointStyle, warnLines, spec, cfg);
                end
            end

            groupRows = {};
            groupNames = {};
            if ~explicitGroups
                return;
            end

            groupsMap = bms.analyzer.StructuralPlotConfigService.normalizeGroupMap(groupsCfg);
            names = fieldnames(groupsMap);
            for i = 1:numel(names)
                groupName = names{i};
                [dataList, rows] = bms.analyzer.StructuralSeriesService.collectPoints( ...
                    rootDir, subfolder, groupsMap.(groupName), startDate, endDate, cfg, ...
                    spec.sensorType, spec.decimals, 'Tilt point');
                if ~isempty(rows)
                    groupNames{end+1, 1} = groupName; %#ok<AGROW>
                    groupRows{end+1, 1} = rows; %#ok<AGROW>
                end
                if bms.analyzer.StructuralPlotConfigService.hasPlotData(dataList)
                    groupWarn = bms.analyzer.StructuralTimeSeriesPlotService.resolveWarnLines( ...
                        style, cfg, spec.moduleKey, '');
                    groupStyle = style;
                    groupStyle.output_dir = bms.analyzer.StructuralFilteredSeriesPipeline.tiltGroupOutputDir(style, spec);
                    bms.analyzer.StructuralFilteredPlotService.plotTiltCurve( ...
                        rootDir, dataList, startDate, endDate, groupName, groupStyle, groupWarn, spec, cfg);
                end
            end
        end

        function plotTiltCurve(varargin)
            bms.analyzer.StructuralFilteredPlotService.plotTiltCurve(varargin{:});
        end

        function groups = legacyTiltGroups()
            groups = bms.analyzer.StructuralFilteredSeriesService.legacyTiltGroups();
        end

        function rec = loadFilteredPoint(rootDir, subfolder, pid, startDate, endDate, cfg, spec)
            rec = bms.analyzer.StructuralFilteredSeriesService.loadFilteredPoint( ...
                rootDir, subfolder, pid, startDate, endDate, cfg, spec);
        end

        function [records, rows] = collectGroup(rootDir, subfolder, pointIds, startDate, endDate, cfg, spec)
            [records, rows] = bms.analyzer.StructuralFilteredSeriesService.collectGroup( ...
                rootDir, subfolder, pointIds, startDate, endDate, cfg, spec);
        end

        function records = collectRecordsOnly(rootDir, subfolder, pointIds, startDate, endDate, cfg, spec)
            records = bms.analyzer.StructuralFilteredSeriesService.collectRecordsOnly( ...
                rootDir, subfolder, pointIds, startDate, endDate, cfg, spec);
        end

        function rec = emptyRecord()
            rec = bms.analyzer.StructuralFilteredSeriesService.emptyRecord();
        end

        function row = statsRow(rec, spec)
            row = bms.analyzer.StructuralFilteredSeriesService.statsRow(rec, spec);
        end

        function plotRecord(rec, rootDir, startDate, endDate, nameTag, style, suffix, spec, cfg, warnLines)
            if nargin < 10
                warnLines = bms.analyzer.StructuralFilteredPlotService.defaultWarnLines(style, cfg, spec, rec.pid);
            end
            bms.analyzer.StructuralFilteredPlotService.plotRecord( ...
                rec, rootDir, startDate, endDate, nameTag, style, suffix, spec, cfg, warnLines);
        end

        function plotRecords(records, rootDir, startDate, endDate, nameTag, style, suffix, spec, cfg, warnLines)
            if nargin < 10
                warnLines = bms.analyzer.StructuralFilteredPlotService.defaultWarnLines(style, cfg, spec, '');
            end
            bms.analyzer.StructuralFilteredPlotService.plotRecords( ...
                records, rootDir, startDate, endDate, nameTag, style, suffix, spec, cfg, warnLines);
        end

        function warnLines = defaultWarnLines(style, cfg, spec, pid)
            warnLines = bms.analyzer.StructuralFilteredPlotService.defaultWarnLines(style, cfg, spec, pid);
        end

        function [titleText, fileNameTag, titleSuffix] = titleParts(style, spec, nameTag, suffix)
            [titleText, fileNameTag, titleSuffix] = bms.analyzer.StructuralFilteredPlotService.titleParts( ...
                style, spec, nameTag, suffix);
        end

        function base = baseName(spec, nameTag, suffixTag, dt0, dt1, titleSuffix)
            base = bms.analyzer.StructuralFilteredPlotService.baseName( ...
                spec, nameTag, suffixTag, dt0, dt1, titleSuffix);
        end

        function tag = fileSuffixTag(suffix)
            tag = bms.analyzer.StructuralFilteredPlotService.fileSuffixTag(suffix);
        end

        function opts = applyColorOptions(opts, nSeries)
            opts = bms.analyzer.StructuralFilteredPlotService.applyColorOptions(opts, nSeries);
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
            groups = bms.analyzer.StructuralFilteredSeriesService.deflectionGroups(cfg, spec);
        end

        function groups = groupsAsCell(raw)
            groups = bms.analyzer.StructuralFilteredSeriesService.groupsAsCell(raw);
        end
    end
end
