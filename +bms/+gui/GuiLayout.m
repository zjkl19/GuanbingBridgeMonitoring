classdef GuiLayout
    %GUILAYOUT Shared layout constants for the MATLAB GUI.

    methods (Static)
        function pos = mainWindowPosition(screenRect)
            % Return a screen-aware default position that keeps the status
            % summary and log panes visible on common 1080p/2K displays.
            if nargin < 1 || isempty(screenRect)
                screenRect = get(groot, 'ScreenSize');
            end
            screenRect = double(screenRect);
            if numel(screenRect) < 4
                screenRect = [1 1 1440 900];
            end

            desired = [1380 900];
            minimum = [1180 760];
            margin = [40 70];
            available = [max(800, screenRect(3) - 2 * margin(1)), ...
                max(650, screenRect(4) - 2 * margin(2))];

            sizePx = min(desired, available);
            sizePx = max(sizePx, min(minimum, available));

            x = screenRect(1) + max(20, floor((screenRect(3) - sizePx(1)) / 2));
            y = screenRect(2) + max(40, floor((screenRect(4) - sizePx(2)) / 2));
            pos = [x y sizePx(1) sizePx(2)];
        end

        function heights = runPageRowHeights()
            heights = {104,30,30,30,30,30,30,30,30,30,30,30,30,30,24,110,'1x'};
        end

        function applyRunGridDefaults(grid)
            grid.RowHeight = bms.gui.GuiLayout.runPageRowHeights();
            grid.ColumnWidth = {190,240,240,'1x'};
            grid.Padding = [12 10 12 10];
            grid.RowSpacing = 4;
            grid.ColumnSpacing = 8;
            if isprop(grid, 'Scrollable')
                grid.Scrollable = 'on';
            end
        end
    end
end
