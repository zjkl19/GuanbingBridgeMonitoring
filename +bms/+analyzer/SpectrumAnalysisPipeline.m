classdef SpectrumAnalysisPipeline
    %SPECTRUMANALYSISPIPELINE Shared acceleration/cable spectrum workflow.

    methods (Static)
        function run(kind, rootDir, startDate, endDate, pointIds, excelFile, subfolder, targetFreqs, tolerance, useParallel, cfg)
            spec = bms.analyzer.SpectrumAnalysisPipeline.spec(kind);

            if nargin < 2 || isempty(rootDir), rootDir = pwd; end
            if nargin < 3 || isempty(startDate), error('必须指定 start_date'); end
            if nargin < 4 || isempty(endDate), error('必须指定 end_date'); end
            if nargin < 11 || isempty(cfg), cfg = load_config(); end
            if nargin < 5 || isempty(pointIds)
                pointIds = bms.analyzer.SpectrumAnalysisPipeline.resolvePoints(cfg, spec);
            else
                pointIds = bms.data.PointResolver.normalize(pointIds);
            end
            if nargin < 6 || isempty(excelFile), excelFile = spec.defaultExcel; end
            if nargin < 7 || isempty(subfolder)
                subfolder = bms.analyzer.SpectrumAnalysisPipeline.resolveSubfolder(cfg, spec);
            end
            if nargin < 8 || isempty(targetFreqs)
                targetFreqs = bms.analyzer.SpectrumAnalysisPipeline.param(cfg, spec, 'target_freqs', spec.defaultTargetFreqs);
            end
            if nargin < 9 || isempty(tolerance)
                tolerance = bms.analyzer.SpectrumAnalysisPipeline.param(cfg, spec, 'tolerance', spec.defaultTolerance);
            end
            if nargin < 10 || isempty(useParallel), useParallel = false; end

            rootDir = char(rootDir);
            excelFile = resolve_data_output_path(rootDir, excelFile, 'stats');
            if isfile(excelFile)
                delete(excelFile);
            end
            style = bms.analyzer.SpectrumAnalysisPipeline.plotStyle(cfg, spec);
            dirs = bms.analyzer.SpectrumAnalysisPipeline.ensureOutputDirs(rootDir, spec, style);
            datesAll = (datetime(startDate):days(1):datetime(endDate)).';
            [theorFreqs, theorLabels] = bms.analyzer.SpectrumAnalysisPipeline.theoreticalFrequencies(cfg, spec);

            if useParallel
                p = gcp('nocreate');
                if isempty(p), parpool('local'); end
            end

            nPts = numel(pointIds);
            freqSeriesAll = cell(nPts, 1);
            freqValidAll = false(nPts, 1);
            targetFreqsAll = cell(nPts, 1);
            theorFreqsAll = cell(nPts, 1);
            theorLabelsAll = cell(nPts, 1);
            peakLabelsAll = cell(nPts, 1);
            forceSeriesAll = cell(nPts, 1);
            forceValidAll = false(nPts, 1);

            for i = 1:nPts
                pid = pointIds{i};
                fprintf('\n---- 测点 %s ----\n', pid);

                [targetFreqsPt, tolerancePt, theorFreqsPt, theorLabelsPt, peakLabelsPt] = ...
                    bms.analyzer.SpectrumAnalysisPipeline.pointParams( ...
                        cfg, pid, spec, targetFreqs, tolerance, theorFreqs, theorLabels);
                [ampDay, freqDay] = bms.analyzer.SpectrumAnalysisPipeline.processPoint( ...
                    datesAll, pid, rootDir, subfolder, targetFreqsPt, tolerancePt, dirs.psdRoot, style, cfg, spec, useParallel);

                freqSeriesAll{i} = freqDay;
                freqValidAll(i) = ~isempty(freqDay) && any(isfinite(freqDay), 'all');
                targetFreqsAll{i} = targetFreqsPt;
                theorFreqsAll{i} = theorFreqsPt;
                theorLabelsAll{i} = theorLabelsPt;
                peakLabelsAll{i} = peakLabelsPt;

                forceSeries = [];
                if spec.includeForce
                    [forceSeries, forceWarnLines, forceYLim, hasForceParams] = ...
                        bms.analyzer.SpectrumAnalysisPipeline.cableForceSeries(cfg, pid, freqDay, style);
                    forceSeriesAll{i} = forceSeries;
                    forceValidAll(i) = any(isfinite(forceSeries));
                    if ~hasForceParams
                        warning('测点 %s 未配置 rho/L，索力将为 NaN', pid);
                    end
                end

                bms.analyzer.SpectrumAnalysisPipeline.writePointSheet( ...
                    datesAll, freqDay, ampDay, forceSeries, targetFreqsPt, excelFile, spec.moduleKey, pid);
                bms.analyzer.SpectrumAnalysisPipeline.plotFrequencyTimeseries( ...
                    datesAll, freqDay, pid, targetFreqsPt, dirs.freqRoot, style, theorFreqsPt, theorLabelsPt, cfg, peakLabelsPt);

                if spec.includeForce
                    bms.analyzer.SpectrumAnalysisPipeline.plotForceTimeseries( ...
                        {datesAll}, {forceSeries}, {pid}, pid, dirs.forceRoot, style, forceYLim, {forceWarnLines}, cfg);
                end
            end

            if isfield(spec, 'freqGroupKey') && ~isempty(spec.freqGroupKey) ...
                    && isfield(dirs, 'freqGroupRoot') && ~isempty(dirs.freqGroupRoot)
                bms.analyzer.SpectrumAnalysisPipeline.plotFrequencyGroups( ...
                    cfg, pointIds, datesAll, freqSeriesAll, freqValidAll, dirs.freqGroupRoot, style, ...
                    spec.freqGroupKey, targetFreqsAll, peakLabelsAll, theorFreqsAll, theorLabelsAll);
            end

            if spec.includeForce
                bms.analyzer.SpectrumAnalysisPipeline.plotCableForceGroups( ...
                    cfg, pointIds, datesAll, forceSeriesAll, forceValidAll, dirs.forceGroupRoot, style);
            end

            fprintf('✓ 已输出 Excel -> %s\n', excelFile);
        end

        function spec = spec(kind)
            defaultPoints = { ...
                'GB-VIB-G04-001-01', 'GB-VIB-G05-001-01', 'GB-VIB-G05-002-01', 'GB-VIB-G05-003-01', ...
                'GB-VIB-G06-001-01', 'GB-VIB-G06-002-01', 'GB-VIB-G06-003-01', 'GB-VIB-G07-001-01'};
            baseStyle = struct( ...
                'psd_ylabel', 'PSD (dB)', ...
                'psd_title_prefix', 'PSD', ...
                'psd_color', [0 0 0], ...
                'freq_ylabel', '峰值频率 (Hz)', ...
                'freq_title_prefix', '峰值频率时程', ...
                'colors', {{[0 0 1], [1 0 0], [0 0.7 0], [0.5 0 0.7]}});

            kind = lower(char(string(kind)));
            switch kind
                case {'accel_spectrum', 'acceleration_spectrum'}
                    spec.moduleKey = 'accel_spectrum';
                    spec.sensorType = 'acceleration';
                    spec.pointKeys = {'accel_spectrum', 'acceleration'};
                    spec.paramsKey = 'accel_spectrum_params';
                    spec.perPointKey = 'accel_spectrum';
                    spec.styleKey = 'accel_spectrum';
                    spec.defaultExcel = 'accel_spec_stats.xlsx';
                    spec.subfolderKeys = {'acceleration_raw'};
                    spec.defaultSubfolder = '波形';
                    spec.freqOutputDir = '频谱峰值曲线_加速度';
                    spec.freqGroupOutputDir = '频谱峰值曲线_加速度_组图';
                    spec.freqGroupKey = 'acceleration';
                    spec.psdOutputDir = 'PSD_备查';
                    spec.defaultTargetFreqs = [1.150 1.480 2.310];
                    spec.defaultTolerance = 0.15;
                    spec.defaultPoints = defaultPoints;
                    spec.defaultStyle = baseStyle;
                    spec.includeForce = false;
                case {'cable_accel_spectrum', 'cable_acceleration_spectrum'}
                    forceStyle = struct( ...
                        'force_ylabel', '索力 (kN)', ...
                        'force_title_prefix', '索力时程', ...
                        'force_color', [0 0.447 0.741], ...
                        'force_ylim', [], ...
                        'force_alarm_colors', [0.929 0.694 0.125; 0.85 0.1 0.1]);
                    spec.moduleKey = 'cable_accel_spectrum';
                    spec.sensorType = 'cable_accel';
                    spec.pointKeys = {'cable_accel_spectrum', 'cable_accel', 'cable_force'};
                    spec.paramsKey = 'cable_accel_spectrum_params';
                    spec.perPointKey = 'cable_accel';
                    spec.styleKey = 'cable_accel_spectrum';
                    spec.defaultExcel = 'cable_accel_spec_stats.xlsx';
                    spec.subfolderKeys = {'cable_accel_raw', 'cable_accel'};
                    spec.defaultSubfolder = '索力加速度';
                    spec.freqOutputDir = '频谱峰值曲线_索力加速度';
                    spec.psdOutputDir = 'PSD_备查_索力加速度';
                    spec.forceOutputDir = '索力时程图';
                    spec.forceGroupOutputDir = '索力时程图_组图';
                    spec.forceGroupKey = 'cable_force';
                    spec.defaultTargetFreqs = [1.150 1.480 2.310];
                    spec.defaultTolerance = 0.15;
                    spec.defaultPoints = defaultPoints;
                    spec.defaultStyle = bms.config.ConfigReader.mergeStruct(baseStyle, forceStyle);
                    spec.includeForce = true;
                otherwise
                    error('SpectrumAnalysisPipeline:UnsupportedKind', 'Unsupported spectrum pipeline kind: %s', kind);
            end
        end

        function points = resolvePoints(varargin)
            points = bms.analyzer.SpectrumConfigService.resolvePoints(varargin{:});
        end

        function subfolder = resolveSubfolder(varargin)
            subfolder = bms.analyzer.SpectrumConfigService.resolveSubfolder(varargin{:});
        end

        function style = plotStyle(varargin)
            style = bms.analyzer.SpectrumConfigService.plotStyle(varargin{:});
        end

        function value = param(varargin)
            value = bms.analyzer.SpectrumConfigService.param(varargin{:});
        end

        function [freqs, labels] = theoreticalFrequencies(varargin)
            [freqs, labels] = bms.analyzer.SpectrumConfigService.theoreticalFrequencies(varargin{:});
        end

        function [freqs, tol, theorFreqs, theorLabels, peakLabels] = pointParams(varargin)
            [freqs, tol, theorFreqs, theorLabels, peakLabels] = bms.analyzer.SpectrumConfigService.pointParams(varargin{:});
        end

        function pt = pointConfig(varargin)
            pt = bms.analyzer.SpectrumConfigService.pointConfig(varargin{:});
        end

        function labels = normalizeTheorLabels(varargin)
            labels = bms.analyzer.SpectrumConfigService.normalizeTheorLabels(varargin{:});
        end

        function dirs = ensureOutputDirs(varargin)
            dirs = bms.analyzer.SpectrumConfigService.ensureOutputDirs(varargin{:});
        end

        function [ampDay, freqDay] = processPoint(varargin)
            [ampDay, freqDay] = bms.analyzer.SpectrumPointService.processPoint(varargin{:});
        end

        function writePointSheet(varargin)
            bms.analyzer.SpectrumPointService.writePointSheet(varargin{:});
        end

        function [forceSeries, warnLines, forceYLim, hasParams] = cableForceSeries(varargin)
            [forceSeries, warnLines, forceYLim, hasParams] = bms.analyzer.SpectrumPointService.cableForceSeries(varargin{:});
        end

        function plotFrequencyTimeseries(varargin)
            bms.analyzer.SpectrumPlotService.plotFrequencyTimeseries(varargin{:});
        end

        function plotFrequencyGroups(varargin)
            bms.analyzer.SpectrumPlotService.plotFrequencyGroups(varargin{:});
        end

        function applyFrequencyYLim(varargin)
            bms.analyzer.SpectrumPlotService.applyFrequencyYLim(varargin{:});
        end

        function drawTheoreticalLines(varargin)
            bms.analyzer.SpectrumPlotService.drawTheoreticalLines(varargin{:});
        end

        function plotForceTimeseries(varargin)
            bms.analyzer.SpectrumPlotService.plotForceTimeseries(varargin{:});
        end

        function allWarnLines = drawWarnLines(varargin)
            allWarnLines = bms.analyzer.SpectrumPlotService.drawWarnLines(varargin{:});
        end

        function applyForceYLim(varargin)
            bms.analyzer.SpectrumPlotService.applyForceYLim(varargin{:});
        end

        function vals = warnValues(varargin)
            vals = bms.analyzer.SpectrumPlotService.warnValues(varargin{:});
        end

        function plotCableForceGroups(varargin)
            bms.analyzer.SpectrumPlotService.plotCableForceGroups(varargin{:});
        end

        function name = groupDisplayName(varargin)
            name = bms.analyzer.SpectrumPlotService.groupDisplayName(varargin{:});
        end

        function colors = normalizeColors(varargin)
            colors = bms.analyzer.SpectrumPlotService.normalizeColors(varargin{:});
        end
    end
end
