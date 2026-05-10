classdef WimTrafficAggregationService
    %WIMTRAFFICAGGREGATIONSERVICE Direct WIM traffic statistics aggregation.

    methods (Static)
        function acc = initAccumulators(wim, startDate, endDate)
            t0 = datenum(startDate, 'yyyy-mm-dd');
            t1 = datenum(endDate, 'yyyy-mm-dd') + 1;
            dayVec = (datetime(startDate):days(1):datetime(endDate)).';
            nDays = numel(dayVec);

            lanes = double(wim.lanes(:))';
            upLanes = double(wim.up_lanes(:))';
            speedEdges = double(wim.speed_bins(:))';
            grossEdges = double(wim.gross_bins(:))';
            hourEdges = double(wim.hour_bins(:))';
            customWeights = double(wim.custom_weights(:))';
            criticalLanes = double(wim.critical_lanes(:))';

            acc = struct();
            acc.t0 = t0;
            acc.t1 = t1;
            acc.days = dayVec;
            acc.daily_up = zeros(nDays, 1);
            acc.daily_down = zeros(nDays, 1);
            acc.daily_total = zeros(nDays, 1);

            acc.lanes = lanes;
            acc.lane_counts = zeros(numel(lanes), 1);
            acc.lane_map = containers.Map(num2cell(lanes), num2cell(1:numel(lanes)));
            acc.up_lane_set = containers.Map(num2cell(upLanes), num2cell(true(size(upLanes))));

            acc.speed_edges = speedEdges;
            acc.speed_counts = zeros(numel(speedEdges) - 1, 1);
            acc.gross_edges = grossEdges;
            acc.gross_counts = zeros(numel(grossEdges) - 1, 1);
            acc.lane_gross_counts = zeros(numel(lanes), numel(grossEdges) - 1);

            acc.hour_edges = hourEdges;
            acc.hour_counts = zeros(numel(hourEdges) - 1, 1);
            acc.hour_speed_sum = zeros(numel(hourEdges) - 1, 1);
            acc.hour_speed_cnt = zeros(numel(hourEdges) - 1, 1);
            acc.hour_over_cnt = zeros(numel(hourEdges) - 1, 1);
            acc.hour_critical_weight = double(wim.hourly_critical_weight_kg);

            acc.custom_weights = customWeights;
            acc.custom_overall = zeros(numel(customWeights), 1);
            acc.critical_lanes = criticalLanes;
            acc.custom_per_lane = zeros(numel(criticalLanes), numel(customWeights));

            acc.topn = bms.analyzer.WimAccumulatorService.initTopN(double(wim.topn));
            acc.topn_max_axle = bms.analyzer.WimAccumulatorService.initTopN(double(wim.topn));
            acc.topn_raw_headers = {};

            acc.overload_factors = double(wim.overload_factors(:))';
            acc.design_total = double(wim.design_total_kg);
            acc.design_axle = double(wim.design_axle_kg);
            acc.overload_counts = zeros(2, numel(acc.overload_factors));
        end

        function tf = isInRange(acc, timeDatenum)
            tf = ~isempty(timeDatenum) && isfinite(timeDatenum) && timeDatenum >= acc.t0 && timeDatenum < acc.t1;
        end

        function tf = qualifiesForMaxAxleTopN(acc, axleWeights, timeDatenum)
            [maxAxle, ~] = max(axleWeights, [], 'omitnan');
            tf = bms.analyzer.WimAccumulatorService.qualifiesForTopN(acc.topn_max_axle, maxAxle, timeDatenum);
        end

        function acc = addRecord(acc, timeDatenum, lane, gross, speed, axleWeights, axleNum, plate, axleDistances, rawRow, rawHeaders)
            if nargin < 10
                rawRow = [];
            end
            if nargin < 11
                rawHeaders = {};
            end

            acc = bms.analyzer.WimTrafficAggregationService.updateAccumulators( ...
                acc, timeDatenum, lane, gross, speed, axleWeights, axleNum);
            acc = bms.analyzer.WimTrafficAggregationService.updateOverload(acc, gross, axleWeights);

            stdRow = bms.analyzer.WimAccumulatorService.standardRow( ...
                lane, timeDatenum, axleNum, gross, speed, plate, axleWeights, axleDistances);
            acc.topn = bms.analyzer.WimAccumulatorService.updateTopN(acc.topn, gross, timeDatenum, stdRow, []);

            [maxAxle, ~] = max(axleWeights, [], 'omitnan');
            if ~isempty(rawHeaders) && ~isempty(rawRow)
                acc.topn_raw_headers = rawHeaders;
            end
            acc.topn_max_axle = bms.analyzer.WimAccumulatorService.updateTopN( ...
                acc.topn_max_axle, maxAxle, timeDatenum, stdRow, rawRow);
        end

        function acc = updateAccumulators(acc, timeDatenum, lane, gross, speed, ~, ~)
            dayIdx = floor(timeDatenum) - floor(acc.t0) + 1;
            if dayIdx >= 1 && dayIdx <= numel(acc.daily_total)
                acc.daily_total(dayIdx) = acc.daily_total(dayIdx) + 1;
                if isfinite(lane) && isKey(acc.up_lane_set, lane)
                    acc.daily_up(dayIdx) = acc.daily_up(dayIdx) + 1;
                else
                    acc.daily_down(dayIdx) = acc.daily_down(dayIdx) + 1;
                end
            end

            if isfinite(lane) && isKey(acc.lane_map, lane)
                li = acc.lane_map(lane);
                acc.lane_counts(li) = acc.lane_counts(li) + 1;
            end

            if isfinite(speed)
                bi = bms.analyzer.WimAccumulatorService.findBin(speed, acc.speed_edges);
                if bi > 0, acc.speed_counts(bi) = acc.speed_counts(bi) + 1; end
            end

            if isfinite(gross)
                bi = bms.analyzer.WimAccumulatorService.findBin(gross, acc.gross_edges);
                if bi > 0
                    acc.gross_counts(bi) = acc.gross_counts(bi) + 1;
                    if isfinite(lane) && isKey(acc.lane_map, lane)
                        li = acc.lane_map(lane);
                        acc.lane_gross_counts(li, bi) = acc.lane_gross_counts(li, bi) + 1;
                    end
                end
            end

            hh = floor(mod(timeDatenum, 1) * 24);
            bi = bms.analyzer.WimAccumulatorService.findBin(hh, acc.hour_edges);
            if bi > 0
                acc.hour_counts(bi) = acc.hour_counts(bi) + 1;
                if isfinite(speed)
                    acc.hour_speed_sum(bi) = acc.hour_speed_sum(bi) + speed;
                    acc.hour_speed_cnt(bi) = acc.hour_speed_cnt(bi) + 1;
                end
                if isfinite(gross) && gross >= acc.hour_critical_weight
                    acc.hour_over_cnt(bi) = acc.hour_over_cnt(bi) + 1;
                end
            end

            if isfinite(gross)
                for i = 1:numel(acc.custom_weights)
                    if gross >= acc.custom_weights(i)
                        acc.custom_overall(i) = acc.custom_overall(i) + 1;
                    end
                end
                for li = 1:numel(acc.critical_lanes)
                    if isfinite(lane) && lane == acc.critical_lanes(li)
                        for i = 1:numel(acc.custom_weights)
                            if gross >= acc.custom_weights(i)
                                acc.custom_per_lane(li, i) = acc.custom_per_lane(li, i) + 1;
                            end
                        end
                        break;
                    end
                end
            end
        end

        function acc = updateOverload(acc, gross, axleWeights)
            if ~isfinite(gross), return; end
            for i = 1:numel(acc.overload_factors)
                if gross >= acc.design_total * acc.overload_factors(i)
                    acc.overload_counts(1, i) = acc.overload_counts(1, i) + 1;
                end
            end
            maxAxle = max(axleWeights, [], 'omitnan');
            if isfinite(maxAxle)
                for i = 1:numel(acc.overload_factors)
                    if maxAxle >= acc.design_axle * acc.overload_factors(i)
                        acc.overload_counts(2, i) = acc.overload_counts(2, i) + 1;
                    end
                end
            end
        end

        function reports = buildReportTables(acc)
            reports = struct();
            reports.DailyTraffic = table(acc.days, acc.daily_up, acc.daily_down, acc.daily_total, ...
                'VariableNames', {'date','up_cnt','down_cnt','total'});

            reports.LaneSpeedWeight_Lane = table(acc.lanes(:), acc.lane_counts(:), ...
                'VariableNames', {'lane','count'});
            [labels, counts] = bms.analyzer.WimReportTableService.binTable(acc.speed_edges, acc.speed_counts);
            reports.LaneSpeedWeight_Speed = table((1:numel(counts)).', labels, counts, ...
                'VariableNames', {'bin_id','label','count'});
            [labels, counts] = bms.analyzer.WimReportTableService.binTable(acc.gross_edges, acc.gross_counts);
            reports.LaneSpeedWeight_Gross = table((1:numel(counts)).', labels, counts, ...
                'VariableNames', {'bin_id','label','count'});

            [labels2, ~] = bms.analyzer.WimReportTableService.binTable(acc.gross_edges, acc.gross_counts);
            [laneGrid, binGrid] = ndgrid(acc.lanes(:), 1:numel(labels2));
            labelGrid = repmat(labels2(:).', numel(acc.lanes), 1);
            reports.LaneSpeedWeight_GrossPerLane = table( ...
                laneGrid(:), binGrid(:), labelGrid(:), acc.lane_gross_counts(:), ...
                'VariableNames', {'lane','bin_id','label','count'});

            [labels, counts] = bms.analyzer.WimReportTableService.binTable(acc.hour_edges, acc.hour_counts);
            avgSpeed = acc.hour_speed_sum ./ acc.hour_speed_cnt;
            avgSpeed(acc.hour_speed_cnt == 0) = NaN;
            reports.Hourly_Count = table((1:numel(counts)).', labels, counts, ...
                'VariableNames', {'bin_id','label','count'});
            reports.Hourly_AvgSpeed = table((1:numel(counts)).', labels, avgSpeed, ...
                'VariableNames', {'bin_id','label','avg_speed'});
            reports.Hourly_Over = table((1:numel(counts)).', labels, acc.hour_over_cnt, ...
                'VariableNames', {'bin_id','label','over_cnt'});

            reports.CustomThresholds_Overall = table(acc.custom_weights(:), acc.custom_overall(:), ...
                'VariableNames', {'weight_threshold','over_cnt'});
            [laneGrid, weightGrid] = ndgrid(acc.critical_lanes, acc.custom_weights);
            perLane = reshape(acc.custom_per_lane, numel(acc.critical_lanes) * numel(acc.custom_weights), 1);
            reports.CustomThresholds_PerLane = table(laneGrid(:), weightGrid(:), perLane, ...
                'VariableNames', {'lane','weight_threshold','over_cnt'});

            reports.TopN = bms.analyzer.WimReportTableService.buildTopNTable(acc.topn);
            reports.TopN_MaxAxle = bms.analyzer.WimReportTableService.buildTopNTable(acc.topn_max_axle);

            if ~isempty(acc.topn_raw_headers) && ~isempty(acc.topn_max_axle.raw_rows)
                reports.TopN_MaxAxle_Raw = bms.analyzer.WimReportTableService.buildRawTopNTable( ...
                    acc.topn_raw_headers, acc.topn_max_axle.raw_rows);
            else
                reports.TopN_MaxAxle_Raw = table();
            end

            factors = acc.overload_factors(:);
            totalThr = acc.design_total * factors;
            axleThr = acc.design_axle * factors;
            reports.Overload_Summary = table( ...
                [repmat({'total'}, numel(factors), 1); repmat({'axle'}, numel(factors), 1)], ...
                [totalThr; axleThr], ...
                [acc.overload_counts(1,:).'; acc.overload_counts(2,:).'], ...
                'VariableNames', {'type','threshold_kg','count'});
        end
    end
end
