classdef test_spectrum_peak_order_editor_service < matlab.unittest.TestCase
    methods (Test)
        function rowsExpandDefaultAndPointPeakOrders(tc)
            cfg = struct();
            cfg.points.acceleration = {'AZ-1', 'AZ-2'};
            cfg.accel_spectrum_params.peak_orders = struct( ...
                'order', 1, ...
                'label', 'default first', ...
                'theoretical_hz', 0.593, ...
                'search_center_hz', 0.640, ...
                'search_half_width_hz', 0.200);
            cfg.per_point.accel_spectrum.AZ_2.peak_orders = struct( ...
                'order', 1, ...
                'label', 'AZ-2 first', ...
                'theoretical_hz', 0.600, ...
                'search_min_hz', 0.500, ...
                'search_max_hz', 0.700);

            rows = bms.gui.SpectrumPeakOrderEditorService.rows(cfg, 'accel_spectrum');

            tc.verifyEqual(size(rows, 2), numel(bms.gui.SpectrumPeakOrderEditorService.columnNames()));
            tc.verifyTrue(any(strcmp(rows(:, 1), 'default')));
            tc.verifyTrue(any(strcmp(rows(:, 1), 'point') & strcmp(rows(:, 2), 'AZ-2')));
            idx = find(strcmp(rows(:, 2), 'AZ-2'), 1);
            tc.verifyEqual(rows{idx, 6}, 0.500);
            tc.verifyEqual(rows{idx, 7}, 0.700);
        end

        function applyRowsWritesDefaultAndPointOrders(tc)
            cfg = struct();
            cfg.points.acceleration = {'AZ-1', 'AZ-2'};
            cfg.accel_spectrum_params.target_freqs = [0.64 1.25];
            cfg.accel_spectrum_params.tolerance = [0.2 0.1];
            cfg.per_point.accel_spectrum.AZ_2.target_freqs = 0.62;
            cfg.per_point.accel_spectrum.AZ_2.keep_me = 42;

            rows = {
                'default', '', 1, 'first', 0.593, 0.44, 0.84, true, 'theor first', 'new'
                'point', 'AZ-2', 1, 'az2 first', 0.600, 0.50, 0.70, true, 'az2 theor', 'new'
                };

            cfgOut = bms.gui.SpectrumPeakOrderEditorService.applyRows(cfg, 'accel_spectrum', rows);

            tc.verifyFalse(isfield(cfgOut.accel_spectrum_params, 'target_freqs'));
            tc.verifyEqual(cfgOut.accel_spectrum_params.peak_orders.search_center_hz, 0.64, 'AbsTol', 1e-12);
            tc.verifyEqual(cfgOut.accel_spectrum_params.peak_orders.search_half_width_hz, 0.20, 'AbsTol', 1e-12);
            tc.verifyEqual(cfgOut.per_point.accel_spectrum.AZ_2.keep_me, 42);
            tc.verifyFalse(isfield(cfgOut.per_point.accel_spectrum.AZ_2, 'target_freqs'));
            tc.verifyEqual(cfgOut.per_point.accel_spectrum.AZ_2.peak_orders.search_center_hz, 0.60, 'AbsTol', 1e-12);
            tc.verifyEqual(cfgOut.per_point.accel_spectrum.AZ_2.peak_orders.theoretical_hz, 0.600);
        end

        function cablePointOrdersPreserveForceParameters(tc)
            cfg = struct();
            cfg.points.cable_force = {'CF-1'};
            cfg.per_point.cable_accel.CF_1.length_m = 75.61;
            cfg.per_point.cable_accel.CF_1.linear_density_kg_m = 57.687;
            cfg.per_point.cable_accel.CF_1.target_freqs = 1.60;

            rows = {'point', 'CF-1', 1, 'first', 1.621, 1.42, 1.82, true, '', 'new'};

            cfgOut = bms.gui.SpectrumPeakOrderEditorService.applyRows(cfg, 'cable_accel_spectrum', rows);

            tc.verifyEqual(cfgOut.per_point.cable_accel.CF_1.length_m, 75.61);
            tc.verifyEqual(cfgOut.per_point.cable_accel.CF_1.linear_density_kg_m, 57.687);
            tc.verifyFalse(isfield(cfgOut.per_point.cable_accel.CF_1, 'target_freqs'));
            tc.verifyEqual(cfgOut.per_point.cable_accel.CF_1.peak_orders.search_min_hz, 1.42);
            tc.verifyEqual(cfgOut.per_point.cable_accel.CF_1.peak_orders.search_max_hz, 1.82);
        end

        function disabledRowsAreIgnored(tc)
            cfg = struct();
            rows = {'default', '', 1, 'ignored', 0.593, 0.44, 0.84, false, '', 'new'};

            cfgOut = bms.gui.SpectrumPeakOrderEditorService.applyRows(cfg, 'accel_spectrum', rows);

            tc.verifyFalse(isfield(cfgOut.accel_spectrum_params, 'peak_orders'));
        end
    end
end
