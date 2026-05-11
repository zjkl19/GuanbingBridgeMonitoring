classdef WindAnalysisPipeline
    %WINDANALYSISPIPELINE Shared wind speed/direction analysis workflow.

    methods (Static)
        function run(rootDir, startDate, endDate, subfolder, cfg)
            if nargin < 1 || isempty(rootDir), rootDir = pwd; end
            if nargin < 2 || isempty(startDate), startDate = input('开始日期 (yyyy-MM-dd): ', 's'); end
            if nargin < 3 || isempty(endDate), endDate = input('结束日期 (yyyy-MM-dd): ', 's'); end
            if nargin < 5 || isempty(cfg), cfg = load_config(); end
            if nargin < 4 || isempty(subfolder)
                subfolder = bms.analyzer.WindAnalysisPipeline.resolveSubfolder(cfg);
            end

            timeStart = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
            fprintf('开始时间: %s\n', char(timeStart));

            points = bms.analyzer.WindAnalysisPipeline.resolvePoints(cfg);
            style = bms.analyzer.WindAnalysisPipeline.style(cfg);
            stats = cell(numel(points), 6);
            statsFile = resolve_data_output_path(rootDir, ...
                bms.analyzer.WindAnalysisPipeline.statsFileName(cfg), 'stats');

            outRoot = fullfile(rootDir, style.output.root_dir);
            bms.core.PathResolver.ensureDir(outRoot);

            for i = 1:numel(points)
                pid = points{i};
                fprintf('处理测点 %s ...\n', pid);
                [row, series] = bms.analyzer.WindSeriesService.analyzePoint( ...
                    rootDir, subfolder, pid, startDate, endDate, cfg);
                stats(i, :) = row;
                bms.analyzer.WindPlotService.plotPoint(series, style, outRoot, startDate, endDate, cfg);
            end

            T = bms.analyzer.DynamicSeriesService.windStatsTable(stats);
            bms.io.StatsWriter.writeModuleTableChecked(T, statsFile, 'wind');
            fprintf('Wind stats saved to %s\n', statsFile);

            timeEnd = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
            fprintf('结束时间: %s\n', char(timeEnd));
            elapsed = seconds(timeEnd - timeStart);
            fprintf('总用时: %.2f 秒\n', elapsed);
        end

        function subfolder = resolveSubfolder(cfg)
            subfolder = bms.analyzer.WindSeriesService.resolveSubfolder(cfg);
        end

        function points = resolvePoints(cfg)
            points = bms.analyzer.WindSeriesService.resolvePoints(cfg);
        end

        function statsFile = statsFileName(cfg)
            statsFile = bms.analyzer.WindSeriesService.statsFileName(cfg);
        end

        function row = analyzePoint(rootDir, subfolder, pid, startDate, endDate, cfg, style, outRoot)
            [row, series] = bms.analyzer.WindSeriesService.analyzePoint( ...
                rootDir, subfolder, pid, startDate, endDate, cfg);
            if nargin >= 8
                bms.analyzer.WindPlotService.plotPoint(series, style, outRoot, startDate, endDate, cfg);
            end
        end

        function plotSpeedTimeseries(varargin)
            bms.analyzer.WindPlotService.plotSpeedTimeseries(varargin{:});
        end

        function plotDirectionTimeseries(varargin)
            bms.analyzer.WindPlotService.plotDirectionTimeseries(varargin{:});
        end

        function plotSpeed10min(varargin)
            bms.analyzer.WindPlotService.plotSpeed10min(varargin{:});
        end

        function plotWindRose(varargin)
            bms.analyzer.WindPlotService.plotWindRose(varargin{:});
        end

        function colors = roseColors(varargin)
            colors = bms.analyzer.WindPlotService.roseColors(varargin{:});
        end

        function drawWindRose(varargin)
            bms.analyzer.WindPlotService.drawWindRose(varargin{:});
        end

        function drawAnnularSector(varargin)
            bms.analyzer.WindPlotService.drawAnnularSector(varargin{:});
        end

        function drawPolarGrid(varargin)
            bms.analyzer.WindPlotService.drawPolarGrid(varargin{:});
        end

        function drawDirectionLabels(varargin)
            bms.analyzer.WindPlotService.drawDirectionLabels(varargin{:});
        end

        function savePlot(varargin)
            bms.analyzer.WindPlotService.savePlot(varargin{:});
        end

        function style = style(cfg)
            style = bms.analyzer.WindPlotService.style(cfg);
        end

        function params = params(cfg, pid)
            params = bms.analyzer.WindSeriesService.params(cfg, pid);
        end

        function params = mergeWindParams(params, override)
            params = bms.analyzer.WindSeriesService.mergeWindParams(params, override);
        end

        function out = mergeStruct(base, override)
            out = bms.config.ConfigReader.mergeStruct(base, override);
        end
    end
end
