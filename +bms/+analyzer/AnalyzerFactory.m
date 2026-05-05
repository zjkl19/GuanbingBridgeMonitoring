classdef AnalyzerFactory
    %ANALYZERFACTORY Creates analysis adapters by module key.

    methods (Static)
        function analyzer = create(key, root, startDate, endDate, statsDir, sub, cfg, points, params)
            if nargin < 8, points = {}; end
            if nargin < 9 || isempty(params), params = struct(); end
            key = char(key);
            spec = bms.module.ModuleRegistry.fromKey(key);
            statsFile = '';
            if ~isempty(spec.StatsFile)
                statsFile = fullfile(char(statsDir), spec.StatsFile);
            end
            subfolder = bms.analyzer.AnalyzerFactory.subfolderFor(key, spec, sub);

            switch key
                case 'temperature'
                    analyzer = bms.analyzer.TemperatureAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, points);
                case 'humidity'
                    analyzer = bms.analyzer.HumidityAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, points);
                case 'rainfall'
                    analyzer = bms.analyzer.RainfallAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, points);
                case 'deflection'
                    analyzer = bms.analyzer.DeflectionAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg);
                case 'crack'
                    analyzer = bms.analyzer.CrackAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg);
                case 'gnss'
                    analyzer = bms.analyzer.LegacyFunctionAnalyzer(key, root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                        @() analyze_gnss_points(root, points, startDate, endDate, statsFile, subfolder, cfg));
                case 'bearing_displacement'
                    analyzer = bms.analyzer.LegacyFunctionAnalyzer(key, root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                        @() analyze_bearing_displacement_points(root, startDate, endDate, statsFile, subfolder, cfg));
                case 'tilt'
                    analyzer = bms.analyzer.LegacyFunctionAnalyzer(key, root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                        @() analyze_tilt_points(root, startDate, endDate, statsFile, subfolder, cfg));
                case 'strain'
                    analyzer = bms.analyzer.LegacyFunctionAnalyzer(key, root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                        @() analyze_strain_points(root, startDate, endDate, statsFile, subfolder, cfg));
                case 'wind'
                    analyzer = bms.analyzer.LegacyFunctionAnalyzer(key, root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                        @() analyze_wind_points(root, startDate, endDate, subfolder, cfg));
                case {'earthquake','eq'}
                    analyzer = bms.analyzer.LegacyFunctionAnalyzer('earthquake', root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                        @() analyze_eq_points(root, startDate, endDate, subfolder, cfg));
                case 'acceleration'
                    analyzer = bms.analyzer.LegacyFunctionAnalyzer(key, root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                        @() analyze_acceleration_points(root, startDate, endDate, statsFile, subfolder, true, cfg));
                case 'cable_accel'
                    analyzer = bms.analyzer.LegacyFunctionAnalyzer(key, root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                        @() analyze_cable_acceleration_points(root, startDate, endDate, statsFile, subfolder, true, cfg));
                case 'accel_spectrum'
                    [freqs, tol] = bms.analyzer.AnalyzerFactory.resolveSpectrumParams(params, cfg, false);
                    analyzer = bms.analyzer.LegacyFunctionAnalyzer(key, root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                        @() analyze_accel_spectrum_points(root, startDate, endDate, points, statsFile, subfolder, freqs, tol, false, cfg));
                case 'cable_accel_spectrum'
                    [freqs, tol] = bms.analyzer.AnalyzerFactory.resolveSpectrumParams(params, cfg, true);
                    analyzer = bms.analyzer.LegacyFunctionAnalyzer(key, root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                        @() analyze_cable_accel_spectrum_points(root, startDate, endDate, points, statsFile, subfolder, freqs, tol, false, cfg));
                case 'dynamic_strain_highpass'
                    outputDir = bms.config.ConfigReader.get(cfg, 'dynamic_strain.output_dir', bms.app.LegacyStepFunctions.dynamicHighpassOutputDir());
                    analyzer = bms.analyzer.LegacyFunctionAnalyzer(key, root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                        @() analyze_dynamic_strain_boxplot(root, startDate, endDate, ...
                            'Cfg', cfg, 'Subfolder', subfolder, 'OutputDir', outputDir, ...
                            'Fs', bms.config.ConfigReader.getNumeric(cfg, 'dynamic_strain.fs', 20), ...
                            'Fc', bms.config.ConfigReader.getNumeric(cfg, 'dynamic_strain.fc', 0.1), ...
                            'Whisker', bms.config.ConfigReader.getNumeric(cfg, 'dynamic_strain.whisker', 300), ...
                            'ShowOutliers', false, 'YLimManual', true, 'YLimRange', [-30 30], ...
                            'LowerBound', -150, 'UpperBound', 30, 'EdgeTrimSec', 5));
                case 'dynamic_strain_lowpass'
                    analyzer = bms.analyzer.LegacyFunctionAnalyzer(key, root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                        @() analyze_dynamic_strain_lowpass_boxplot(root, startDate, endDate, 'Cfg', cfg, 'Subfolder', subfolder));
                case 'wim'
                    analyzer = bms.analyzer.LegacyFunctionAnalyzer(key, root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                        @() analyze_wim_reports(root, startDate, endDate, cfg));
                otherwise
                    error('AnalyzerFactory:UnsupportedKey', 'Unsupported analyzer key: %s', key);
            end
        end

        function tf = supports(key)
            key = char(key);
            tf = ismember(key, {'temperature','humidity','rainfall','gnss','deflection', ...
                'bearing_displacement','tilt','crack','strain','wind','earthquake','eq', ...
                'acceleration','cable_accel','accel_spectrum','cable_accel_spectrum', ...
                'dynamic_strain_highpass','dynamic_strain_lowpass','wim'});
        end

        function subfolder = subfolderFor(key, spec, sub)
            subfolder = '';
            candidates = [{key, spec.SubfolderKey}, bms.analyzer.AnalyzerFactory.subfolderAliases(key, spec.SubfolderKey)];
            for i = 1:numel(candidates)
                name = candidates{i};
                if isempty(name), continue; end
                if isstruct(sub) && isfield(sub, name)
                    subfolder = sub.(name);
                    return;
                end
            end
        end

        function [freqs, tol] = resolveSpectrumParams(params, cfg, cable)
            if nargin < 3, cable = false; end
            if isstruct(params) && isfield(params, 'freqs') && ~isempty(params.freqs)
                freqs = params.freqs;
            elseif cable
                [freqs, ~] = bms.app.LegacyStepFunctions.getCableSpecParams(cfg);
            else
                [freqs, ~] = bms.app.LegacyStepFunctions.getAccelSpecParams(cfg);
            end
            if isstruct(params) && isfield(params, 'tol') && ~isempty(params.tol)
                tol = params.tol;
            elseif cable
                [~, tol] = bms.app.LegacyStepFunctions.getCableSpecParams(cfg);
            else
                [~, tol] = bms.app.LegacyStepFunctions.getAccelSpecParams(cfg);
            end
        end

        function aliases = subfolderAliases(key, subfolderKey)
            aliases = {};
            switch char(key)
                case 'acceleration'
                    aliases = {'accel'};
                case 'accel_spectrum'
                    aliases = {'accel_raw','acceleration_raw'};
                case 'earthquake'
                    aliases = {'eq_raw'};
                case 'wim'
                    aliases = {'wim'};
            end
            if strcmp(char(subfolderKey), 'acceleration')
                aliases{end+1} = 'accel';
            elseif strcmp(char(subfolderKey), 'acceleration_raw')
                aliases{end+1} = 'accel_raw';
            end
            aliases = unique(aliases(~cellfun(@isempty, aliases)), 'stable');
        end
    end
end
