classdef AnalyzerFactory
    %ANALYZERFACTORY Creates analysis adapters by module key.

    methods (Static)
        function analyzer = create(key, root, startDate, endDate, statsDir, sub, cfg, points)
            if nargin < 8, points = {}; end
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
                otherwise
                    error('AnalyzerFactory:UnsupportedKey', 'Unsupported analyzer key: %s', key);
            end
        end

        function tf = supports(key)
            key = char(key);
            tf = ismember(key, {'temperature','humidity','rainfall','deflection','crack'});
        end

        function subfolder = subfolderFor(key, spec, sub)
            subfolder = '';
            candidates = {key, spec.SubfolderKey};
            for i = 1:numel(candidates)
                name = candidates{i};
                if isempty(name), continue; end
                if isstruct(sub) && isfield(sub, name)
                    subfolder = sub.(name);
                    return;
                end
            end
        end
    end
end
