classdef test_fig_threshold_request_runner < matlab.unittest.TestCase
    properties
        TempDir
        FigPath
        FigHash
        FigBytes
        Times
    end

    methods (TestMethodSetup)
        function makeFixture(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            tc.FigPath = fullfile(tc.TempDir, 'source.fig');
            tc.Times = datenum(datetime(2026, 5, 1) + days(0:4));

            fig = figure('Visible', 'off');
            closeFig = onCleanup(@() close(fig)); %#ok<NASGU>
            ax = axes('Parent', fig);
            plot(ax, tc.Times, [-5 -2 0 3 8], ...
                'DisplayName', 'SOURCE-1', 'LineWidth', 1.0);
            title(ax, 'Synthetic threshold source');
            xlabel(ax, 'Time');
            ylabel(ax, 'Value');
            savefig(fig, tc.FigPath);
            clear closeFig;

            tc.FigHash = bms.io.JsonFile.sha256(tc.FigPath);
            info = dir(tc.FigPath);
            tc.FigBytes = double(info.bytes);
        end
    end

    methods (TestMethodTeardown)
        function removeFixture(tc)
            close all force;
            if isfolder(tc.TempDir)
                rmdir(tc.TempDir, 's');
            end
        end
    end

    methods (Test)
        function bandRequestWritesSourceBoundResult(tc)
            scripted = struct( ...
                'axis_index', 1, ...
                'curve_index', 1, ...
                'lower', -2.5, ...
                'upper', 4.5, ...
                't_range_start', '2026-05-02 00:00:00', ...
                't_range_end', '2026-05-04 00:00:00');
            [requestPath, request] = tc.writeRequest('band', scripted, 'band');

            actual = bms.app.FigThresholdRequestRunner.runFile(requestPath);

            tc.verifyEqual(actual, request.result_path);
            result = jsondecode(fileread(request.result_path));
            status = jsondecode(fileread(request.status_path));
            tc.verifyEqual(result.artifact_type, 'fig_threshold_result');
            tc.verifyEqual(result.request_type, 'fig_threshold_interaction');
            tc.verifyEqual(result.status, 'ok');
            tc.verifyEqual(result.operation, 'band');
            tc.verifyEqual(result.target_module, 'acceleration');
            tc.verifyEqual(result.target_point, 'TARGET-1');
            tc.verifyEqual(result.candidate.lower, -2.5);
            tc.verifyEqual(result.candidate.upper, 4.5);
            tc.verifyEqual(result.candidate.t_range_start, '2026-05-02 00:00:00');
            tc.verifyEqual(result.candidate.t_range_end, '2026-05-04 00:00:00');
            tc.verifyEqual(result.source_curve.axis_title, ...
                'Synthetic threshold source');
            tc.verifyEqual(result.source_curve.curve_label, 'SOURCE-1');
            tc.verifyEqual(result.source_curve.sample_count, 5);
            tc.verifyEqual(result.source_fig.path, ...
                char(java.io.File(tc.FigPath).getCanonicalPath()));
            tc.verifyEqual(result.source_fig.sha256, tc.FigHash);
            tc.verifyEqual(result.source_fig.size, tc.FigBytes);
            tc.verifyNotEmpty(result.source_fig.mtime);
            tc.verifyEqual(status.status, 'completed');
            tc.verifyEqual(status.result_status, 'ok');
        end

        function lowerBoxUsesHighestSelectedActualSample(tc)
            scripted = struct( ...
                'axis_index', 1, ...
                'curve_index', 1, ...
                'selection_start', '2026-05-01 00:00:00', ...
                'selection_end', '2026-05-05 00:00:00', ...
                'selection_min', -10, ...
                'selection_max', 0);
            [requestPath, request] = tc.writeRequest( ...
                'box_lower', scripted, 'lower');

            bms.app.FigThresholdRequestRunner.runFile(requestPath);

            result = jsondecode(fileread(request.result_path));
            tc.verifyEqual(result.status, 'ok');
            tc.verifyEqual(result.candidate.side, 'lower');
            tc.verifyEqual(result.candidate.value, 0);
            tc.verifyEqual(result.candidate.selected_sample_count, 3);
            tc.verifyEqual(result.candidate.selection_start, ...
                '2026-05-01 00:00:00');
            tc.verifyEqual(result.candidate.selection_end, ...
                '2026-05-05 00:00:00');
        end

        function upperBoxUsesLowestSelectedActualSample(tc)
            scripted = struct( ...
                'axis_index', 1, ...
                'curve_index', 1, ...
                'selection_start', tc.Times(1), ...
                'selection_end', tc.Times(end), ...
                'selection_min', 0, ...
                'selection_max', 10);
            [requestPath, request] = tc.writeRequest( ...
                'box_upper', scripted, 'upper');

            bms.app.FigThresholdRequestRunner.runFile(requestPath);

            result = jsondecode(fileread(request.result_path));
            tc.verifyEqual(result.status, 'ok');
            tc.verifyEqual(result.candidate.side, 'upper');
            tc.verifyEqual(result.candidate.value, 0);
            tc.verifyEqual(result.candidate.selected_sample_count, 3);
        end

        function selectorFiltersNonTimeAndReferenceLines(tc)
            mixedFigPath = fullfile(tc.TempDir, 'mixed.fig');
            fig = figure('Visible', 'off');
            closeFig = onCleanup(@() close(fig)); %#ok<NASGU>
            validAxes = subplot(2, 1, 1, 'Parent', fig);
            plot(validAxes, tc.Times, [-5 -2 0 3 8], ...
                'DisplayName', 'VALID-SERIES');
            hold(validAxes, 'on');
            plot(validAxes, 1:5, [1 2 3 4 5], ...
                'DisplayName', 'NUMERIC-INDEX-NOT-TIME');
            plot(validAxes, [tc.Times(1) tc.Times(end)], [10 10], ...
                'DisplayName', 'TWO-POINT-REFERENCE');
            title(validAxes, 'Valid source axes');
            invalidAxes = subplot(2, 1, 2, 'Parent', fig);
            plot(invalidAxes, 1:5, [5 4 3 2 1], ...
                'DisplayName', 'INVALID-AXIS-LINE');
            title(invalidAxes, 'Invalid source axes');
            savefig(fig, mixedFigPath);
            clear closeFig;

            options = struct('scripted_selection', struct( ...
                'axis_index', 1, 'curve_index', 1));
            [curve, cancelled] = ...
                bms.gui.FigCurveSelector.selectFromFile(mixedFigPath, options);

            tc.verifyFalse(cancelled);
            tc.verifyEqual(curve.axis_title, 'Valid source axes');
            tc.verifyEqual(curve.curve_label, 'VALID-SERIES');
            tc.verifyEqual(curve.sample_count, 5);
            tc.verifyEqual(curve.y, [-5; -2; 0; 3; 8]);
        end

        function selectorFallsBackToLegendOnlyCurveLabels(tc)
            legendFigPath = fullfile(tc.TempDir, 'legend_only.fig');
            fig = figure('Visible', 'off');
            closeFig = onCleanup(@() close(fig)); %#ok<NASGU>
            ax = axes('Parent', fig);
            hold(ax, 'on');
            first = plot(ax, tc.Times, [1 2 3 4 5]);
            second = plot(ax, tc.Times, [5 4 3 2 1]);
            lg = legend(ax, [first second], {'LEGEND-ONLY-A', 'LEGEND-ONLY-B'});
            first.DisplayName = '';
            second.DisplayName = '';
            lg.String = {'LEGEND-ONLY-A', 'LEGEND-ONLY-B'};
            savefig(fig, legendFigPath);
            clear closeFig;

            options = struct('scripted_selection', struct( ...
                'axis_index', 1, 'curve_index', 2));
            [curve, cancelled] = ...
                bms.gui.FigCurveSelector.selectFromFile(legendFigPath, options);

            tc.verifyFalse(cancelled);
            tc.verifyEqual(curve.curve_label, 'LEGEND-ONLY-B');
            tc.verifyEqual(curve.sample_count, 5);
            tc.verifyEqual(curve.y, [5; 4; 3; 2; 1]);
        end

        function selectorKeepsTwoPointSlopedTimeSeries(tc)
            slopedFigPath = fullfile(tc.TempDir, 'two_point_sloped.fig');
            fig = figure('Visible', 'off');
            closeFig = onCleanup(@() close(fig)); %#ok<NASGU>
            ax = axes('Parent', fig);
            plot(ax, tc.Times([1 end]), [-1 2], ...
                'DisplayName', 'TWO-POINT-SLOPED');
            savefig(fig, slopedFigPath);
            clear closeFig;

            options = struct('scripted_selection', struct( ...
                'axis_index', 1, 'curve_index', 1));
            [curve, cancelled] = ...
                bms.gui.FigCurveSelector.selectFromFile(slopedFigPath, options);

            tc.verifyFalse(cancelled);
            tc.verifyEqual(curve.curve_label, 'TWO-POINT-SLOPED');
            tc.verifyEqual(curve.sample_count, 2);
            tc.verifyEqual(curve.y, [-1; 2]);
        end

        function selectorKeepsTwoPointHorizontalDataSeries(tc)
            constantFigPath = fullfile(tc.TempDir, 'two_point_constant.fig');
            fig = figure('Visible', 'off');
            closeFig = onCleanup(@() close(fig)); %#ok<NASGU>
            ax = axes('Parent', fig);
            plot(ax, tc.Times([1 end]), [3 3 + eps(3)], ...
                'DisplayName', 'TWO-POINT-CONSTANT-DATA', ...
                'LineStyle', '-');
            savefig(fig, constantFigPath);
            clear closeFig;

            options = struct('scripted_selection', struct( ...
                'axis_index', 1, 'curve_index', 1));
            [curve, cancelled] = ...
                bms.gui.FigCurveSelector.selectFromFile(constantFigPath, options);

            tc.verifyFalse(cancelled);
            tc.verifyEqual(curve.curve_label, 'TWO-POINT-CONSTANT-DATA');
            tc.verifyEqual(curve.sample_count, 2);
            tc.verifyEqual(curve.y, [3; 3 + eps(3)]);
        end

        function selectorRejectsTwoPointHorizontalReferenceLine(tc)
            referenceFigPath = fullfile(tc.TempDir, 'two_point_reference.fig');
            fig = figure('Visible', 'off');
            closeFig = onCleanup(@() close(fig)); %#ok<NASGU>
            ax = axes('Parent', fig);
            plot(ax, tc.Times([1 end]), [3 3 + eps(3)], ...
                'DisplayName', 'TWO-POINT-REFERENCE');
            savefig(fig, referenceFigPath);
            clear closeFig;

            options = struct('scripted_selection', struct( ...
                'axis_index', 1, 'curve_index', 1));
            tc.verifyError(@() bms.gui.FigCurveSelector.selectFromFile( ...
                referenceFigPath, options), 'BMS:FigCurveSelector:NoAxes');
        end

        function scriptedCancelIsACompletedCancelledResult(tc)
            scripted = struct('cancel', true);
            [requestPath, request] = tc.writeRequest('band', scripted, 'cancel');

            bms.app.FigThresholdRequestRunner.runFile(requestPath);

            result = jsondecode(fileread(request.result_path));
            status = jsondecode(fileread(request.status_path));
            tc.verifyEqual(result.status, 'cancelled');
            tc.verifyEmpty(fieldnames(result.candidate));
            tc.verifyEqual(result.source_curve.sample_count, 0);
            tc.verifyEqual(status.status, 'completed');
            tc.verifyEqual(status.result_status, 'cancelled');
        end

        function hashDriftFailsClosed(tc)
            [requestPath, request] = tc.writeRequest( ...
                'band', struct('cancel', true), 'hash_drift');
            request.fig_sha256 = repmat('0', 1, 64);
            bms.core.Logger.writeJson(requestPath, request);

            tc.verifyError( ...
                @() bms.app.FigThresholdRequestRunner.runFile(requestPath), ...
                'BMS:FigThresholdRequest:FigHashChanged');
            status = jsondecode(fileread(request.status_path));
            tc.verifyEqual(status.status, 'failed');
            tc.verifyEqual(status.error_id, ...
                'BMS:FigThresholdRequest:FigHashChanged');
            tc.verifyFalse(isfile(request.result_path));
        end

        function cliDispatchRestoresFigureVisibility(tc)
            scripted = struct( ...
                'axis_index', 1, ...
                'curve_index', 1, ...
                'lower', -1, ...
                'upper', 1);
            [requestPath, request] = tc.writeRequest('band', scripted, 'cli');
            before = char(string(get(groot, 'DefaultFigureVisible')));
            restore = onCleanup( ...
                @() set(groot, 'DefaultFigureVisible', before)); %#ok<NASGU>
            set(groot, 'DefaultFigureVisible', 'off');

            actual = run_request_cli(requestPath);

            tc.verifyEqual(actual, request.result_path);
            tc.verifyEqual( ...
                char(string(get(groot, 'DefaultFigureVisible'))), 'off');
            result = jsondecode(fileread(request.result_path));
            tc.verifyEqual(result.status, 'ok');
        end
    end

    methods (Access = private)
        function [requestPath, request] = writeRequest( ...
                tc, operation, scripted, suffix)
            requestPath = fullfile(tc.TempDir, ['request_' suffix '.json']);
            request = struct( ...
                'schema_version', 1, ...
                'request_type', 'fig_threshold_interaction', ...
                'request_id', ['matlab_' suffix], ...
                'operation', operation, ...
                'fig_path', tc.FigPath, ...
                'fig_sha256', tc.FigHash, ...
                'fig_size_bytes', tc.FigBytes, ...
                'status_path', fullfile(tc.TempDir, ['status_' suffix '.json']), ...
                'result_path', fullfile(tc.TempDir, ['result_' suffix '.json']), ...
                'target_module', 'acceleration', ...
                'target_point', 'TARGET-1', ...
                'scripted_selection', scripted);
            bms.core.Logger.writeJson(requestPath, request);
        end
    end
end
