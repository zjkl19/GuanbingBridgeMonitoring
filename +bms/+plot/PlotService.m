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
    end
end
