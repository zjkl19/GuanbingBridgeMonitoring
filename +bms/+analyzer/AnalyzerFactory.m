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
                    analyzer = bms.analyzer.GnssAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, points);
                case 'bearing_displacement'
                    analyzer = bms.analyzer.BearingDisplacementAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg);
                case 'tilt'
                    analyzer = bms.analyzer.TiltAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg);
                case 'strain'
                    analyzer = bms.analyzer.StrainAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg);
                case 'wind'
                    analyzer = bms.analyzer.WindAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg);
                case {'earthquake','eq'}
                    analyzer = bms.analyzer.EarthquakeAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg);
                case 'acceleration'
                    autoDetectFs = true;
                    analyzer = bms.analyzer.AccelerationAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, autoDetectFs);
                case 'cable_accel'
                    autoDetectFs = true;
                    analyzer = bms.analyzer.CableAccelerationAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, autoDetectFs);
                case 'accel_spectrum'
                    [freqs, tol] = bms.analyzer.AnalyzerFactory.resolveSpectrumParams(params, cfg, false);
                    analyzer = bms.analyzer.AccelerationSpectrumAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, points, freqs, tol);
                case 'cable_accel_spectrum'
                    [freqs, tol] = bms.analyzer.AnalyzerFactory.resolveSpectrumParams(params, cfg, true);
                    analyzer = bms.analyzer.CableAccelerationSpectrumAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, points, freqs, tol);
                case 'dynamic_strain_highpass'
                    analyzer = bms.analyzer.DynamicStrainHighpassAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg);
                case 'dynamic_strain_lowpass'
                    analyzer = bms.analyzer.DynamicStrainLowpassAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg);
                case 'wim'
                    analyzer = bms.analyzer.WimAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg);
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
