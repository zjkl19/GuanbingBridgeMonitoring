classdef StructuralFilteredSeriesService
    %STRUCTURALFILTEREDSERIESSERVICE Loading, filtering and stats helpers.

    methods (Static)
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
            records = bms.analyzer.StructuralFilteredSeriesService.collectRecordsOnly( ...
                rootDir, subfolder, pointIds, startDate, endDate, cfg, spec);
            rows = cell(0, 7);
            for i = 1:numel(records)
                rows(end+1, :) = bms.analyzer.StructuralFilteredSeriesService.statsRow(records(i), spec); %#ok<AGROW>
            end
        end

        function records = collectRecordsOnly(rootDir, subfolder, pointIds, startDate, endDate, cfg, spec)
            records = repmat(bms.analyzer.StructuralFilteredSeriesService.emptyRecord(), 0, 1);
            for i = 1:numel(pointIds)
                pid = pointIds{i};
                rec = bms.analyzer.StructuralFilteredSeriesService.loadFilteredPoint( ...
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

        function groups = legacyTiltGroups()
            groups = struct( ...
                'X', {{'GB-DIS-P04-001-01-X', 'GB-DIS-P05-001-01-X', 'GB-DIS-P06-001-01-X'}}, ...
                'Y', {{'GB-DIS-P04-001-01-Y', 'GB-DIS-P05-001-01-Y', 'GB-DIS-P06-001-01-Y'}});
        end

        function groups = deflectionGroups(cfg, spec)
            groups = {};
            raw = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, spec.groupKey, {});
            if bms.analyzer.StructuralPlotConfigService.hasGroups(raw)
                groups = bms.analyzer.StructuralFilteredSeriesService.groupsAsCell(raw);
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
