classdef WindRoseService
    %WINDROSESERVICE Shared wind-rose data processing helpers.

    methods (Static)
        function [speedAligned, dirAligned] = alignForRose(tSpeed, vSpeed, tDir, vDir)
            if isempty(vSpeed) || isempty(vDir)
                speedAligned = [];
                dirAligned = [];
                return;
            end

            xDir = posixtime(tDir);
            xSpeed = posixtime(tSpeed);
            if numel(unique(xDir)) < 2
                speedAligned = [];
                dirAligned = [];
                return;
            end

            dirInterp = interp1(xDir, vDir, xSpeed, 'nearest', NaN);
            mask = isfinite(vSpeed) & isfinite(dirInterp);
            speedAligned = vSpeed(mask);
            dirAligned = mod(dirInterp(mask), 360);
        end

        function angle = circularMeanDeg(dirDeg)
            if isempty(dirDeg)
                angle = NaN;
                return;
            end

            theta = deg2rad(dirDeg(:));
            s = mean(sin(theta), 'omitnan');
            c = mean(cos(theta), 'omitnan');
            if ~isfinite(s) || ~isfinite(c) || (abs(s) < eps && abs(c) < eps)
                angle = NaN;
                return;
            end
            angle = mod(rad2deg(atan2(s, c)), 360);
        end

        function [mat, sectorEdges, speedEdges, totalCount] = buildMatrix(dirDeg, speed, params)
            dirDeg = mod(dirDeg(:), 360);
            speed = speed(:);
            mask = isfinite(dirDeg) & isfinite(speed);
            dirDeg = dirDeg(mask);
            speed = speed(mask);

            if isempty(dirDeg)
                mat = [];
                sectorEdges = [];
                speedEdges = [];
                totalCount = 0;
                return;
            end

            sectorDeg = bms.analyzer.WindRoseService.paramValue(params, 'sector_deg', 22.5);
            if isempty(sectorDeg) || sectorDeg <= 0
                sectorDeg = 22.5;
            end
            sectorEdges = 0:sectorDeg:360;
            if sectorEdges(end) < 360
                sectorEdges = [sectorEdges 360];
            end

            speedEdges = bms.analyzer.WindRoseService.paramValue(params, 'speed_bins', [0 2 4 6 8 10 15 20 25 30 35 40]);
            speedEdges = speedEdges(:)';
            if isempty(speedEdges)
                speedEdges = [0 2 4 6 8 10 15 20 25 30 35 40];
            end
            speedEdges = unique(speedEdges, 'stable');
            if speedEdges(1) > 0
                speedEdges = [0 speedEdges];
            end
            if speedEdges(end) < max(speed)
                speedEdges = [speedEdges inf];
            end

            sectorIdx = discretize(dirDeg, sectorEdges, 'IncludedEdge', 'right');
            sectorIdx(sectorIdx == 0) = 1;
            binIdx = discretize(speed, speedEdges);

            nSec = numel(sectorEdges) - 1;
            nBin = numel(speedEdges) - 1;
            mat = zeros(nSec, nBin);
            for i = 1:numel(sectorIdx)
                si = sectorIdx(i);
                bi = binIdx(i);
                if ~isnan(si) && ~isnan(bi) && si >= 1 && si <= nSec && bi >= 1 && bi <= nBin
                    mat(si, bi) = mat(si, bi) + 1;
                end
            end

            totalCount = sum(mat, 'all');
            if totalCount > 0
                mat = mat ./ totalCount;
            end
        end

        function labels = speedBinLabels(edges)
            labels = cell(1, numel(edges) - 1);
            for i = 1:numel(labels)
                a = edges(i);
                b = edges(i + 1);
                if isinf(b)
                    labels{i} = sprintf('>=%.0f m/s', a);
                else
                    labels{i} = sprintf('%.0f-%.0f m/s', a, b);
                end
            end
        end

        function summary = summarize(pid, dirDeg, speed, sectorEdges, speedEdges, mat, totalCount)
            summary = struct();
            summary.pid = char(string(pid));
            summary.total_count = totalCount;
            summary.mean_dir = bms.analyzer.WindRoseService.circularMeanDeg(dirDeg);
            summary.mean_speed = mean(speed, 'omitnan');
            summary.max_speed = max(speed, [], 'omitnan');
            summary.dominant_direction = '';
            summary.dominant_direction_ratio = NaN;
            summary.main_speed_bin = '';

            if totalCount <= 0 || isempty(mat)
                return;
            end

            sectorTotals = sum(mat, 2);
            [domVal, domIdx] = max(sectorTotals);
            summary.dominant_direction = sprintf('%.1f°-%.1f°', sectorEdges(domIdx), sectorEdges(domIdx + 1));
            summary.dominant_direction_ratio = domVal;

            binTotals = sum(mat, 1);
            [~, binIdx] = max(binTotals);
            labels = bms.analyzer.WindRoseService.speedBinLabels(speedEdges);
            summary.main_speed_bin = labels{binIdx};
        end

        function writeSummary(outDir, baseName, pid, dirDeg, speed, sectorEdges, speedEdges, mat, totalCount)
            if totalCount <= 0
                return;
            end

            summary = bms.analyzer.WindRoseService.summarize( ...
                pid, dirDeg, speed, sectorEdges, speedEdges, mat, totalCount);
            fid = fopen(fullfile(outDir, [baseName '_summary.txt']), 'w', 'n', 'UTF-8');
            if fid < 0
                return;
            end
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, '风玫瑰简要结论（%s）\n', summary.pid);
            fprintf(fid, '样本总数: %d\n', summary.total_count);
            if isfinite(summary.mean_dir)
                fprintf(fid, '平均风向: %.1f°\n', summary.mean_dir);
            end
            fprintf(fid, '主导风向: %s，占比 %.1f%%\n', ...
                summary.dominant_direction, summary.dominant_direction_ratio * 100);
            fprintf(fid, '平均风速: %.2f m/s\n', summary.mean_speed);
            fprintf(fid, '最大风速: %.2f m/s\n', summary.max_speed);
            fprintf(fid, '主要风速等级: %s（依据：全样本风速分级占比最高）\n', summary.main_speed_bin);
        end

        function value = paramValue(params, field, defaultValue)
            value = defaultValue;
            if isstruct(params) && isfield(params, field) && ~isempty(params.(field))
                value = params.(field);
            end
        end
    end
end
