classdef CrackAnalysisPipeline
    %CRACKANALYSISPIPELINE Crack width analysis with optional temperature branch.

    methods (Static)
        function run(rootDir, startDate, endDate, excelFile, subfolder, cfg)
            if nargin < 1 || isempty(rootDir), rootDir = pwd; end
            if nargin < 2 || isempty(startDate), error('start_date is required'); end
            if nargin < 3 || isempty(endDate), error('end_date is required'); end
            if nargin < 4 || isempty(excelFile), excelFile = 'crack_stats.xlsx'; end
            if nargin < 6 || isempty(cfg), cfg = load_config(); end
            if nargin < 5 || isempty(subfolder)
                subfolder = bms.analyzer.CrackAnalysisPipeline.resolveSubfolder(cfg);
            end

            excelFile = resolve_data_output_path(rootDir, excelFile, 'stats');
            style = bms.analyzer.CrackAnalysisPipeline.style(cfg);
            opt = bms.analyzer.CrackAnalysisPipeline.options(style);
            groups = bms.analyzer.CrackAnalysisPipeline.resolveGroups(cfg, opt);
            points = bms.analyzer.CrackAnalysisPipeline.resolvePoints(cfg, groups);
            cache = containers.Map('KeyType', 'char', 'ValueType', 'any');

            rows = bms.analyzer.CrackAnalysisPipeline.collectStats( ...
                cache, rootDir, subfolder, startDate, endDate, cfg, points, opt);
            T = bms.analyzer.StructuralSeriesService.crackStatsTable(rows);
            bms.io.StatsWriter.writeModuleTableChecked(T, excelFile, 'crack');

            plotSpec = bms.analyzer.CrackAnalysisPipeline.plotSpec(rootDir, style);
            if opt.per_point_plot
                bms.analyzer.CrackAnalysisPipeline.plotPerPoint( ...
                    cache, rootDir, subfolder, startDate, endDate, cfg, points, opt, style, plotSpec);
            end
            if opt.group_plot && bms.analyzer.StructuralPlotConfigService.hasGroupConfig(groups)
                bms.analyzer.CrackAnalysisPipeline.plotGroups( ...
                    cache, rootDir, subfolder, startDate, endDate, cfg, groups, opt, style, plotSpec);
            end

            fprintf('Crack stats saved to %s\n', excelFile);
        end

        function subfolder = resolveSubfolder(cfg)
            subfolder = bms.config.ConfigReader.getSubfolder(cfg, 'crack', '???');
        end

        function style = style(cfg)
            style = bms.analyzer.StructuralPlotConfigService.getStyle(cfg, 'crack');
        end

        function opt = options(style)
            opt = struct( ...
                'per_point_plot', false, ...
                'group_plot', true, ...
                'temp_enabled', true, ...
                'skip_group_if_missing', true);

            if ~isstruct(style)
                return;
            end
            opt.per_point_plot = bms.analyzer.CrackAnalysisPipeline.boolField(style, 'per_point_plot', opt.per_point_plot);
            opt.group_plot = bms.analyzer.CrackAnalysisPipeline.boolField(style, 'group_plot', opt.group_plot);
            opt.temp_enabled = bms.analyzer.CrackAnalysisPipeline.boolField(style, 'temp_enabled', opt.temp_enabled);
            opt.skip_group_if_missing = bms.analyzer.CrackAnalysisPipeline.boolField(style, 'skip_group_if_missing', opt.skip_group_if_missing);
        end

        function value = boolField(s, field, defaultValue)
            value = defaultValue;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                value = logical(s.(field));
            end
        end

        function groups = resolveGroups(cfg, opt)
            groups = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, 'crack', []);
            if ~opt.group_plot
                groups = struct();
            elseif ~bms.analyzer.StructuralPlotConfigService.hasGroupConfig(groups)
                if opt.skip_group_if_missing
                    groups = struct();
                else
                    groups = bms.analyzer.CrackAnalysisPipeline.defaultGroups();
                end
            end
        end

        function points = resolvePoints(cfg, groups)
            points = bms.analyzer.StructuralPlotConfigService.getPoints(cfg, 'crack', {});
            if isempty(points)
                points = unique(bms.analyzer.StructuralPlotConfigService.flattenGroupPoints(groups), 'stable');
            end
        end

        function rows = collectStats(cache, rootDir, subfolder, startDate, endDate, cfg, points, opt)
            rows = cell(numel(points), 7);
            row = 0;
            for i = 1:numel(points)
                pid = points{i};
                S = bms.analyzer.CrackAnalysisPipeline.fetchPointSeries( ...
                    cache, rootDir, subfolder, startDate, endDate, cfg, pid, opt.temp_enabled);
                crackStats = bms.analyzer.StructuralSeriesService.statsTriple(S.crack_vals, 3);

                row = row + 1;
                rows{row, 1} = pid;
                rows{row, 2} = crackStats(1);
                rows{row, 3} = crackStats(2);
                rows{row, 4} = crackStats(3);
                if opt.temp_enabled
                    tempStats = bms.analyzer.StructuralSeriesService.statsTriple(S.temp_vals, 3);
                    rows{row, 5} = tempStats(1);
                    rows{row, 6} = tempStats(2);
                    rows{row, 7} = tempStats(3);
                else
                    rows{row, 5} = NaN;
                    rows{row, 6} = NaN;
                    rows{row, 7} = NaN;
                end
            end

            if row == 0
                rows = cell(0, 7);
            else
                rows = rows(1:row, :);
            end
        end

        function S = fetchPointSeries(cache, rootDir, subfolder, startDate, endDate, cfg, pid, tempEnabled)
            if isKey(cache, pid)
                S = cache(pid);
                return;
            end

            [tc, vc] = load_timeseries_range(rootDir, subfolder, pid, startDate, endDate, cfg, 'crack');
            tt = [];
            vt = [];
            if tempEnabled
                [tt, vt] = load_timeseries_range(rootDir, subfolder, [pid '-t'], startDate, endDate, cfg, 'crack_temp');
            end

            S = struct('crack_times', tc, 'crack_vals', vc, 'temp_times', tt, 'temp_vals', vt);
            cache(pid) = S;
        end

        function ps = plotSpec(rootDir, style)
            ps = struct();
            ps.crack_ylabel = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'ylabel_crack', 'Crack Width (mm)');
            ps.crack_title = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'title_prefix_crack', 'Crack Width');
            ps.temp_ylabel = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'ylabel_temp', 'Crack Temp (degC)');
            ps.temp_title = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'title_prefix_temp', 'Crack Temp');
            ps.crack_dir = fullfile(rootDir, bms.analyzer.StructuralPlotConfigService.sanitizeFilename( ...
                bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'output_dir_crack', '时程曲线_裂缝宽度')));
            ps.temp_dir = fullfile(rootDir, bms.analyzer.StructuralPlotConfigService.sanitizeFilename( ...
                bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'output_dir_temp', '时程曲线_裂缝温度')));
        end

        function plotPerPoint(cache, rootDir, subfolder, startDate, endDate, cfg, points, opt, style, ps)
            for i = 1:numel(points)
                pid = points{i};
                S = bms.analyzer.CrackAnalysisPipeline.fetchPointSeries( ...
                    cache, rootDir, subfolder, startDate, endDate, cfg, pid, opt.temp_enabled);
                if ~isempty(S.crack_times)
                    bms.analyzer.CrackAnalysisPipeline.plotSingleCurve( ...
                        S.crack_times, S.crack_vals, pid, ps.crack_ylabel, ps.crack_title, ...
                        ps.crack_dir, startDate, endDate, ...
                        bms.analyzer.CrackAnalysisPipeline.namedYLim(style, pid), cfg);
                end
                if opt.temp_enabled && ~isempty(S.temp_times)
                    bms.analyzer.CrackAnalysisPipeline.plotSingleCurve( ...
                        S.temp_times, S.temp_vals, pid, ps.temp_ylabel, ps.temp_title, ...
                        ps.temp_dir, startDate, endDate, [], cfg);
                end
            end
        end

        function plotGroups(cache, rootDir, subfolder, startDate, endDate, cfg, groups, opt, style, ps)
            names = fieldnames(groups);
            for gi = 1:numel(names)
                groupName = names{gi};
                pointList = bms.analyzer.StructuralPlotConfigService.normalizePoints(groups.(groupName));
                if isempty(pointList)
                    continue;
                end

                crackTimes = {};
                crackVals = {};
                crackLabels = {};
                tempTimes = {};
                tempVals = {};
                tempLabels = {};

                for i = 1:numel(pointList)
                    pid = pointList{i};
                    S = bms.analyzer.CrackAnalysisPipeline.fetchPointSeries( ...
                        cache, rootDir, subfolder, startDate, endDate, cfg, pid, opt.temp_enabled);
                    if ~isempty(S.crack_times)
                        crackTimes{end+1, 1} = S.crack_times; %#ok<AGROW>
                        crackVals{end+1, 1} = S.crack_vals; %#ok<AGROW>
                        crackLabels{end+1, 1} = pid; %#ok<AGROW>
                    end
                    if opt.temp_enabled && ~isempty(S.temp_times)
                        tempTimes{end+1, 1} = S.temp_times; %#ok<AGROW>
                        tempVals{end+1, 1} = S.temp_vals; %#ok<AGROW>
                        tempLabels{end+1, 1} = pid; %#ok<AGROW>
                    end
                end

                if ~isempty(crackLabels)
                    bms.analyzer.CrackAnalysisPipeline.plotGroupCurve( ...
                        crackTimes, crackVals, crackLabels, ps.crack_ylabel, ps.crack_title, ...
                        ps.crack_dir, groupName, startDate, endDate, ...
                        bms.analyzer.CrackAnalysisPipeline.namedYLim(style, groupName), style, cfg);
                elseif ~opt.skip_group_if_missing
                    warning('Crack group %s has no valid data.', groupName);
                end

                if opt.temp_enabled
                    if ~isempty(tempLabels)
                        bms.analyzer.CrackAnalysisPipeline.plotGroupCurve( ...
                            tempTimes, tempVals, tempLabels, ps.temp_ylabel, ps.temp_title, ...
                            ps.temp_dir, groupName, startDate, endDate, [], style, cfg);
                    elseif ~opt.skip_group_if_missing
                        warning('Crack temp group %s has no valid data.', groupName);
                    end
                end
            end
        end

        function plotSingleCurve(t, v, pid, ylabelText, titlePrefix, outDir, startDate, endDate, ylimRange, cfg)
            if nargin < 10
                cfg = struct();
            end
            bms.analyzer.CrackAnalysisPipeline.plotGroupCurve( ...
                {t}, {v}, {pid}, ylabelText, titlePrefix, outDir, pid, startDate, endDate, ...
                ylimRange, struct(), cfg);
        end

        function plotGroupCurve(timesCell, valsCell, labels, ylabelText, titlePrefix, outDir, groupName, startDate, endDate, ylimRange, style, cfg)
            if nargin < 12
                cfg = struct();
            end
            if isempty(labels)
                return;
            end

            [dt0, dt1] = bms.analyzer.StructuralTimeSeriesPlotService.dateRange(startDate, endDate);
            opts = struct();
            opts.style = style;
            opts.outputDir = outDir;
            opts.baseName = sprintf('%s_%s_%s_%s_%s', titlePrefix, groupName, ...
                datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd'), datestr(now, 'yyyymmdd_HHMMSS'));
            opts.titleText = sprintf('%s %s', titlePrefix, groupName);
            opts.ylabel = ylabelText;
            opts.ylimRange = ylimRange;
            opts.colorField = 'colors_4';
            opts.defaultColors = [0 0 0; 1 0 0; 0 0 1; 0 0.7 0];
            bms.analyzer.StructuralTimeSeriesPlotService.plotCells( ...
                '', timesCell, valsCell, labels, startDate, endDate, opts, cfg);
        end

        function ylimValue = namedYLim(style, name)
            defaultYLim = bms.analyzer.StructuralPlotConfigService.defaultYLim(style);
            ylimValue = bms.analyzer.StructuralPlotConfigService.resolveNamedYLim(style, name, defaultYLim);
        end

        function groups = defaultGroups()
            groups = struct( ...
                'G05', {{'GB-CRK-G05-001-01', 'GB-CRK-G05-001-02', 'GB-CRK-G05-001-03', 'GB-CRK-G05-001-04'}}, ...
                'G06', {{'GB-CRK-G06-001-01', 'GB-CRK-G06-001-02', 'GB-CRK-G06-001-03', 'GB-CRK-G06-001-04'}});
        end
    end
end
