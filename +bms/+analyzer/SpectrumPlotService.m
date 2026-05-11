classdef SpectrumPlotService
    %SPECTRUMPLOTSERVICE Plot helpers for spectrum and cable force outputs.

    methods (Static)
        function plotFrequencyTimeseries(datesAll, freqDay, pid, targetFreqs, outDir, style, theorFreqs, theorLabels, cfg)
            fig = figure('Visible', 'off', 'Position', [100 100 1000 470]);
            hold on;
            colors = bms.analyzer.SpectrumPlotService.normalizeColors(style.colors);
            h = gobjects(numel(targetFreqs), 1);
            hasLine = false(numel(targetFreqs), 1);
            for k = 1:numel(targetFreqs)
                [datesPlot, freqPlot] = prepare_plot_series(datesAll, freqDay(:, k));
                if isempty(datesPlot) || isempty(freqPlot) || ~any(isfinite(freqPlot))
                    continue;
                end
                if k <= numel(colors)
                    h(k) = plot(datesPlot, freqPlot, 'LineWidth', 1.2, 'Color', colors{k});
                else
                    h(k) = plot(datesPlot, freqPlot, 'LineWidth', 1.2);
                end
                hasLine(k) = isgraphics(h(k));
            end
            grid on;
            xtickformat('yyyy-MM-dd');
            xlabel('日期');
            ylabel(style.freq_ylabel);
            labels = arrayfun(@(k, f) sprintf('峰%d (%.3fHz)', k, f), (1:numel(targetFreqs)).', targetFreqs(:), 'UniformOutput', false);
            if any(hasLine)
                legend(h(hasLine), labels(hasLine), 'Location', 'eastoutside');
            end
            title(sprintf('%s %s', style.freq_title_prefix, pid));

            bms.analyzer.SpectrumPlotService.applyFrequencyYLim(freqDay, theorFreqs);
            bms.analyzer.SpectrumPlotService.drawTheoreticalLines(datesAll, theorFreqs, theorLabels, h);
            hold off;

            baseName = sprintf('SpecFreq_%s_%s_%s', pid, datestr(datesAll(1), 'yyyymmdd'), datestr(datesAll(end), 'yyyymmdd'));
            bms.plot.PlotService.saveModuleBundle(fig, outDir, baseName, cfg);
        end

        function applyFrequencyYLim(freqDay, theorFreqs)
            if nargin < 2 || isempty(theorFreqs)
                theorFreqs = [];
            end
            dataMin = min(freqDay, [], 'all', 'omitnan');
            dataMax = max(freqDay, [], 'all', 'omitnan');
            if isempty(dataMin) || isempty(dataMax) || ~isfinite(dataMin) || ~isfinite(dataMax)
                return;
            end
            valsMin = dataMin;
            valsMax = dataMax;
            if ~isempty(theorFreqs)
                valsMin = min([valsMin; theorFreqs(:)]);
                valsMax = max([valsMax; theorFreqs(:)]);
            end
            pad = max(0.02, 0.05 * (valsMax - valsMin));
            ylim([valsMin - 0.5 * pad, valsMax + 1.5 * pad]);
        end

        function drawTheoreticalLines(datesAll, theorFreqs, theorLabels, h)
            if isempty(theorFreqs)
                return;
            end
            ax = gca;
            if numel(datesAll) >= 2
                xoff = (datesAll(end) - datesAll(1)) * 0.01;
            else
                xoff = days(1);
            end
            yoff = diff(ylim(ax)) * 0.02;
            xleft = datesAll(1);

            for k = 1:numel(theorFreqs)
                c = [0 0 0];
                if k <= numel(h) && isgraphics(h(k))
                    c = get(h(k), 'Color');
                end
                yline(theorFreqs(k), '--', 'Color', c, 'LineWidth', 1, 'HandleVisibility', 'off');
                text(xleft + xoff, theorFreqs(k) + yoff, theorLabels{k}, ...
                    'Color', c, 'FontSize', 9, 'VerticalAlignment', 'bottom');
            end
        end

        function plotForceTimeseries(timesList, forceList, labels, nameTag, outDir, style, forceYLim, warnLineSets, cfg)
            valid = false(numel(forceList), 1);
            for i = 1:numel(forceList)
                valid(i) = ~isempty(forceList{i}) && any(isfinite(forceList{i}));
            end
            if ~any(valid)
                warning('测点/组 %s 索力全为 NaN，跳过绘图', nameTag);
                return;
            end

            fig = figure('Visible', 'off', 'Position', [100 100 1000 470]);
            hold on;
            colors = bms.analyzer.SpectrumPlotService.normalizeColors(style.colors);
            h = gobjects(numel(forceList), 1);
            for i = 1:numel(forceList)
                if ~valid(i)
                    continue;
                end
                if isscalar(forceList)
                    c = style.force_color;
                elseif i <= numel(colors)
                    c = colors{i};
                else
                    cmap = lines(numel(forceList));
                    c = cmap(i, :);
                end
                [timesPlot, forcePlot] = prepare_plot_series(timesList{i}, forceList{i});
                if isempty(timesPlot) || isempty(forcePlot) || ~any(isfinite(forcePlot))
                    continue;
                end
                h(i) = plot(timesPlot, forcePlot, 'LineWidth', 1.2, 'Color', c);
            end
            grid on;
            xtickformat('yyyy-MM-dd');
            xlabel('日期');
            ylabel(style.force_ylabel);
            title(sprintf('%s %s', style.force_title_prefix, nameTag));

            goodLines = h(isgraphics(h));
            if numel(goodLines) > 1
                legend(goodLines, labels(valid), 'Location', 'eastoutside');
            end

            allWarnLines = bms.analyzer.SpectrumPlotService.drawWarnLines(warnLineSets);
            bms.analyzer.SpectrumPlotService.applyForceYLim(forceList, valid, forceYLim, allWarnLines);

            firstIdx = find(valid, 1, 'first');
            dt0 = timesList{firstIdx}(1);
            dt1 = timesList{firstIdx}(end);
            safeName = bms.analyzer.StructuralPlotConfigService.sanitizeFilename(strrep(nameTag, ' ', '_'));
            baseName = sprintf('CableForce_%s_%s_%s', safeName, datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd'));
            bms.plot.PlotService.saveModuleBundle(fig, outDir, baseName, cfg);
        end

        function allWarnLines = drawWarnLines(warnLineSets)
            allWarnLines = {};
            if nargin < 1 || isempty(warnLineSets)
                return;
            end
            for i = 1:numel(warnLineSets)
                warnLines = warnLineSets{i};
                if isempty(warnLines)
                    continue;
                end
                for k = 1:numel(warnLines)
                    wl = warnLines{k};
                    if ~isstruct(wl) || ~isfield(wl, 'y') || ~isnumeric(wl.y) || ~isfinite(wl.y)
                        continue;
                    end
                    yl = yline(wl.y, '--', bms.analyzer.CableForceService.warnLabel(wl), 'LabelHorizontalAlignment', 'left');
                    if isfield(wl, 'color') && isnumeric(wl.color) && numel(wl.color) == 3
                        yl.Color = reshape(wl.color, 1, 3);
                    end
                    yl.LineWidth = 1.0;
                    allWarnLines{end+1, 1} = wl; %#ok<AGROW>
                end
            end
        end

        function applyForceYLim(forceList, valid, forceYLim, warnLines)
            if nargin >= 3 && ~isempty(forceYLim)
                ylim(forceYLim);
                return;
            end

            dataMin = NaN;
            dataMax = NaN;
            for i = 1:numel(forceList)
                if ~valid(i)
                    continue;
                end
                dataMin = min([dataMin; min(forceList{i}, [], 'all', 'omitnan')], [], 'omitnan');
                dataMax = max([dataMax; max(forceList{i}, [], 'all', 'omitnan')], [], 'omitnan');
            end
            warnVals = bms.analyzer.SpectrumPlotService.warnValues(warnLines);
            if ~isempty(warnVals)
                dataMin = min([dataMin; warnVals(:)], [], 'omitnan');
                dataMax = max([dataMax; warnVals(:)], [], 'omitnan');
            end
            if isfinite(dataMin) && isfinite(dataMax)
                pad = max(0.02, 0.05 * (dataMax - dataMin));
                ylim([dataMin - 0.5 * pad, dataMax + 1.5 * pad]);
            end
        end

        function vals = warnValues(warnLines)
            vals = [];
            for i = 1:numel(warnLines)
                wl = warnLines{i};
                if isstruct(wl) && isfield(wl, 'y') && isnumeric(wl.y) && isfinite(wl.y)
                    vals(end+1, 1) = wl.y; %#ok<AGROW>
                end
            end
        end

        function plotCableForceGroups(cfg, pointIds, datesAll, forceSeriesAll, forceValidAll, outDir, style)
            groupsCfg = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, 'cable_force', struct());
            groups = bms.analyzer.StructuralPlotConfigService.normalizeGroupMap(groupsCfg);
            groupNames = fieldnames(groups);
            for gi = 1:numel(groupNames)
                groupName = groupNames{gi};
                pidList = groups.(groupName);
                if isempty(pidList)
                    continue;
                end

                forceList = {};
                labels = {};
                for pi = 1:numel(pidList)
                    idx = find(strcmp(pointIds, pidList{pi}), 1, 'first');
                    if isempty(idx) || ~forceValidAll(idx)
                        continue;
                    end
                    forceList{end+1, 1} = forceSeriesAll{idx}; %#ok<AGROW>
                    labels{end+1, 1} = pidList{pi}; %#ok<AGROW>
                end
                if isempty(labels)
                    continue;
                end

                warnLineSets = cell(numel(labels), 1);
                for pi = 1:numel(labels)
                    warnLineSets{pi} = bms.analyzer.CableForceService.warnLines(cfg, labels{pi}, style, labels{pi});
                end
                groupDisplayName = bms.analyzer.SpectrumPlotService.groupDisplayName(groupName, labels);
                bms.analyzer.SpectrumPlotService.plotForceTimeseries( ...
                    repmat({datesAll}, numel(labels), 1), forceList, labels, groupDisplayName, outDir, style, [], warnLineSets, cfg);
            end
        end

        function name = groupDisplayName(groupName, labels)
            labels = labels(~cellfun(@isempty, labels));
            if isempty(labels)
                name = groupName;
            elseif numel(labels) <= 4
                name = strjoin(labels(:).', '-');
            else
                name = groupName;
            end
        end

        function colors = normalizeColors(raw)
            colors = bms.plot.PlotService.normalizeColors(raw, {});
        end
    end
end
