classdef DynamicStrainBoxplotPipeline
    %DYNAMICSTRAINBOXPLOTPIPELINE Shared orchestration for dynamic strain boxplots.

    methods (Static)
        function run(mode, rootDir, startDate, endDate, varargin)
            spec = bms.analyzer.DynamicStrainBoxplotPipeline.modeSpec(mode);
            opt = bms.analyzer.DynamicStrainBoxplotPipeline.parseInputs(rootDir, startDate, endDate, varargin{:});

            rootDir = char(opt.root_dir);
            dt0 = datetime(opt.start_date, 'InputFormat', 'yyyy-MM-dd');
            dt1 = datetime(opt.end_date, 'InputFormat', 'yyyy-MM-dd');
            startStr = char(string(dt0, 'yyyy-MM-dd'));
            endStr = char(string(dt1, 'yyyy-MM-dd'));
            tag = sprintf('%s-%s', char(string(dt0, 'yyyyMMdd')), char(string(dt1, 'yyyyMMdd')));
            timestamp = char(string(datetime('now'), 'yyyy-MM-dd_HH-mm-ss'));

            cfg = bms.analyzer.DynamicStrainBoxplotPipeline.loadConfig(opt.Cfg);
            ds = bms.analyzer.DynamicStrainBoxplotPipeline.dynamicConfig(cfg, spec);
            bms.analyzer.DynamicStrainBoxplotPipeline.applyPlotCommonRuntime(cfg);
            [groups, groupNames, style] = bms.analyzer.DynamicStrainBoxplotPipeline.groupsAndStyle(cfg, spec);
            if ~isempty(opt.Subfolder)
                subfolder = char(opt.Subfolder);
            else
                subfolder = bms.config.ConfigReader.getSubfolder(cfg, 'strain', '特征值');
            end

            outDir = bms.analyzer.DynamicStrainBoxplotPipeline.resolveDir(rootDir, opt.OutputDir, spec.defaultOutputDir);
            outDirTsSingle = bms.analyzer.DynamicStrainBoxplotPipeline.resolveTimeseriesSingleDir(rootDir, opt.OutputDirTs, style, spec);
            outDirTsGroup = bms.analyzer.DynamicStrainBoxplotPipeline.resolveTimeseriesGroupDir(rootDir, outDirTsSingle, style);
            statsFile = bms.analyzer.DynamicStrainBoxplotPipeline.resolveStatsFile(rootDir, opt.StatsFile, spec.defaultStatsFile);
            bms.core.PathResolver.ensureDir(outDir);
            bms.core.PathResolver.ensureDir(outDirTsSingle);
            bms.core.PathResolver.ensureDir(outDirTsGroup);
            if isfile(statsFile)
                delete(statsFile);
            end

            fprintf('日期范围: %s ~ %s\n', startStr, endStr);
            fprintf('数据目录: %s\\YYYY-MM-DD\\%s\n', rootDir, subfolder);

            plottedPointIds = {};
            for gi = 1:numel(groups)
                bms.app.StopController.throwIfRequested('Stop requested before next dynamic strain group');
                groupName = groupNames{gi};
                fprintf('\n== 处理分组 %s ==\n', groupName);
                [dataMat, labels, tsList] = bms.analyzer.DynamicStrainBoxplotPipeline.collectGroupData( ...
                    rootDir, subfolder, startStr, endStr, groups{gi}, ds, cfg, spec);
                ylimGroup = bms.analyzer.DynamicStrainBoxplotPipeline.groupYLim(style, groupName, ds);
                plottedPointIds = bms.analyzer.DynamicStrainPlotService.plotPointTimeseriesList( ...
                    tsList, labels, outDirTsSingle, dt0, dt1, ds, spec, ylimGroup, tag, timestamp, cfg, plottedPointIds);
                bms.analyzer.DynamicStrainBoxplotPipeline.makeBoxplotAndStats( ...
                    dataMat, labels, groupName, outDir, statsFile, ds, spec, tag, timestamp, dt0, dt1, cfg);
                bms.analyzer.DynamicStrainBoxplotPipeline.plotTimeseriesGroup( ...
                    tsList, labels, groupName, outDirTsGroup, dt0, dt1, ds, spec, ylimGroup, tag, timestamp, cfg);
            end

            fprintf('\n全部完成。\n');
        end

        function opt = parseInputs(varargin)
            opt = bms.analyzer.DynamicStrainConfigService.parseInputs(varargin{:});
        end

        function cfg = loadConfig(varargin)
            cfg = bms.analyzer.DynamicStrainConfigService.loadConfig(varargin{:});
        end

        function spec = modeSpec(varargin)
            spec = bms.analyzer.DynamicStrainConfigService.modeSpec(varargin{:});
        end

        function ds = dynamicConfig(varargin)
            ds = bms.analyzer.DynamicStrainConfigService.dynamicConfig(varargin{:});
        end

        function [groups, names, style] = groupsAndStyle(varargin)
            [groups, names, style] = bms.analyzer.DynamicStrainConfigService.groupsAndStyle(varargin{:});
        end

        function [dataMat, labels, tsList] = collectGroupData(varargin)
            [dataMat, labels, tsList] = bms.analyzer.DynamicStrainSeriesService.collectGroupData(varargin{:});
        end

        function makeBoxplotAndStats(varargin)
            bms.analyzer.DynamicStrainPlotService.makeBoxplotAndStats(varargin{:});
        end

        function plotTimeseriesGroup(varargin)
            bms.analyzer.DynamicStrainPlotService.plotTimeseriesGroup(varargin{:});
        end

        function writeStatsTxt(varargin)
            bms.analyzer.DynamicStrainPlotService.writeStatsTxt(varargin{:});
        end

        function ylimValue = groupYLim(varargin)
            ylimValue = bms.analyzer.DynamicStrainConfigService.groupYLim(varargin{:});
        end

        function applyPlotCommonRuntime(varargin)
            bms.analyzer.DynamicStrainConfigService.applyPlotCommonRuntime(varargin{:});
        end

        function path = resolveDir(varargin)
            path = bms.analyzer.DynamicStrainConfigService.resolveDir(varargin{:});
        end

        function path = resolveTimeseriesSingleDir(varargin)
            path = bms.analyzer.DynamicStrainConfigService.resolveTimeseriesSingleDir(varargin{:});
        end

        function path = resolveTimeseriesGroupDir(varargin)
            path = bms.analyzer.DynamicStrainConfigService.resolveTimeseriesGroupDir(varargin{:});
        end

        function path = resolveStatsFile(varargin)
            path = bms.analyzer.DynamicStrainConfigService.resolveStatsFile(varargin{:});
        end

        function tf = isAbsolutePath(varargin)
            tf = bms.analyzer.DynamicStrainConfigService.isAbsolutePath(varargin{:});
        end
    end
end
