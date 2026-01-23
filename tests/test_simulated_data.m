classdef test_simulated_data < matlab.unittest.TestCase
    % Smoke tests on the synthetic fixtures under tests/data
    properties (Constant)
        Root  = fullfile(fileparts(mfilename('fullpath')), 'data');
        Date0 = '2025-01-01';
        Date1 = '2025-01-02';
    end

    methods (Test)
        function deflectionThresholds(tc)
            cfg = load_config();
            [~, v] = load_timeseries_range(tc.Root, cfg.subfolders.deflection, ...
                'GB-DIS-G05-001-01Y', tc.Date0, tc.Date1, cfg, 'deflection');
            tc.verifyNumElements(v, 24, 'Should merge two days (12 each).');
            tc.verifyEqual(nnz(isnan(v)), 2, 'Out-of-range values should be NaN.');
            tc.verifyLessThanOrEqual(max(v,[],'omitnan'), 31);
            tc.verifyGreaterThanOrEqual(min(v,[],'omitnan'), -10);
        end

        function strainOutlier(tc)
            cfg = load_config();
            [~, v] = load_timeseries_range(tc.Root, cfg.subfolders.strain, ...
                'GB-RSG-G05-001-01', tc.Date0, tc.Date1, cfg, 'strain');
            tc.verifyNumElements(v, 40, 'Two days, 20 rows each.');
            tc.verifyEqual(nnz(isnan(v)), 2, 'Out-of-range strain should be NaN.');
            tc.verifyTrue(all(v(isfinite(v)) >= -400 & v(isfinite(v)) <= 200));
        end

        function accelBasic(tc)
            cfg = load_config();
            [times, vals] = load_timeseries_range(tc.Root, cfg.subfolders.acceleration, ...
                'GB-VIB-G05-001-01', tc.Date0, tc.Date1, cfg, 'acceleration');
            tc.verifyNumElements(vals, 200, 'Two days, 100 rows each.');
            % Sampling interval ~0.05 s
            dt = median(seconds(diff(times)));
            tc.verifyLessThan(abs(dt - 0.05), 1e-3);
            tc.verifyLessThan(abs(mean(vals, 'omitnan')), 0.2, 'Mean should be near zero.');
        end

        function crackWithTemp(tc)
            cfg = load_config();
            [tcC, vc] = load_timeseries_range(tc.Root, cfg.subfolders.crack, ...
                'GB-CRK-G05-001-01', tc.Date0, tc.Date1, cfg, 'crack');
            [ttT, vt] = load_timeseries_range(tc.Root, cfg.subfolders.crack, ...
                'GB-CRK-G05-001-01-t', tc.Date0, tc.Date1, cfg, 'crack_temp');
            tc.verifyNumElements(vc, 16);
            tc.verifyNumElements(vt, 16);
            tc.verifyEqual(numel(tcC), numel(ttT));
            tc.verifyLessThanOrEqual(max(vc,[],'omitnan'), 0.35);
        end

        function headerMarker(tc)
            % Ensure header_marker matches fixtures
            cfg = load_config();
            tc.verifyEqual(string(cfg.defaults.header_marker), "[绝对时间]");
        end
    end
end
