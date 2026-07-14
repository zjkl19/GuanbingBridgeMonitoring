classdef DynamicAccelerationPipeline
    %DYNAMICACCELERATIONPIPELINE Shared pipeline for acceleration-like modules.

    methods (Static)
        function run(kind, rootDir, startDate, endDate, excelFile, subfolder, autoDetectFs, cfg)
            spec = bms.analyzer.DynamicAccelerationPipeline.spec(kind);
            if nargin < 2 || isempty(rootDir), rootDir = pwd; end
            if nargin < 3 || isempty(startDate), startDate = input('开始日期 (yyyy-MM-dd): ', 's'); end
            if nargin < 4 || isempty(endDate), endDate = input('结束日期 (yyyy-MM-dd): ', 's'); end
            if nargin < 5 || isempty(excelFile), excelFile = spec.defaultStatsFile; end
            if nargin < 7 || isempty(autoDetectFs), autoDetectFs = false; end
            if nargin < 8 || isempty(cfg), cfg = load_config(); end

            rootDir = char(rootDir);
            excelFile = resolve_data_output_path(rootDir, excelFile, 'stats');
            if nargin < 6 || isempty(subfolder)
                subfolder = bms.config.ConfigReader.getSubfolder(cfg, spec.subfolderKey, spec.defaultSubfolder);
            end
            cfg = bms.analyzer.DynamicAccelerationSeriesService.modulePlotConfig(cfg, spec);

            timeStart = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
            fprintf('开始时间: %s\n', char(timeStart));

            points = bms.analyzer.DynamicAccelerationPipeline.resolvePoints(cfg, spec);
            style = bms.analyzer.DynamicAccelerationPipeline.plotStyle(cfg, spec);
            stats = cell(numel(points), 6);

            if spec.keepSeries
                stats = bms.analyzer.DynamicAccelerationPipeline.runSequential( ...
                    rootDir, subfolder, startDate, endDate, cfg, autoDetectFs, points, style, stats, spec);
            else
                stats = bms.analyzer.DynamicAccelerationPipeline.runWithOptionalParallel( ...
                    rootDir, subfolder, startDate, endDate, cfg, autoDetectFs, points, style, stats, spec);
            end

            tableOut = bms.analyzer.DynamicSeriesService.dynamicStatsTable(stats);
            bms.io.StatsWriter.writeModuleTableChecked(tableOut, excelFile, spec.moduleKey);
            fprintf('统计结果已保存至 %s\n', excelFile);

            timeEnd = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
            fprintf('结束时间: %s\n', char(timeEnd));
            fprintf('总用时 %.2f 秒\n', seconds(timeEnd - timeStart));
        end

        function stats = runSequential(varargin)
            stats = bms.analyzer.DynamicAccelerationSeriesService.runSequential(varargin{:});
        end

        function stats = runWithOptionalParallel(varargin)
            stats = bms.analyzer.DynamicAccelerationSeriesService.runWithOptionalParallel(varargin{:});
        end

        function rec = collectRecord(varargin)
            rec = bms.analyzer.DynamicAccelerationSeriesService.collectRecord(varargin{:});
        end

        function printSampleRate(varargin)
            bms.analyzer.DynamicAccelerationSeriesService.printSampleRate(varargin{:});
        end

        function points = resolvePoints(varargin)
            points = bms.analyzer.DynamicAccelerationSeriesService.resolvePoints(varargin{:});
        end

        function style = plotStyle(varargin)
            style = bms.analyzer.DynamicAccelerationSeriesService.plotStyle(varargin{:});
        end

        function plotAccelCurve(varargin)
            bms.analyzer.DynamicAccelerationPlotService.plotAccelCurve(varargin{:});
        end

        function plotRmsCurve(varargin)
            bms.analyzer.DynamicAccelerationPlotService.plotRmsCurve(varargin{:});
        end

        function applyMainYLim(varargin)
            bms.analyzer.DynamicAccelerationPlotService.applyMainYLim(varargin{:});
        end

        function applyRmsYLim(varargin)
            bms.analyzer.DynamicAccelerationPlotService.applyRmsYLim(varargin{:});
        end

        function applyTimeAxis(varargin)
            bms.analyzer.DynamicAccelerationPlotService.applyTimeAxis(varargin{:});
        end

        function applyTimeAxisLimits(varargin)
            bms.analyzer.DynamicAccelerationPlotService.applyTimeAxisLimits(varargin{:});
        end

        function spec = spec(kind)
            defaultPoints = { ...
                'GB-VIB-G04-001-01', 'GB-VIB-G05-001-01', 'GB-VIB-G05-002-01', 'GB-VIB-G05-003-01', ...
                'GB-VIB-G06-001-01', 'GB-VIB-G06-002-01', 'GB-VIB-G06-003-01', 'GB-VIB-G07-001-01'};
            kind = lower(char(string(kind)));
            switch kind
                case {'acceleration', 'accel'}
                    spec.moduleKey = 'acceleration';
                    spec.sensorType = 'acceleration';
                    spec.parallelLabel = 'acceleration';
                    spec.displayName = '加速度';
                    spec.pointKeys = {'acceleration'};
                    spec.styleKey = 'acceleration';
                    spec.groupKey = 'acceleration';
                    spec.subfolderKey = 'acceleration';
                    spec.defaultSubfolder = '波形_重采样';
                    spec.defaultStatsFile = 'accel_stats.xlsx';
                    spec.filePrefix = 'Accel';
                    spec.outputDir = '时程曲线_加速度';
                    spec.groupOutputDir = '时程曲线_加速度_组图';
                    spec.rmsOutputDir = '时程曲线_加速度_RMS10min';
                    spec.rmsGroupOutputDir = '时程曲线_加速度_RMS10min_组图';
                    spec.rmsFilePrefix = 'AccelRMS10';
                    spec.envelopeEnabled = false;
                    spec.envelopeOutputDir = [char([26102 31243 26354 32447]) '_' char([32034 21147 21152 36895 24230]) '_' char([21253 32476]) '30min'];
                    spec.envelopeFilePrefix = '';
                    spec.envelopeBinMinutes = 30;
                    spec.groupWarnField = 'group_warn_lines';
                    spec.keepSeries = true;
                    spec.defaultPoints = defaultPoints;
                    spec.defaultStyle = struct('ylabel', '主梁竖向振动加速度 (m/s^2)', ...
                        'title_prefix', '加速度时程', ...
                        'ylim_auto', false, ...
                        'ylim', [], ...
                        'ylims', [], ...
                        'color_main', [0 0.447 0.741], ...
                        'color_rms', [0.8500 0.3250 0.0980], ...
                        'rms_ylabel', '10 min RMS (m/s^2)', ...
                        'rms_title_prefix', '10 min RMS 时程', ...
                        'rms_ylim_auto', false, ...
                        'rms_ylim', [], ...
                        'rms_ylims', []);
                case {'cable_accel', 'cable_acceleration'}
                    spec.moduleKey = 'cable_accel';
                    spec.sensorType = 'cable_accel';
                    spec.parallelLabel = 'cable_accel';
                    spec.displayName = '索力加速度';
                    spec.pointKeys = {'cable_accel', 'cable_force'};
                    spec.styleKey = 'cable_accel';
                    spec.groupKey = 'cable_accel';
                    spec.subfolderKey = 'cable_accel';
                    spec.defaultSubfolder = '索力加速度_重采样';
                    spec.defaultStatsFile = 'cable_accel_stats.xlsx';
                    spec.filePrefix = 'CableAccel';
                    spec.outputDir = '时程曲线_索力加速度';
                    spec.groupOutputDir = '时程曲线_索力加速度_组图';
                    spec.rmsOutputDir = '时程曲线_索力加速度_RMS10min';
                    spec.rmsGroupOutputDir = '时程曲线_索力加速度_RMS10min_组图';
                    spec.rmsFilePrefix = 'CableAccelRMS10';
                    spec.envelopeEnabled = true;
                    spec.envelopeOutputDir = [char([26102 31243 26354 32447]) '_' char([32034 21147 21152 36895 24230]) '_' char([21253 32476]) '30min'];
                    spec.envelopeFilePrefix = 'CableAccelEnvelope30';
                    spec.envelopeBinMinutes = 30;
                    spec.groupWarnField = 'group_warn_lines';
                    spec.keepSeries = false;
                    spec.defaultPoints = defaultPoints;
                    spec.defaultStyle = struct('ylabel', '索力加速度 (mm/s^2)', ...
                        'title_prefix', '索力加速度时程', ...
                        'ylim_auto', false, ...
                        'ylim', [], ...
                        'ylims', [], ...
                        'color_main', [0 0.447 0.741], ...
                        'color_rms', [0.8500 0.3250 0.0980], ...
                        'rms_ylabel', '10 min RMS (mm/s^2)', ...
                        'rms_title_prefix', '10 min RMS 时程', ...
                        'rms_ylim_auto', false, ...
                        'rms_ylim', [], ...
                        'rms_ylims', [], ...
                        'envelope_title_prefix', ['30 min ' char([21253 32476]) '/RMS'], ...
                        'envelope_bin_minutes', 30);
                otherwise
                    error('DynamicAccelerationPipeline:UnsupportedKind', 'Unsupported acceleration pipeline kind: %s', kind);
            end
        end
    end
end
