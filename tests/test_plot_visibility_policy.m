classdef test_plot_visibility_policy < matlab.unittest.TestCase
    properties
        ProjectRoot
        TempDir
        OriginalDefault
        OriginalFigures
    end

    methods (TestMethodSetup)
        function setupCase(tc)
            tc.ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(tc.ProjectRoot, fullfile(tc.ProjectRoot, 'pipeline'));
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            tc.OriginalDefault = char(string(get(groot, 'DefaultFigureVisible')));
            tc.OriginalFigures = findall(groot, 'Type', 'figure');
        end
    end

    methods (TestMethodTeardown)
        function teardownCase(tc)
            current = findall(groot, 'Type', 'figure');
            for i = 1:numel(current)
                if ~any(arrayfun(@(h) isequal(h, current(i)), tc.OriginalFigures))
                    try
                        close(current(i));
                    catch
                    end
                end
            end
            set(groot, 'DefaultFigureVisible', tc.OriginalDefault);
            if exist(tc.TempDir, 'dir')
                rmdir(tc.TempDir, 's');
            end
        end
    end

    methods (Test)
        function backgroundModeHidesNewFiguresAndRestoresRoot(tc)
            set(groot, 'DefaultFigureVisible', 'on');
            [guard, state] = bms.plot.PlotVisibilityPolicy.enter('background');
            tc.verifyTrue(isa(guard, 'onCleanup'));
            tc.verifyEqual(state.mode, 'background');
            tc.verifyEqual(char(string(get(groot, 'DefaultFigureVisible'))), 'off');

            fig = figure();
            tc.verifyEqual(char(string(fig.Visible)), 'off');
            close(fig);
            clear guard;

            tc.verifyEqual(char(string(get(groot, 'DefaultFigureVisible'))), 'on');
        end

        function interactiveModePreservesUserPreference(tc)
            set(groot, 'DefaultFigureVisible', 'off');
            [guard, state] = bms.plot.PlotVisibilityPolicy.enter('interactive');
            tc.verifyTrue(isa(guard, 'onCleanup'));
            tc.verifyEqual(state.mode, 'interactive');
            tc.verifyEqual(state.original_default, 'off');
            tc.verifyEqual(char(string(get(groot, 'DefaultFigureVisible'))), 'off');
            clear guard;
            tc.verifyEqual(char(string(get(groot, 'DefaultFigureVisible'))), 'off');
        end

        function currentProcessDetectionMatchesMatlabStartup(tc)
            [background, reason] = bms.plot.PlotVisibilityPolicy.detectBackgroundProcess();
            if isdeployed
                tc.verifyTrue(background);
                tc.verifyEqual(reason, 'compiled_runner');
            elseif batchStartupOptionUsed
                tc.verifyTrue(background);
                tc.verifyEqual(reason, 'matlab_batch');
            else
                tc.verifyFalse(background);
                tc.verifyEqual(reason, 'interactive_matlab');
            end
        end

        function saveFigPersistsVisibleWithoutShowingLiveFigure(tc)
            figPath = fullfile(tc.TempDir, 'hidden_saved_visible.fig');
            fig = figure('Visible', 'off', 'Position', [120 140 640 360]);
            ax = axes(fig);
            plot(ax, 1:5, [1 4 2 5 3], 'LineWidth', 1.25);
            title(ax, 'visibility regression');
            figureCount = numel(findall(groot, 'Type', 'figure'));

            bms.plot.PlotVisibilityPolicy.saveFigVisibleOn(fig, figPath);

            tc.verifyEqual(char(string(fig.Visible)), 'off');
            tc.verifyEqual(numel(findall(groot, 'Type', 'figure')), figureCount);
            tc.verifyEqual( ...
                bms.plot.PlotVisibilityPolicy.savedFigureVisibility(figPath), 'on');
            tc.verifyEqual(fig.Position, [120 140 640 360], 'AbsTol', 1);

            reopened = openfig(figPath, 'new', 'invisible');
            tc.verifyEqual(char(string(reopened.Visible)), 'off');
            tc.verifyGreaterThan(numel(findall(reopened, 'Type', 'line')), 0);
            tc.verifyGreaterThan(reopened.Position(1), -1000);
            close(reopened);

            % This is the user-facing contract: an ordinary OPENFIG without a
            % visibility override must not inherit the hidden batch state.
            visibleReopen = openfig(figPath, 'new');
            tc.verifyEqual(char(string(visibleReopen.Visible)), 'on');
            tc.verifyGreaterThan(visibleReopen.Position(1), -1000);
            close(visibleReopen);
            close(fig);
        end

        function savedVisibilityDiscoversNonDefaultHgSchemaName(tc)
            originalPath = fullfile(tc.TempDir, 'original_schema.fig');
            renamedPath = fullfile(tc.TempDir, 'renamed_schema.fig');
            fig = figure('Visible', 'off');
            ax = axes(fig);
            plot(ax, datetime(2026, 1, 1) + minutes(0:4), 1:5);
            yline(ax, 3.5, '--', 'threshold');
            savefig(fig, originalPath);

            payload = load(originalPath, 'hgS_070000', 'meta_data', '-mat');
            tc.assumeTrue(isfield(payload, 'hgS_070000'), ...
                'This compatibility fixture requires the R2024a hgS_070000 schema.');
            renamed = struct( ...
                'hgS_090123', payload.hgS_070000, ...
                'meta_data', payload.meta_data);
            renamed.hgS_090123.properties.Visible = 'on';
            save(renamedPath, '-struct', 'renamed', '-mat');

            before = numel(findall(groot, 'Type', 'figure'));
            tc.verifyEqual( ...
                bms.plot.PlotVisibilityPolicy.savedFigureVisibility(renamedPath), 'on');
            tc.verifyEqual(numel(findall(groot, 'Type', 'figure')), before, ...
                'Side-effect-free FIG inspection must not materialize a duplicate figure.');
            close(fig);
        end

        function omittedVisiblePropertyMeansSavedDefaultOn(tc)
            originalPath = fullfile(tc.TempDir, 'explicit_hidden.fig');
            defaultOnPath = fullfile(tc.TempDir, 'default_visible_omitted.fig');
            fig = figure('Visible', 'off');
            ax = axes(fig);
            plot(ax, 1:5, [2 1 4 3 5]);
            yline(ax, 3.5, '--', 'threshold');
            savefig(fig, originalPath);

            payload = load(originalPath, 'hgS_070000', 'meta_data', '-mat');
            tc.assumeTrue(isfield(payload, 'hgS_070000'), ...
                'This compatibility fixture requires the R2024a hgS_070000 schema.');
            tc.assumeTrue(isfield(payload.hgS_070000.properties, 'Visible'));
            payload.hgS_070000.properties = rmfield( ...
                payload.hgS_070000.properties, 'Visible');
            save(defaultOnPath, '-struct', 'payload', '-mat');

            before = numel(findall(groot, 'Type', 'figure'));
            tc.verifyEqual( ...
                bms.plot.PlotVisibilityPolicy.savedFigureVisibility(defaultOnPath), 'on');
            tc.verifyEqual(numel(findall(groot, 'Type', 'figure')), before);
            close(fig);
        end

        function savePlotBundleSupportsInvisibleScreenshotInspection(tc)
            fig = figure('Visible', 'off', 'Position', [80 90 720 420]);
            ax = axes(fig);
            y = zeros(5000, 1);
            y(1234) = -20;
            y(4321) = 8;
            plot(ax, 1:numel(y), y);
            opts = struct( ...
                'save_jpg', false, ...
                'save_emf', false, ...
                'save_fig', true, ...
                'lightweight_fig', true, ...
                'fig_max_points', 1000, ...
                'append_timestamp', false);

            paths = save_plot_bundle(fig, tc.TempDir, 'inspection_ready', opts);
            figPath = fullfile(tc.TempDir, 'inspection_ready.fig');
            tc.verifyTrue(any(strcmp(paths, figPath)));
            tc.verifyEqual( ...
                bms.plot.PlotVisibilityPolicy.savedFigureVisibility(figPath), 'on');

            visibleReopen = openfig(figPath, 'new');
            tc.verifyEqual(char(string(visibleReopen.Visible)), 'on');
            close(visibleReopen);

            reopened = openfig(figPath, 'new', 'invisible');
            reopenCleanup = onCleanup(@() close(reopened));
            lineHandles = findall(reopened, 'Type', 'line');
            ySaved = lineHandles(1).YData;
            tc.verifyTrue(any(abs(ySaved + 20) < 1e-12));
            tc.verifyTrue(any(abs(ySaved - 8) < 1e-12));
            tc.verifyGreaterThan(reopened.Position(1), -1000);

            screenshotPath = fullfile(tc.TempDir, 'inspection_ready.png');
            exportgraphics(reopened, screenshotPath, 'Resolution', 80);
            tc.verifyTrue(isfile(screenshotPath));
            info = dir(screenshotPath);
            tc.verifyGreaterThan(info.bytes, 0);
        end

        function savePlotBundlePreservesModernGraphicsObjects(tc)
            fig = figure('Visible', 'off');
            ax = axes(fig);
            hold(ax, 'on');
            plot(ax, 1:5, [1 4 2 5 3], 'DisplayName', 'A');
            plot(ax, 1:5, [2 3 1 4 2], 'DisplayName', 'B');
            yline(ax, -10, '--r', 'lower');
            yline(ax, 10, '--r', 'upper');
            legend(ax, 'show');
            opts = struct( ...
                'save_jpg', false, ...
                'save_emf', false, ...
                'save_fig', true, ...
                'lightweight_fig', false, ...
                'append_timestamp', false);

            paths = save_plot_bundle(fig, tc.TempDir, 'modern_objects', opts);
            figPath = fullfile(tc.TempDir, 'modern_objects.fig');
            tc.verifyTrue(any(strcmp(paths, figPath)));
            tc.verifyEqual( ...
                bms.plot.PlotVisibilityPolicy.savedFigureVisibility(figPath), 'on');

            reopened = openfig(figPath, 'new', 'invisible');
            reopenCleanup = onCleanup(@() close(reopened));
            constantLines = findall(reopened, 'Type', 'ConstantLine');
            tc.verifyEqual(numel(constantLines), 2);
            tc.verifyEqual(sort([constantLines.Value]), [-10 10]);
            tc.verifyEqual(numel(findall(reopened, 'Type', 'legend')), 1);
            tc.verifyEqual(numel(findall(reopened, 'Type', 'line')), 2);
        end

        function wimPlotDoesNotLeaveVisibleFigure(tc)
            set(groot, 'DefaultFigureVisible', 'on');
            guard = bms.plot.PlotVisibilityPolicy.enter('background'); %#ok<NASGU>
            before = numel(findall(groot, 'Type', 'figure'));
            plotCfg = bms.analyzer.WimPlotService.getPlotConfig(struct(), struct());
            plotCfg.save_fig = true;
            plotCfg.export_padding_px = 5;
            outPath = fullfile(tc.TempDir, 'wim_visibility.jpg');

            bms.analyzer.WimPlotService.plotBarChart( ...
                outPath, 'WIM visibility', 'count', ["A"; "B"], ...
                [3; 7], false, '', plotCfg, [640 360]);

            tc.verifyTrue(isfile(outPath));
            figPath = fullfile(tc.TempDir, 'wim_visibility.fig');
            tc.verifyTrue(isfile(figPath));
            tc.verifyEqual( ...
                bms.plot.PlotVisibilityPolicy.savedFigureVisibility(figPath), 'on');
            tc.verifyEqual(numel(findall(groot, 'Type', 'figure')), before);
        end
    end
end
