classdef StructuralFilteredPlotService
    %STRUCTURALFILTEREDPLOTSERVICE Plot helpers for raw/filtered structural data.

    methods (Static)
        function plotTiltCurve(rootDir, dataList, startDate, endDate, suffix, style, warnLines, spec, cfg)
            if isempty(dataList) || ~bms.analyzer.StructuralPlotConfigService.hasPlotData(dataList)
                return;
            end

            [dt0, dt1] = bms.analyzer.StructuralTimeSeriesPlotService.dateRange(startDate, endDate);
            pid = '';
            if numel(dataList) == 1 && isfield(dataList, 'pid')
                pid = dataList(1).pid;
            end

            opts = struct();
            opts.style = style;
            opts.ylabel = bms.analyzer.StructuralPlotConfigService.getStyleField( ...
                style, 'ylabel', spec.defaultYLabel);
            opts.titleText = sprintf('%s %s', ...
                bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'title_prefix', spec.defaultTitlePrefix), ...
                char(string(suffix)));
            opts.outputDir = bms.analyzer.StructuralPlotConfigService.getStyleField( ...
                style, 'output_dir', spec.defaultOutputDir);
            opts.baseName = sprintf('%s_%s_%s_%s_%s', spec.filePrefix, char(string(suffix)), ...
                datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd'), datestr(now, 'yyyymmdd_HHMMSS'));
            opts.warnLines = warnLines;
            opts.moduleKey = spec.moduleKey;
            opts.ylimRange = bms.analyzer.StructuralTimeSeriesPlotService.resolveStyleYLim(style, pid);
            if numel(dataList) == 3
                opts.colorField = 'colors_3';
                opts.defaultColors = [0 0 0; 1 0 0; 0 0 1];
            end

            bms.analyzer.StructuralTimeSeriesPlotService.plotDataList( ...
                rootDir, dataList, startDate, endDate, opts, cfg);
        end

        function plotRecord(rec, rootDir, startDate, endDate, nameTag, style, suffix, spec, cfg, warnLines)
            if nargin < 10
                warnLines = bms.analyzer.StructuralFilteredPlotService.defaultWarnLines(style, cfg, spec, rec.pid);
            end
            bms.analyzer.StructuralFilteredPlotService.plotRecords( ...
                rec, rootDir, startDate, endDate, nameTag, style, suffix, spec, cfg, warnLines);
        end

        function plotRecords(records, rootDir, startDate, endDate, nameTag, style, suffix, spec, cfg, warnLines)
            if nargin < 10
                warnLines = bms.analyzer.StructuralFilteredPlotService.defaultWarnLines(style, cfg, spec, '');
            end
            if isempty(records)
                return;
            end

            valuesField = 'raw';
            suffixTag = bms.analyzer.StructuralFilteredPlotService.fileSuffixTag(suffix);
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
            [titleText, fileNameTag, titleSuffix] = bms.analyzer.StructuralFilteredPlotService.titleParts( ...
                style, spec, nameTag, suffix);
            opts = struct();
            opts.style = style;
            opts.ylabel = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'ylabel', spec.defaultYLabel);
            opts.titleText = titleText;
            opts.outputDir = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'output_dir', spec.defaultOutputDir);
            opts.baseName = bms.analyzer.StructuralFilteredPlotService.baseName( ...
                spec, fileNameTag, suffixTag, dt0, dt1, titleSuffix);
            opts.warnLines = warnLines;
            opts.moduleKey = spec.moduleKey;
            pointId = '';
            if numel(records) == 1
                pointId = records(1).pid;
            end
            opts.ylimRange = bms.analyzer.StructuralTimeSeriesPlotService.resolveStyleYLim(style, pointId);
            opts = bms.analyzer.StructuralFilteredPlotService.applyColorOptions(opts, numel(records));
            bms.analyzer.StructuralTimeSeriesPlotService.plotCells( ...
                rootDir, timesList, valuesList, labels, startDate, endDate, opts, cfg);
        end

        function warnLines = defaultWarnLines(style, cfg, spec, pid)
            if strcmp(spec.moduleKey, 'deflection')
                if ~isempty(pid)
                    warnLines = bms.analyzer.StructuralTimeSeriesPlotService.resolveWarnLines(style, cfg, spec.moduleKey, pid);
                    if ~isempty(warnLines)
                        return;
                    end
                end
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
                    displayTag = bms.analyzer.StructuralPlotConfigService.groupLabel(style, fileNameTag);
                    titleText = sprintf(spec.pointTitlePattern, prefix, displayTag, titleSuffix);
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
    end
end
