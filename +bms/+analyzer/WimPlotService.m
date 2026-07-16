classdef WimPlotService
    %WIMPLOTSERVICE Plot generation for WIM report CSV outputs.

    methods (Static)
        function generate(csvPaths, outDir, wim, cfg, bridge, yyyymm)
            plotCfg = bms.analyzer.WimPlotService.getPlotConfig(cfg, wim);
            if ~plotCfg.enabled
                return;
            end

            plotDir = fullfile(outDir, plotCfg.output_dir);
            if ~exist(plotDir, 'dir'), mkdir(plotDir); end

            defs = bms.analyzer.WimPlotService.loadPlotDefs(plotCfg.excel_path, plotCfg.sheet);
            if isempty(defs)
                fprintf('[WIM] No plot defs found: %s\n', plotCfg.excel_path);
                return;
            end

            summaryPath = fullfile(plotDir, sprintf('WIM_Plot_Summary_%s_%s.txt', bridge, yyyymm));
            fid = fopen(summaryPath, 'w', 'n', 'UTF-8');
            if fid < 0
                fprintf('[WIM] Cannot write summary: %s\n', summaryPath);
                fid = [];
            end

            laneTemplate = [];
            for i = 1:numel(defs)
                if contains(defs(i).name, "车道") && contains(defs(i).name, "不同车重区间车辆数")
                    laneTemplate = defs(i);
                    break;
                end
            end

            for i = 1:numel(defs)
                def = defs(i);
                if contains(def.name, "车道") && contains(def.name, "不同车重区间车辆数")
                    continue;
                end
                [xlabels, yvals, ylabel, titleText] = bms.analyzer.WimPlotService.resolvePlotData(def.name, csvPaths, wim, plotCfg);
                if isempty(yvals)
                    continue;
                end
                figPx = bms.analyzer.WimPlotService.resolveFigSize(plotCfg, def.name);
                outName = sprintf('WIM_%s_%s_%s.%s', bms.analyzer.WimPlotService.safeName(def.name), bridge, yyyymm, plotCfg.format);
                outPath = fullfile(plotDir, outName);
                bms.analyzer.WimPlotService.plotBarChart(outPath, titleText, ylabel, xlabels, yvals, def.show_pct, def.dtype, plotCfg, figPx);
                bms.analyzer.WimPlotService.writePlotSummary(fid, titleText, xlabels, yvals, def.dtype, def.show_pct, plotCfg);
            end

            if ~isempty(laneTemplate)
                bms.analyzer.WimPlotService.generateLaneGrossPlots(csvPaths, plotDir, bridge, yyyymm, laneTemplate, plotCfg, fid);
            end

            if ~isempty(fid)
                fclose(fid);
            end
        end

        function generateLaneGrossPlots(csvPaths, plotDir, bridge, yyyymm, laneTemplate, plotCfg, fid)
            if ~isfield(csvPaths, 'LaneSpeedWeight_GrossPerLane') || ~exist(csvPaths.LaneSpeedWeight_GrossPerLane, 'file')
                return;
            end
            T = readtable(csvPaths.LaneSpeedWeight_GrossPerLane, 'TextType', 'string', 'Encoding', 'UTF-8');
            lanes = unique(T.lane);
            labels = string(T.label);
            for li = 1:numel(lanes)
                lane = lanes(li);
                mask = T.lane == lane;
                [~, order] = sort(T.bin_id(mask));
                yvals = T.count(mask);
                yvals = yvals(order);
                xlabels = labels(mask);
                xlabels = xlabels(order);
                titleText = regexprep(laneTemplate.name, "车道\d+", sprintf("车道%d", lane));
                figPx = bms.analyzer.WimPlotService.resolveFigSize(plotCfg, titleText);
                outName = sprintf('WIM_%s_%s_%s.%s', bms.analyzer.WimPlotService.safeName(titleText), bridge, yyyymm, plotCfg.format);
                outPath = fullfile(plotDir, outName);
                bms.analyzer.WimPlotService.plotBarChart(outPath, titleText, laneTemplate.ylabel, xlabels, yvals, ...
                    laneTemplate.show_pct, laneTemplate.dtype, plotCfg, figPx);
                bms.analyzer.WimPlotService.writePlotSummary(fid, titleText, xlabels, yvals, laneTemplate.dtype, laneTemplate.show_pct, plotCfg);
            end
        end

        function plotCfg = getPlotConfig(cfg, wim)
            plotCfg = struct();
            if isfield(cfg, 'wim_plot') && isstruct(cfg.wim_plot)
                plotCfg = cfg.wim_plot;
            end
            if isfield(wim, 'plot') && isstruct(wim.plot)
                plotCfg = bms.analyzer.WimConfigService.mergeStruct(plotCfg, wim.plot);
            end
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'enabled', false);
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'output_dir', 'plots');
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'format', 'png');
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'excel_path', fullfile('data','python','动态称重.xlsx'));
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'sheet', 'Sheet1');
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'fig_size_px', [900, 600]);
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'y_decimals', 0);
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'value_label', true);
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'percent_on_newline', true);
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'font_tick', 11);
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'font_xlabel', 12);
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'font_ylabel', 12);
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'font_title', 14);
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'font_value_label', 11);
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'x_label_rotation', 0);
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'save_fig', true);
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'force_exponent_label', true);
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'xlabels_list', []);
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'ylabels_list', []);
            plotCfg = bms.analyzer.WimConfigService.fillDefault(plotCfg, 'fig_size_list', []);
        end

        function defs = loadPlotDefs(excelPath, sheet)
            defs = struct('name', {}, 'dtype', {}, 'ylabel', {}, 'show_pct', {});
            if ~exist(excelPath, 'file')
                fprintf('[WIM] Plot config not found: %s\n', excelPath);
                return;
            end
            T = readtable(excelPath, 'Sheet', sheet, 'VariableNamingRule', 'preserve');
            n = height(T);
            for i = 1:n
                name = string(T{i, 2});
                if strlength(strtrim(name)) == 0
                    break;
                end
                dtype = lower(string(T{i, 4}));
                ylabel = string(T{i, 6});
                pct = string(T{i, 7});
                defs(end+1) = struct( ... %#ok<AGROW>
                    'name', strtrim(name), ...
                    'dtype', strtrim(dtype), ...
                    'ylabel', strtrim(ylabel), ...
                    'show_pct', strcmp(strtrim(pct), "是"));
            end
        end

        function [xlabels, yvals, ylabel, titleText] = resolvePlotData(name, csvPaths, wim, plotCfg)
            xlabels = strings(0, 1);
            yvals = [];
            ylabel = "";
            titleText = name;

            if contains(name, "不同车道车辆数") && isfield(csvPaths, 'LaneSpeedWeight_Lane')
                T = readtable(csvPaths.LaneSpeedWeight_Lane, 'TextType', 'string', 'Encoding', 'UTF-8');
                xlabels = "车道" + string(T.lane);
                yvals = T.count;
                ylabel = "数量";
                [xlabels, ylabel] = bms.analyzer.WimPlotService.applyPlotOverrides(name, xlabels, ylabel, plotCfg);
                return;
            end
            if contains(name, "不同车速区间车辆数") && isfield(csvPaths, 'LaneSpeedWeight_Speed')
                T = readtable(csvPaths.LaneSpeedWeight_Speed, 'TextType', 'string', 'Encoding', 'UTF-8');
                xlabels = string(T.label);
                yvals = T.count;
                ylabel = "数量";
                [xlabels, ylabel] = bms.analyzer.WimPlotService.applyPlotOverrides(name, xlabels, ylabel, plotCfg);
                return;
            end
            if contains(name, "不同车重区间车辆数") && isfield(csvPaths, 'LaneSpeedWeight_Gross')
                T = readtable(csvPaths.LaneSpeedWeight_Gross, 'TextType', 'string', 'Encoding', 'UTF-8');
                xlabels = string(T.label);
                yvals = T.count;
                ylabel = "数量";
                [xlabels, ylabel] = bms.analyzer.WimPlotService.applyPlotOverrides(name, xlabels, ylabel, plotCfg);
                return;
            end
            if contains(name, "不同小时区间车辆数") && isfield(csvPaths, 'Hourly_Count')
                T = readtable(csvPaths.Hourly_Count, 'TextType', 'string', 'Encoding', 'UTF-8');
                xlabels = string(T.label);
                yvals = T.count;
                ylabel = "数量";
                [xlabels, ylabel] = bms.analyzer.WimPlotService.applyPlotOverrides(name, xlabels, ylabel, plotCfg);
                return;
            end
            if contains(name, "不同小时区间平均车速") && isfield(csvPaths, 'Hourly_AvgSpeed')
                T = readtable(csvPaths.Hourly_AvgSpeed, 'TextType', 'string', 'Encoding', 'UTF-8');
                xlabels = string(T.label);
                yvals = T.avg_speed;
                ylabel = "km/h";
                [xlabels, ylabel] = bms.analyzer.WimPlotService.applyPlotOverrides(name, xlabels, ylabel, plotCfg);
                return;
            end
            if contains(name, "车辆时间分布") && isfield(csvPaths, 'Hourly_Over')
                T = readtable(csvPaths.Hourly_Over, 'TextType', 'string', 'Encoding', 'UTF-8');
                xlabels = string(T.label);
                yvals = T.over_cnt;
                ylabel = "数量";
                thr = double(wim.hourly_critical_weight_kg) / 1000;
                titleText = regexprep(name, "\\d+\\s*t", sprintf('%.0ft', thr));
                [xlabels, ylabel] = bms.analyzer.WimPlotService.applyPlotOverrides(name, xlabels, ylabel, plotCfg);
            end
        end

        function figPx = resolveFigSize(plotCfg, name)
            figPx = plotCfg.fig_size_px;
            if isfield(plotCfg, 'fig_size_per_plot') && isstruct(plotCfg.fig_size_per_plot)
                key = bms.analyzer.WimPlotService.makeFieldKey(name);
                if isfield(plotCfg.fig_size_per_plot, key)
                    figPx = plotCfg.fig_size_per_plot.(key);
                end
            end
            if isfield(plotCfg, 'fig_size_list') && ~isempty(plotCfg.fig_size_list)
                sz = bms.analyzer.WimPlotService.lookupFigSizeList(plotCfg.fig_size_list, name);
                if ~isempty(sz)
                    figPx = sz;
                end
            end
        end

        function plotBarChart(outPath, plotTitle, yLabel, xlabels, yvals, showPct, ~, plotCfg, figPx)
            if isempty(yvals)
                return;
            end
            f = figure('Visible', 'off', 'Units', 'pixels', 'Position', [100 100 figPx(1) figPx(2)]);
            bars = bar(yvals, 'FaceColor', [0 0.447 0.741]);
            grid on;
            if ~isempty(plotTitle)
                title(char(plotTitle), 'Interpreter', 'none', 'FontSize', plotCfg.font_title);
            end
            if ~isempty(yLabel)
                ylabel(char(yLabel), 'Interpreter', 'none', 'FontSize', plotCfg.font_ylabel);
            end
            xlabel('', 'FontSize', plotCfg.font_xlabel);
            xticklabels(cellstr(xlabels));
            ax = gca;
            ax.FontSize = plotCfg.font_tick;
            ax.TickLabelInterpreter = 'none';
            labels = bms.analyzer.WimPlotService.buildXTickLabels(xlabels, yvals, showPct, plotCfg.percent_on_newline);
            ax.XTick = 1:numel(labels);
            ax.XTickLabel = labels;
            if showPct
                ax.XTickLabel = [];
                ax.XTick = 1:numel(labels);
                pos = ax.Position;
                padFrac = 0.10;
                pos(2) = pos(2) + padFrac;
                pos(4) = max(0.1, pos(4) - padFrac);
                ax.Position = pos;
                y = ax.YLim(1) - diff(ax.YLim) * 0.12;
                for i = 1:numel(labels)
                    text(ax.XTick(i), y, labels{i}, ...
                        'HorizontalAlignment', 'center', ...
                        'VerticalAlignment', 'top', ...
                        'FontSize', plotCfg.font_tick, ...
                        'Clipping', 'off');
                end
            else
                ax.XTickLabelRotation = plotCfg.x_label_rotation;
            end
            ax.YAxis.TickLabelFormat = sprintf('%%.%df', plotCfg.y_decimals);
            expVal = ax.YAxis.Exponent;
            if expVal ~= 0
                forceExp = true;
                if isfield(plotCfg, 'force_exponent_label')
                    forceExp = logical(plotCfg.force_exponent_label);
                end
                if forceExp
                    text(ax, 0, 1, sprintf('\\times10^{%d}', expVal), ...
                        'Units', 'normalized', ...
                        'HorizontalAlignment', 'left', ...
                        'VerticalAlignment', 'bottom', ...
                        'FontSize', plotCfg.font_tick, ...
                        'Interpreter', 'tex', ...
                        'Clipping', 'off');
                end
            end
            if plotCfg.value_label
                bms.analyzer.WimPlotService.addBarLabels(bars, yvals, plotCfg.y_decimals, plotCfg.font_value_label);
            end
            drawnow;
            [p, n, ~] = fileparts(outPath);
            figPath = fullfile(p, [n '.fig']);
            hiddenObjects = findall(f, 'Visible', 'off');
            hiddenObjects(arrayfun(@(h) isequal(h, f), hiddenObjects)) = [];
            set(hiddenObjects, 'Visible', 'on');
            if plotCfg.save_fig
                bms.plot.PlotVisibilityPolicy.saveFigVisibleOn(f, figPath);
            else
                figPath = fullfile(tempdir, [n '_' char(java.util.UUID.randomUUID) '.fig']);
                bms.plot.PlotVisibilityPolicy.saveFigVisibleOn(f, figPath);
            end
            close(f);

            f2 = openfig(figPath, 'invisible');
            set(f2, 'Units', 'pixels', 'Position', [100 100 figPx(1) figPx(2)]);
            drawnow;
            padPx = 10;
            if isfield(plotCfg, 'export_padding_px') && ~isempty(plotCfg.export_padding_px)
                padPx = plotCfg.export_padding_px;
            end
            try
                exportgraphics(f2, outPath, 'Resolution', 100, 'BackgroundColor', 'white', 'ContentType', 'image', 'Padding', padPx);
            catch
                exportgraphics(f2, outPath, 'Resolution', 100, 'BackgroundColor', 'white', 'ContentType', 'image');
            end
            close(f2);
            if ~plotCfg.save_fig && exist(figPath, 'file')
                delete(figPath);
            end
        end

        function writePlotSummary(fid, titleText, xlabels, yvals, ~, showPct, plotCfg)
            if isempty(fid) || isempty(yvals)
                return;
            end
            total = sum(yvals);
            [mx, idx] = max(yvals);
            if isstring(xlabels) || iscellstr(xlabels)
                lab = string(xlabels(idx));
            else
                lab = string(idx);
            end
            fprintf(fid, "[%s]\n", titleText);
            fmt = sprintf('%%.%df', plotCfg.y_decimals);
            fprintf(fid, "总量: %s\n", sprintf(fmt, total));
            fprintf(fid, "最大: %s = %s\n", lab, sprintf(fmt, mx));
            if showPct && total > 0
                fprintf(fid, "占比: %s = %.2f%%\n", lab, mx / total * 100);
            end
            fprintf(fid, "\n");
        end

        function labels = buildXTickLabels(xlabels, yvals, showPct, percentOnNewline)
            labels = cellstr(string(xlabels));
            if ~showPct
                return;
            end
            total = sum(yvals);
            if total <= 0
                return;
            end
            pct = yvals ./ total * 100;
            n = numel(xlabels);
            labels = cell(n, 1);
            for i = 1:n
                if percentOnNewline
                    labels{i} = sprintf('%s\n(%.2f%%)', char(string(xlabels(i))), pct(i));
                else
                    labels{i} = sprintf('%s (%.2f%%)', char(string(xlabels(i))), pct(i));
                end
            end
        end

        function name = safeName(name)
            name = regexprep(name, '[\\/:*?\"<>| ]', '_');
        end

        function key = makeFieldKey(name)
            key = regexprep(char(name), '\s+', '_');
            key = regexprep(key, '[^A-Za-z0-9_]', '_');
            if isempty(key)
                key = 'plot';
            end
        end

        function [xlabels, ylabel] = applyPlotOverrides(name, xlabels, ylabel, plotCfg)
            if isfield(plotCfg, 'xlabels') && isstruct(plotCfg.xlabels)
                key = bms.analyzer.WimPlotService.makeFieldKey(name);
                if isfield(plotCfg.xlabels, key)
                    xl = plotCfg.xlabels.(key);
                    if ischar(xl) || isstring(xl)
                        xl = cellstr(xl);
                    end
                    if numel(xl) == numel(xlabels)
                        xlabels = string(xl);
                    end
                end
            end
            if isfield(plotCfg, 'xlabels_list') && ~isempty(plotCfg.xlabels_list)
                xl = bms.analyzer.WimPlotService.lookupLabelList(plotCfg.xlabels_list, name);
                if ~isempty(xl)
                    if ischar(xl) || isstring(xl)
                        xl = cellstr(xl);
                    end
                    if numel(xl) == numel(xlabels)
                        xlabels = string(xl);
                    end
                end
            end
            if isfield(plotCfg, 'ylabels') && isstruct(plotCfg.ylabels)
                key = bms.analyzer.WimPlotService.makeFieldKey(name);
                if isfield(plotCfg.ylabels, key)
                    ylabel = string(plotCfg.ylabels.(key));
                end
            end
            if isfield(plotCfg, 'ylabels_list') && ~isempty(plotCfg.ylabels_list)
                yl = bms.analyzer.WimPlotService.lookupLabelList(plotCfg.ylabels_list, name);
                if ~isempty(yl)
                    ylabel = string(yl);
                end
            end
        end

        function val = lookupLabelList(list, name)
            val = [];
            try
                for i = 1:numel(list)
                    item = list(i);
                    if isfield(item, 'name') && strcmp(string(item.name), string(name))
                        if isfield(item, 'labels')
                            val = item.labels;
                        elseif isfield(item, 'ylabel')
                            val = item.ylabel;
                        end
                        return;
                    end
                end
            catch
            end
        end

        function addBarLabels(bars, yvals, decimals, fontSize)
            fmt = sprintf('%%.%df', decimals);
            if isempty(bars)
                return;
            end
            x = bars(1).XEndPoints;
            y = bars(1).YEndPoints;
            n = min(numel(yvals), numel(x));
            for i = 1:n
                txt = sprintf(fmt, yvals(i));
                text(x(i), y(i), txt, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                    'FontSize', fontSize);
            end
        end

        function sz = lookupFigSizeList(list, name)
            sz = [];
            try
                for i = 1:numel(list)
                    item = list(i);
                    if isfield(item, 'name') && strcmp(string(item.name), string(name))
                        if isfield(item, 'size_px')
                            sz = item.size_px;
                        elseif isfield(item, 'fig_size_px')
                            sz = item.fig_size_px;
                        end
                        return;
                    end
                end
            catch
            end
        end
    end
end
