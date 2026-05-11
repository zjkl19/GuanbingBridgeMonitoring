classdef SpectrumConfigService
    %SPECTRUMCONFIGSERVICE Configuration helpers for spectrum workflows.

    methods (Static)
        function points = resolvePoints(cfg, spec)
            points = {};
            for i = 1:numel(spec.pointKeys)
                points = bms.data.PointResolver.fromConfig(cfg, spec.pointKeys{i}, {});
                if ~isempty(points)
                    return;
                end
            end
            points = spec.defaultPoints;
        end

        function subfolder = resolveSubfolder(cfg, spec)
            subfolder = '';
            for i = 1:numel(spec.subfolderKeys)
                subfolder = bms.config.ConfigReader.getSubfolder(cfg, spec.subfolderKeys{i}, '');
                if ~isempty(subfolder)
                    return;
                end
            end
            subfolder = spec.defaultSubfolder;
        end

        function style = plotStyle(cfg, spec)
            style = bms.config.ConfigReader.getPlotStyle(cfg, spec.styleKey, spec.defaultStyle);
        end

        function value = param(cfg, spec, field, defaultValue)
            params = bms.config.ConfigReader.getStruct(cfg, spec.paramsKey, struct());
            value = bms.config.ConfigReader.getField(params, field, defaultValue);
        end

        function [freqs, labels] = theoreticalFrequencies(cfg, spec)
            params = bms.config.ConfigReader.getStruct(cfg, spec.paramsKey, struct());
            freqs = bms.config.ConfigReader.getField(params, 'theor_freqs', []);
            labels = bms.config.ConfigReader.getField(params, 'theor_labels', {});
            labels = bms.analyzer.SpectrumConfigService.normalizeTheorLabels(labels, freqs);
        end

        function [freqs, tol, theorFreqs, theorLabels] = pointParams(cfg, pid, spec, defaultFreqs, defaultTol, defaultTheorFreqs, defaultTheorLabels)
            freqs = defaultFreqs;
            tol = defaultTol;
            theorFreqs = defaultTheorFreqs;
            theorLabels = defaultTheorLabels;

            pt = bms.analyzer.SpectrumConfigService.pointConfig(cfg, spec.perPointKey, pid);
            if isstruct(pt)
                freqs = bms.config.ConfigReader.getField(pt, 'target_freqs', freqs);
                tol = bms.config.ConfigReader.getField(pt, 'tolerance', tol);
                theorFreqs = bms.config.ConfigReader.getField(pt, 'theor_freqs', theorFreqs);
                theorLabels = bms.config.ConfigReader.getField(pt, 'theor_labels', theorLabels);
            end
            theorLabels = bms.analyzer.SpectrumConfigService.normalizeTheorLabels(theorLabels, theorFreqs);
        end

        function pt = pointConfig(cfg, perPointKey, pid)
            pt = [];
            if ~isstruct(cfg) || ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point) || ...
                    ~isfield(cfg.per_point, perPointKey) || ~isstruct(cfg.per_point.(perPointKey))
                return;
            end
            perPoint = cfg.per_point.(perPointKey);
            candidates = {char(string(pid)), strrep(char(string(pid)), '-', '_'), bms.data.PointResolver.safeId(pid)};
            candidates = unique(candidates, 'stable');
            for i = 1:numel(candidates)
                if isfield(perPoint, candidates{i})
                    pt = perPoint.(candidates{i});
                    return;
                end
            end
        end

        function labels = normalizeTheorLabels(labels, freqs)
            if isempty(freqs)
                labels = {};
                return;
            end
            if isstring(labels)
                labels = cellstr(labels(:));
            elseif ischar(labels)
                labels = {labels};
            elseif ~iscell(labels)
                labels = {};
            end
            if numel(labels) ~= numel(freqs)
                labels = arrayfun(@(f) sprintf('理论频率 %.3fHz', f), freqs(:), 'UniformOutput', false);
            end
        end

        function dirs = ensureOutputDirs(rootDir, spec)
            dirs.freqRoot = fullfile(rootDir, spec.freqOutputDir);
            dirs.psdRoot = fullfile(rootDir, spec.psdOutputDir);
            bms.core.PathResolver.ensureDir(dirs.freqRoot);
            bms.core.PathResolver.ensureDir(dirs.psdRoot);

            if spec.includeForce
                dirs.forceRoot = fullfile(rootDir, spec.forceOutputDir);
                dirs.forceGroupRoot = fullfile(rootDir, spec.forceGroupOutputDir);
                bms.core.PathResolver.ensureDir(dirs.forceRoot);
                bms.core.PathResolver.ensureDir(dirs.forceGroupRoot);
            end
        end
    end
end
