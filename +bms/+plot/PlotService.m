classdef PlotService
    %PLOTSERVICE Thin facade for plot output naming/saving conventions.

    methods (Static)
        function name = outputBase(baseName, appendTimestamp, timestamp)
            if nargin < 2, appendTimestamp = false; end
            if nargin < 3 || isempty(timestamp), timestamp = datestr(now, 'yyyymmdd_HHMMSS'); end
            name = char(baseName);
            if appendTimestamp
                name = [name '_' char(timestamp)];
            end
        end

        function saveBundle(fig, outDir, baseName, opts)
            if nargin < 4, opts = struct(); end
            save_plot_bundle(fig, outDir, baseName, opts);
        end

        function saveBundleWithTimestamp(fig, outDir, baseName, opts)
            if nargin < 4, opts = struct(); end
            bms.plot.PlotService.saveBundle(fig, outDir, ...
                bms.plot.PlotService.outputBase(baseName, true), opts);
        end

        function [xPlot, yPlot] = prepareSeries(x, y, opts)
            if nargin < 3, opts = struct(); end
            [xPlot, yPlot] = prepare_plot_series(x, y, opts);
        end

        function setTimeAxis(times)
            if isempty(times)
                return;
            end
            times = times(:);
            if isdatetime(times)
                valid = ~isnat(times);
            else
                valid = isfinite(times);
            end
            if ~any(valid)
                return;
            end
            t = times(valid);
            xmin = min(t);
            xmax = max(t);
            if bms.plot.PlotService.isSameLimit(xmin, xmax)
                if isdatetime(t)
                    xmin = xmin - minutes(1);
                    xmax = xmax + minutes(1);
                else
                    xmin = xmin - 1;
                    xmax = xmax + 1;
                end
            end

            ax = gca;
            ax.XLim = [xmin xmax];
            ticks = bms.plot.PlotService.makeTicks(xmin, xmax, 5);
            if numel(ticks) >= 2
                ax.XTick = ticks;
            else
                ax.XTickMode = 'auto';
            end
            if isdatetime(t)
                if days(xmax - xmin) >= 1
                    xtickformat('yyyy-MM-dd');
                else
                    xtickformat('MM-dd HH:mm');
                end
            end
        end

        function ticks = makeTicks(xmin, xmax, n)
            if nargin < 3, n = 5; end
            if isdatetime(xmin)
                ticks = datetime(linspace(posixtime(xmin), posixtime(xmax), n), 'ConvertFrom', 'posixtime');
                ticks = unique(ticks, 'stable');
                if numel(ticks) >= 2 && ~all(diff(ticks) > duration(0,0,0))
                    ticks = ticks([]);
                end
            else
                ticks = unique(linspace(double(xmin), double(xmax), n), 'stable');
                if numel(ticks) >= 2 && ~all(diff(ticks) > 0)
                    ticks = [];
                end
            end
        end

        function tf = isSameLimit(a, b)
            if isdatetime(a)
                tf = a == b;
            else
                tf = double(a) == double(b);
            end
        end
    end
end
