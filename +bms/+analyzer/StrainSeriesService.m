classdef StrainSeriesService
    %STRAINSERIESSERVICE Data collection and stats for strain analysis.

    methods (Static)
        function rows = runPoints(rootDir, subfolder, startDate, endDate, cfg, ctx, rows)
            for i = 1:numel(ctx.points)
                bms.app.StopController.throwIfRequested('Stop requested before next strain point');
                pid = ctx.points{i};
                fprintf('Per-point strain: %s ...\n', pid);
                data = bms.analyzer.StructuralSeriesService.loadPoint( ...
                    rootDir, subfolder, pid, startDate, endDate, cfg, 'strain');
                if isempty(data.vals)
                    warning('Strain point %s has no data, skip', pid);
                    continue;
                end

                rows(end+1, :) = bms.analyzer.StructuralSeriesService.basicStatsRow( ...
                    pid, data.vals, 3); %#ok<AGROW>

                warnLines = bms.analyzer.StrainConfigService.resolveWarnLines(ctx.style, cfg, pid);
                bms.analyzer.StrainPlotService.plotPointCurve( ...
                    rootDir, data.times, data.vals, startDate, endDate, pid, ctx.style, warnLines, cfg);
            end
        end

        function [rows, plottedGroups] = runTimeseriesGroups(rootDir, subfolder, startDate, endDate, cfg, ctx, rows)
            plottedGroups = {};
            groupsMap = bms.analyzer.StrainConfigService.normalizeGroupMap(ctx.ts_groups);
            names = fieldnames(groupsMap);
            for i = 1:numel(names)
                bms.app.StopController.throwIfRequested('Stop requested before next strain timeseries group');
                groupName = names{i};
                [dataList, groupRows] = bms.analyzer.StrainSeriesService.collectGroupData( ...
                    rootDir, subfolder, groupsMap.(groupName), startDate, endDate, cfg);
                if isempty(dataList)
                    continue;
                end

                if ~ctx.explicit_points && ~ctx.explicit_groups
                    rows = [rows; groupRows]; %#ok<AGROW>
                end
                bms.analyzer.StrainPlotService.plotGroupTimeseries( ...
                    rootDir, dataList, startDate, endDate, groupName, ctx.style, cfg);
                plottedGroups{end+1, 1} = groupName; %#ok<AGROW>
            end
        end

        function [rows, plottedGroups] = runBoxplotGroups(rootDir, subfolder, startDate, endDate, cfg, ctx, rows)
            plottedGroups = {};
            groupsMap = bms.analyzer.StrainConfigService.normalizeGroupMap(ctx.groups);
            names = fieldnames(groupsMap);
            for i = 1:numel(names)
                bms.app.StopController.throwIfRequested('Stop requested before next strain boxplot group');
                groupName = names{i};
                [dataList, groupRows] = bms.analyzer.StrainSeriesService.collectGroupData( ...
                    rootDir, subfolder, groupsMap.(groupName), startDate, endDate, cfg);
                if isempty(dataList)
                    continue;
                end

                if ~ctx.explicit_points
                    rows = [rows; groupRows]; %#ok<AGROW>
                end
                bms.analyzer.StrainPlotService.plotGroupBoxplot( ...
                    rootDir, dataList, startDate, endDate, groupName, ctx.style, cfg);
                plottedGroups{end+1, 1} = groupName; %#ok<AGROW>
            end
        end

        function [dataList, statsRows] = collectGroupData(rootDir, subfolder, pointIds, startDate, endDate, cfg)
            [dataList, statsRows] = bms.analyzer.StructuralSeriesService.collectPoints( ...
                rootDir, subfolder, pointIds, startDate, endDate, cfg, 'strain', 3, 'Strain point');
        end
    end
end
