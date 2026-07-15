classdef test_plot_option_resolver < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function addProjectPaths(~)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(projectRoot, '-begin');
            addpath(fullfile(projectRoot, 'pipeline'), '-begin');
        end
    end

    methods (Test)
        function precedenceIsPointModuleLegacyGlobal(tc)
            cfg = struct();
            cfg.plot_common = struct( ...
                'gap_mode', 'connect', ...
                'gap_break_factor', 5, ...
                'dynamic_raw_modules', struct( ...
                    'acceleration', struct('gap_mode', 'break', 'gap_break_factor', 6)));
            cfg.plot_styles = struct( ...
                'acceleration', struct('gap_mode', 'connect'));
            cfg.per_point = struct( ...
                'acceleration', struct( ...
                    'A_1', struct('plot', struct( ...
                        'gap_mode', 'break', 'gap_break_factor', 9))));
            cfg.name_map_global = struct('A_1', 'A-1');

            point = bms.plot.PlotOptionResolver.effectiveGap(cfg, 'acceleration', 'A-1');
            tc.verifyEqual(point.gap_mode, 'break');
            tc.verifyEqual(point.gap_break_factor, 9);
            tc.verifyEqual(point.mode_source, 'point');
            tc.verifyEqual(point.factor_source, 'point');

            module = bms.plot.PlotOptionResolver.effectiveGap(cfg, 'acceleration', 'A-2');
            tc.verifyEqual(module.gap_mode, 'connect');
            tc.verifyEqual(module.gap_break_factor, 6);
            tc.verifyEqual(module.mode_source, 'module');
            tc.verifyEqual(module.factor_source, 'legacy_module');

            globalOnly = bms.plot.PlotOptionResolver.effectiveGap(cfg, 'strain', 'S1');
            tc.verifyEqual(globalOnly.gap_mode, 'connect');
            tc.verifyEqual(globalOnly.gap_break_factor, 5);
        end

        function moduleAndPointFieldsMayInheritIndependently(tc)
            cfg.plot_common = struct('gap_mode', 'connect', 'gap_break_factor', 5);
            cfg.plot_styles.strain = struct('gap_mode', 'break');
            cfg.per_point.strain.S1.plot = struct('gap_break_factor', 12);

            gap = bms.plot.PlotOptionResolver.effectiveGap(cfg, 'strain', 'S1');
            tc.verifyEqual(gap.gap_mode, 'break');
            tc.verifyEqual(gap.gap_break_factor, 12);
            tc.verifyEqual(gap.mode_source, 'module');
            tc.verifyEqual(gap.factor_source, 'point');
        end

        function invalidOverridesFallBackWithoutBreakingAnalysis(tc)
            cfg.plot_common = struct('gap_mode', 'invalid', 'gap_break_factor', 0);
            cfg.plot_styles.strain = struct('gap_mode', 'also_invalid', 'gap_break_factor', -1);
            gap = bms.plot.PlotOptionResolver.effectiveGap(cfg, 'strain', 'S1');
            tc.verifyEqual(gap.gap_mode, 'connect');
            tc.verifyEqual(gap.gap_break_factor, 5);
        end

        function analysisKeyWinsAndLegacyConfigKeysRemainUsable(tc)
            cfg.plot_common = struct('gap_mode', 'connect', 'gap_break_factor', 5);
            cfg.plot_styles.dynamic_strain = struct('gap_mode', 'break');
            cfg.plot_styles.dynamic_strain_highpass = struct('gap_mode', 'connect');
            cfg.per_point.dynamic_strain.S1.plot = struct('gap_break_factor', 8);
            cfg.plot_styles.wind = struct('gap_mode', 'break');
            cfg.per_point.wind_speed.W1.plot = struct('gap_mode', 'connect');
            cfg.plot_styles.cable_accel_spectrum = struct('gap_mode', 'break');
            cfg.per_point.cable_accel.CS1.plot = struct('gap_mode', 'connect');

            dynamic = bms.plot.PlotOptionResolver.effectiveGap( ...
                cfg, 'dynamic_strain_highpass', 'S1');
            tc.verifyEqual(dynamic.gap_mode, 'connect');
            tc.verifyEqual(dynamic.gap_break_factor, 8);

            wind = bms.plot.PlotOptionResolver.effectiveGap(cfg, 'wind', 'W1');
            tc.verifyEqual(wind.gap_mode, 'connect');

            cableSpectrum = bms.plot.PlotOptionResolver.effectiveGap( ...
                cfg, 'cable_accel_spectrum', 'CS1');
            tc.verifyEqual(cableSpectrum.gap_mode, 'connect');
        end

        function sharedPythonMatlabContractStaysAligned(tc)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            fixture = fullfile(projectRoot, 'tests', 'fixtures', ...
                'gap_override_contract.json');
            cfg = jsondecode(fileread(fixture));
            cases = cfg.gap_resolution_cases;
            cfg = rmfield(cfg, 'gap_resolution_cases');
            for i = 1:numel(cases)
                resolved = bms.plot.PlotOptionResolver.effectiveGap( ...
                    cfg, cases(i).module_key, cases(i).point_id);
                tc.verifyEqual(resolved.gap_mode, cases(i).gap_mode, ...
                    sprintf('module=%s point=%s', ...
                    cases(i).module_key, cases(i).point_id));
                tc.verifyEqual(resolved.gap_break_factor, ...
                    cases(i).gap_break_factor, ...
                    sprintf('module=%s point=%s', ...
                    cases(i).module_key, cases(i).point_id));
            end
        end

        function runtimeOptionsDriveActualGapInsertion(tc)
            cfg.plot_common = struct('gap_mode', 'connect', 'gap_break_factor', 5, ...
                'fig_max_points', 1000);
            cfg.plot_styles.strain = struct('gap_mode', 'break');
            cfg.per_point.strain.S2.plot = struct('gap_mode', 'connect');
            x = datetime(2026, 1, 1, 0, [0 1 10 11], 0).';
            y = [1; 2; 3; 4];

            optsBreak = bms.plot.PlotService.runtimeOptionsFromConfig(cfg, 'strain', 'S1');
            [xb, yb] = prepare_plot_series(x, y, optsBreak);
            tc.verifyGreaterThan(numel(xb), numel(x));
            tc.verifyTrue(any(isnat(xb)) || any(isnan(yb)));

            optsConnect = bms.plot.PlotService.runtimeOptionsFromConfig(cfg, 'strain', 'S2');
            [xc, yc] = prepare_plot_series(x, y, optsConnect);
            tc.verifyEqual(numel(xc), numel(x));
            tc.verifyFalse(any(isnat(xc)));
            tc.verifyFalse(any(isnan(yc)));
        end

        function spectrumTrendReceivesModuleAndPointContext(tc)
            outDir = tempname;
            mkdir(outDir);
            tc.addTeardown(@() rmdir(outDir, 's'));
            cfg.plot_common = struct( ...
                'gap_mode', 'connect', 'gap_break_factor', 5, ...
                'save_jpg', false, 'save_emf', false, ...
                'save_fig', true, 'lightweight_fig', false, ...
                'append_timestamp', false, 'fig_max_points', 1000);
            cfg.plot_styles.accel_spectrum = struct('gap_mode', 'break');
            dates = datetime(2026, 1, [1 2 11 12]).';
            style = struct( ...
                'colors', {{[0 0.447 0.741]}}, ...
                'freq_ylabel', 'Peak frequency (Hz)', ...
                'freq_title_prefix', 'Peak frequency');

            bms.analyzer.SpectrumPlotService.plotFrequencyTimeseries( ...
                dates, [1.1; 1.2; 1.3; 1.4], 'A1', 1.2, outDir, style, ...
                [], {}, cfg, {'P1'}, 'accel_spectrum');

            files = dir(fullfile(outDir, 'SpecFreq_A1_*.fig'));
            tc.verifyEqual(numel(files), 1);
            fig = openfig(fullfile(files(1).folder, files(1).name), 'invisible');
            cleaner = onCleanup(@() close(fig)); %#ok<NASGU>
            lines = findall(fig, 'Type', 'line');
            hasGap = false;
            for i = 1:numel(lines)
                x = get(lines(i), 'XData');
                y = get(lines(i), 'YData');
                if isdatetime(x)
                    hasGap = hasGap || any(isnat(x)) || any(isnan(y));
                end
            end
            tc.verifyTrue(hasGap);
        end

        function structuralGroupOptionsCannotMaskPointGapOverride(tc)
            cfg.plot_common = struct('gap_mode', 'connect', 'gap_break_factor', 5, ...
                'save_jpg', false, 'save_emf', false, 'save_fig', true, ...
                'lightweight_fig', false, 'append_timestamp', false, ...
                'fig_max_points', 1000);
            cfg.plot_styles.strain = struct('gap_mode', 'break');
            cfg.per_point.strain.S2.plot = struct('gap_mode', 'connect');
            dataList = bms.analyzer.StructuralTimeSeriesPlotService.fromCells( ...
                {datetime(2026, 1, 1, 0, [0 1 10 11], 0).'}, ...
                {[1; 2; 3; 4]}, {'S2'});
            outDir = tempname;
            mkdir(outDir);
            tc.addTeardown(@() rmdir(outDir, 's'));
            opts = struct('moduleKey', 'strain', 'gap_mode', 'break', ...
                'gap_break_factor', 2, 'outputDir', outDir, ...
                'baseName', 'point_gap_precedence');

            bms.analyzer.StructuralTimeSeriesPlotService.plotDataList( ...
                '', dataList, '2026-01-01', '2026-01-02', opts, cfg);

            fig = openfig(fullfile(outDir, 'point_gap_precedence.fig'), 'invisible');
            cleaner = onCleanup(@() close(fig)); %#ok<NASGU>
            lines = findall(fig, 'Type', 'line');
            series = lines(arrayfun(@(h) numel(get(h, 'YData')) == 4, lines));
            tc.verifyNotEmpty(series);
            tc.verifyFalse(any(isnat(get(series(1), 'XData'))));
            tc.verifyFalse(any(isnan(get(series(1), 'YData'))));
        end

        function materializeKeepsUnrelatedFields(tc)
            cfg.plot_common = struct('gap_mode', 'connect', 'gap_break_factor', 5, ...
                'fig_max_points', 12345);
            cfg.plot_styles.strain = struct('gap_mode', 'break');
            out = bms.plot.PlotOptionResolver.materializeGap(cfg, 'strain', 'S1');
            tc.verifyEqual(out.plot_common.gap_mode, 'break');
            tc.verifyEqual(out.plot_common.gap_break_factor, 5);
            tc.verifyEqual(out.plot_common.fig_max_points, 12345);
            tc.verifyEqual(out.plot_styles.strain.gap_mode, 'break');
        end
    end
end
