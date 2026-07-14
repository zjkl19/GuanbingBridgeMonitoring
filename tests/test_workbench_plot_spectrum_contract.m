classdef test_workbench_plot_spectrum_contract < matlab.unittest.TestCase
    properties
        Root
        Fixture
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(tc.Root, '-begin');
            addpath(fullfile(tc.Root, 'pipeline'), '-begin');
            addpath(fullfile(tc.Root, 'analysis'), '-begin');
            addpath(fullfile(tc.Root, 'config'), '-begin');
            addpath(fullfile(tc.Root, 'ui'), '-begin');
            tc.Fixture = fullfile(tc.Root, 'tests', 'fixtures', ...
                'workbench_plot_spectrum_contract.json');
        end
    end

    methods (Test)
        function plotCommonFeedsCurrentRuntimeServices(tc)
            cfg = bms.core.ConfigStore.load(tc.Fixture);
            opts = bms.plot.PlotService.runtimeOptionsFromConfig(cfg);
            tc.verifyTrue(opts.save_fig);
            tc.verifyTrue(opts.lightweight_fig);
            tc.verifyEqual(opts.gap_mode, 'connect');
            tc.verifyTrue(bms.analyzer.DynamicSeriesService.isFullRawSampling(cfg));
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawPlotLineWidth(cfg, 0.5), 1.0);
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawPlotRenderMode(cfg, 'dense_band'), 'line');
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawPlotBandBins(cfg, 1000), 48000);
        end

        function spectrumRowsCoverDefaultsLegacyAndPerPointOrders(tc)
            cfg = bms.core.ConfigStore.load(tc.Fixture);
            spec = bms.config.ModuleConfigRegistry.fromKey('accel_spectrum');
            rows = bms.gui.SpectrumPeakOrderEditorService.rows(cfg, spec);
            tc.verifyEqual(size(rows, 1), 3);
            tc.verifyEqual(rows(:, 1).', {'default', 'point', 'point'});
            tc.verifyTrue(any(strcmp(rows(:, 2), 'A-1')));
            tc.verifyTrue(any(strcmp(rows(:, 2), 'A-2')));
        end

        function spectrumApplyUsesPeakOrdersAndPreservesOtherFields(tc)
            cfg = bms.core.ConfigStore.load(tc.Fixture);
            spec = bms.config.ModuleConfigRegistry.fromKey('accel_spectrum');
            rows = bms.gui.SpectrumPeakOrderEditorService.rows(cfg, spec);
            out = bms.gui.SpectrumPeakOrderEditorService.applyRows(cfg, spec, rows);
            tc.verifyTrue(isfield(out.accel_spectrum_params, 'peak_orders'));
            tc.verifyFalse(isfield(out.per_point.accel_spectrum.A_1, 'target_freqs'));
            tc.verifyTrue(isfield(out.per_point.accel_spectrum.A_1, 'peak_orders'));
            tc.verifyTrue(isfield(out.per_point.accel_spectrum.A_2, 'thresholds'));
            tc.verifyEqual(out.accel_spectrum_params.fs, 20);
            tc.verifyTrue(out.unrelated_marker.keep);
        end
    end
end
